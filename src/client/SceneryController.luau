--[[
	SceneryController.luau
	The night outside the glass. The train never moves; the world does.
	Deterministic chunks (seeded per run) stream past: pine valleys,
	marshes, dead fields, freight yards, trestle gorges over black water,
	and tunnels that swallow the line whole. A far ridge line drifts at
	parallax speed under a standing moon.

	Track-space: a point on the ground at track coordinate s sits at
	worldX = s - distance. The train occupies worldX 0..(Cars*Pitch).
	Everything here is client-local: zero replication cost.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Forge = require(Shared.Forge)
local Palette = require(Shared.Palette)
local RunPlan = require(Shared.RunPlan)
local SoundBank = require(Shared.SoundBank)
local ClientState = require(script.Parent:WaitForChild("ClientState"))

local SceneryController = {}

local M = Palette.M
local CHUNK = Config.Scenery.ChunkLength -- 96
local AHEAD = Config.Scenery.ChunksAhead
local BEHIND = Config.Scenery.ChunksBehind
local FAR_PITCH = 384
local GROUND_Y = 5.6
local RAIL_TOP = 6.8

local root = nil
local chunkFolder = nil
local farFolder = nil
local fxFolder = nil
local moon = nil

local chunks = {}    -- index -> {model}
local farChunks = {} -- index -> {model}
local specials = {}  -- one-off set pieces pinned to track coordinates
local seed = 0

----------------------------------------------------------------
-- Piece builders (local coordinates: x in [0, CHUNK), z world)
----------------------------------------------------------------
local function pineTree(parent, rng, x, z)
	local h = rng:NextNumber(9, 22)
	local trunk = Forge.part({
		parent = parent, name = "Trunk",
		size = Vector3.new(0.8, h * 0.35, 0.8),
		cf = CFrame.new(x, GROUND_Y + h * 0.175, z),
		color = Palette.PineTrunk, material = M.Wood, cancollide = false, canquery = false,
	})
	for tier = 0, 2 do
		local w = (3.6 - tier) * (h / 14)
		Forge.part({
			parent = parent, name = "Canopy",
			size = Vector3.new(w * 2, h * 0.28, w * 2),
			cf = CFrame.new(x, GROUND_Y + h * (0.4 + tier * 0.2), z) * CFrame.Angles(0, rng:NextNumber(0, 1.5), 0),
			color = Palette.PineDark, material = M.Grass, cancollide = false, canquery = false,
		})
	end
	return trunk
end

local function telegraphPole(parent, x, z)
	Forge.part({
		parent = parent, name = "Pole",
		size = Vector3.new(0.5, 13, 0.5),
		cf = CFrame.new(x, GROUND_Y + 6.5, z),
		color = Palette.SnagWood, material = M.Wood, cancollide = false, canquery = false,
	})
	Forge.part({
		parent = parent, name = "Crossarm",
		size = Vector3.new(0.3, 0.3, 3.4),
		cf = CFrame.new(x, GROUND_Y + 11.6, z),
		color = Palette.SnagWood, material = M.Wood, cancollide = false, canquery = false,
	})
	-- sagging wire to the next pole
	Forge.part({
		parent = parent, name = "Wire",
		size = Vector3.new(CHUNK, 0.08, 0.08),
		cf = CFrame.new(x + CHUNK / 2, GROUND_Y + 11.1, z) * CFrame.Angles(0, 0, math.rad(1.2)),
		color = Color3.fromRGB(20, 20, 22), material = M.Metal, cancollide = false, canquery = false, castshadow = false,
	})
end

local function groundSlabs(parent, color, material)
	for _, side in ipairs({ -1, 1 }) do
		Forge.part({
			parent = parent, name = "Ground",
			size = Vector3.new(CHUNK, 1, 210),
			cf = CFrame.new(CHUNK / 2, GROUND_Y - 0.5, side * (105 + 5)),
			color = color, material = material, cancollide = false, canquery = false,
		})
	end
end

local function trackBed(parent)
	Forge.part({
		parent = parent, name = "BallastBed",
		size = Vector3.new(CHUNK, 0.9, 8),
		cf = CFrame.new(CHUNK / 2, GROUND_Y + 0.25, 0),
		color = Palette.Gravel, material = M.Slate, cancollide = false, canquery = false,
	})
	for k = 0, 9 do
		Forge.part({
			parent = parent, name = "Tie",
			size = Vector3.new(1.1, 0.35, 6.4),
			cf = CFrame.new(k * (CHUNK / 10) + 2, GROUND_Y + 0.75, 0),
			color = Palette.SleeperWood, material = M.Wood, cancollide = false, canquery = false, castshadow = false,
		})
	end
	for _, z in ipairs({ -2.35, 2.35 }) do
		Forge.part({
			parent = parent, name = "Rail",
			size = Vector3.new(CHUNK, 0.45, 0.4),
			cf = CFrame.new(CHUNK / 2, RAIL_TOP - 0.22, z),
			color = Palette.RailSteel, material = M.Metal, reflectance = 0.22,
			cancollide = false, canquery = false, castshadow = false,
		})
	end
end

----------------------------------------------------------------
-- Biome chunks
----------------------------------------------------------------
local Builders = {}

function Builders.pine(parent, rng)
	groundSlabs(parent, Palette.GroundNight, M.Grass)
	trackBed(parent)
	telegraphPole(parent, 8, -22)
	for _ = 1, rng:NextInteger(6, 11) do
		local side = rng:NextNumber() < 0.5 and -1 or 1
		pineTree(parent, rng, rng:NextNumber(2, CHUNK - 2), side * rng:NextNumber(26, 180))
	end
	if rng:NextNumber() < 0.12 then
		-- a leaning snag
		Forge.part({
			parent = parent, name = "Snag",
			size = Vector3.new(0.9, 14, 0.9),
			cf = CFrame.new(rng:NextNumber(10, 80), GROUND_Y + 6.5, rng:NextNumber(-60, -25))
				* CFrame.Angles(0, 0, rng:NextNumber(-0.2, 0.2)),
			color = Palette.SnagWood, material = M.Wood, cancollide = false, canquery = false,
		})
	end
end

function Builders.marsh(parent, rng)
	groundSlabs(parent, Color3.fromRGB(22, 28, 28), M.Mud)
	trackBed(parent)
	telegraphPole(parent, 8, -22)
	-- still water sheets
	for _ = 1, 2 do
		local side = rng:NextNumber() < 0.5 and -1 or 1
		Forge.part({
			parent = parent, name = "Water",
			size = Vector3.new(rng:NextNumber(30, 70), 0.2, rng:NextNumber(28, 70)),
			cf = CFrame.new(rng:NextNumber(15, 80), GROUND_Y + 0.18, side * rng:NextNumber(30, 120)),
			color = Palette.MarshWater, material = M.Glass,
			transparency = 0.12, reflectance = 0.42, cancollide = false, canquery = false,
		})
	end
	for _ = 1, rng:NextInteger(3, 6) do
		local side = rng:NextNumber() < 0.5 and -1 or 1
		local x, z = rng:NextNumber(4, CHUNK - 4), side * rng:NextNumber(24, 110)
		Forge.part({
			parent = parent, name = "DeadTree",
			size = Vector3.new(0.6, rng:NextNumber(7, 13), 0.6),
			cf = CFrame.new(x, GROUND_Y + 5, z) * CFrame.Angles(rng:NextNumber(-0.1, 0.1), 0, rng:NextNumber(-0.15, 0.15)),
			color = Palette.SnagWood, material = M.Wood, cancollide = false, canquery = false,
		})
	end
	-- fireflies
	local anchor = Forge.part({
		parent = parent, name = "FireflyAnchor",
		size = Vector3.new(1, 1, 1),
		cf = CFrame.new(CHUNK / 2, GROUND_Y + 5, -60),
		transparency = 1, cancollide = false, canquery = false, castshadow = false,
	})
	Forge.particles(anchor, {
		color = ColorSequence.new(Color3.fromRGB(200, 230, 120)),
		size = NumberSequence.new(0.12),
		transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		lifetime = NumberRange.new(2, 4),
		rate = 3,
		speed = NumberRange.new(0.4, 1.2),
		spread = Vector2.new(180, 40),
		lightEmission = 1,
		lightInfluence = 0,
	})
end

function Builders.fields(parent, rng)
	groundSlabs(parent, Color3.fromRGB(30, 32, 26), M.Grass)
	trackBed(parent)
	telegraphPole(parent, 8, -22)
	-- fence lines
	for _, side in ipairs({ -1, 1 }) do
		if rng:NextNumber() < 0.8 then
			local z = side * rng:NextNumber(24, 40)
			for px = 6, CHUNK - 6, 12 do
				Forge.part({
					parent = parent, name = "FencePost",
					size = Vector3.new(0.35, 2.4, 0.35),
					cf = CFrame.new(px, GROUND_Y + 1.2, z),
					color = Palette.SnagWood, material = M.Wood, cancollide = false, canquery = false,
				})
			end
			Forge.part({
				parent = parent, name = "FenceRail",
				size = Vector3.new(CHUNK, 0.25, 0.25),
				cf = CFrame.new(CHUNK / 2, GROUND_Y + 2, z),
				color = Palette.SnagWood, material = M.Wood, cancollide = false, canquery = false,
			})
		end
	end
	for _ = 1, rng:NextInteger(1, 3) do
		local side = rng:NextNumber() < 0.5 and -1 or 1
		Forge.ball({
			parent = parent, name = "Hay",
			size = Vector3.new(5, 3.4, 5),
			cf = CFrame.new(rng:NextNumber(8, CHUNK - 8), GROUND_Y + 1.4, side * rng:NextNumber(30, 90)),
			color = Color3.fromRGB(64, 58, 38), material = M.Grass, cancollide = false, canquery = false,
		})
	end
	if rng:NextNumber() < 0.16 then
		-- distant farmhouse, one window lit for someone long gone
		local z = (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(90, 150)
		local x = rng:NextNumber(15, 70)
		Forge.part({
			parent = parent, name = "House",
			size = Vector3.new(14, 8, 10),
			cf = CFrame.new(x, GROUND_Y + 4, z),
			color = Color3.fromRGB(20, 20, 24), material = M.Wood, cancollide = false, canquery = false,
		})
		Forge.wedge({
			parent = parent, name = "HouseRoof",
			size = Vector3.new(14, 4, 10),
			cf = CFrame.new(x, GROUND_Y + 10, z),
			color = Color3.fromRGB(16, 16, 18), material = M.Slate, cancollide = false, canquery = false,
		})
		if rng:NextNumber() < 0.5 then
			Forge.part({
				parent = parent, name = "WarmWindow",
				size = Vector3.new(0.2, 1.4, 1.1),
				cf = CFrame.new(x - 7, GROUND_Y + 4.5, z),
				color = Color3.fromRGB(255, 190, 110), material = M.Neon,
				cancollide = false, canquery = false, castshadow = false,
			})
		end
	end
end

function Builders.yard(parent, rng)
	groundSlabs(parent, Color3.fromRGB(34, 34, 36), M.Ground)
	trackBed(parent)
	-- dead siding with a wrecked boxcar
	if rng:NextNumber() < 0.6 then
		local z = -18
		Forge.part({
			parent = parent, name = "SidingRail",
			size = Vector3.new(CHUNK, 0.3, 0.3),
			cf = CFrame.new(CHUNK / 2, GROUND_Y + 0.4, z),
			color = Color3.fromRGB(60, 58, 56), material = M.CorrodedMetal, cancollide = false, canquery = false,
		})
		if rng:NextNumber() < 0.55 then
			local bx = rng:NextNumber(20, 70)
			Forge.part({
				parent = parent, name = "DeadCar",
				size = Vector3.new(26, 9, 9),
				cf = CFrame.new(bx, GROUND_Y + 4.8, z) * CFrame.Angles(0, 0, rng:NextNumber(-0.06, 0.02)),
				color = Color3.fromRGB(26, 22, 22), material = M.CorrodedMetal, cancollide = false, canquery = false,
			})
		end
	end
	-- sleeper stacks and drums
	for _ = 1, rng:NextInteger(2, 4) do
		local side = rng:NextNumber() < 0.5 and -1 or 1
		Forge.part({
			parent = parent, name = "TieStack",
			size = Vector3.new(8, rng:NextNumber(2, 4), 4),
			cf = CFrame.new(rng:NextNumber(8, CHUNK - 8), GROUND_Y + 1.6, side * rng:NextNumber(24, 60)),
			color = Palette.SleeperWood, material = M.Wood, cancollide = false, canquery = false,
		})
	end
	-- signal post with a patient red eye
	if rng:NextNumber() < 0.5 then
		local x = rng:NextNumber(10, CHUNK - 10)
		Forge.part({
			parent = parent, name = "SignalPost",
			size = Vector3.new(0.5, 11, 0.5),
			cf = CFrame.new(x, GROUND_Y + 5.5, 14),
			color = Color3.fromRGB(40, 42, 44), material = M.Metal, cancollide = false, canquery = false,
		})
		Forge.part({
			parent = parent, name = "SignalEye",
			size = Vector3.new(0.5, 0.5, 0.3),
			cf = CFrame.new(x, GROUND_Y + 10.4, 14),
			color = Palette.EmergencyRed, material = M.Neon,
			cancollide = false, canquery = false, castshadow = false,
		})
	end
	-- warehouse silhouettes
	if rng:NextNumber() < 0.4 then
		local side = rng:NextNumber() < 0.5 and -1 or 1
		Forge.part({
			parent = parent, name = "Warehouse",
			size = Vector3.new(40, 16, 18),
			cf = CFrame.new(CHUNK / 2, GROUND_Y + 8, side * rng:NextNumber(70, 130)),
			color = Color3.fromRGB(18, 18, 22), material = M.Concrete, cancollide = false, canquery = false,
		})
	end
end

function Builders.gorge(parent, rng)
	-- no ground: a trestle over black water
	trackBed(parent)
	Forge.part({
		parent = parent, name = "DeckBeam",
		size = Vector3.new(CHUNK, 1.4, 9),
		cf = CFrame.new(CHUNK / 2, GROUND_Y - 1, 0),
		color = Color3.fromRGB(34, 30, 28), material = M.Wood, cancollide = false, canquery = false,
	})
	for px = 12, CHUNK - 12, 36 do
		for _, z in ipairs({ -3.4, 3.4 }) do
			Forge.part({
				parent = parent, name = "Pier",
				size = Vector3.new(2, 92, 2),
				cf = CFrame.new(px, GROUND_Y - 47, z),
				color = Color3.fromRGB(30, 26, 24), material = M.Wood, cancollide = false, canquery = false,
			})
		end
		Forge.part({
			parent = parent, name = "Brace",
			size = Vector3.new(1, 26, 1),
			cf = CFrame.new(px, GROUND_Y - 14, 0) * CFrame.Angles(math.rad(38), 0, 0),
			color = Color3.fromRGB(30, 26, 24), material = M.Wood, cancollide = false, canquery = false,
		})
	end
	Forge.part({
		parent = parent, name = "River",
		size = Vector3.new(CHUNK, 0.3, 400),
		cf = CFrame.new(CHUNK / 2, GROUND_Y - 92, 0),
		color = Color3.fromRGB(10, 14, 20), material = M.Glass,
		transparency = 0.05, reflectance = 0.5, cancollide = false, canquery = false,
	})
	-- side guard beams
	for _, z in ipairs({ -5.2, 5.2 }) do
		Forge.part({
			parent = parent, name = "Guard",
			size = Vector3.new(CHUNK, 1, 0.8),
			cf = CFrame.new(CHUNK / 2, GROUND_Y + 1, z),
			color = Color3.fromRGB(34, 30, 28), material = M.Wood, cancollide = false, canquery = false,
		})
	end
	if rng:NextNumber() < 0.3 then
		-- mist below
		local anchor = Forge.part({
			parent = parent, name = "MistAnchor",
			size = Vector3.new(1, 1, 1),
			cf = CFrame.new(CHUNK / 2, GROUND_Y - 60, 0),
			transparency = 1, cancollide = false, canquery = false,
		})
		Forge.particles(anchor, {
			color = ColorSequence.new(Color3.fromRGB(40, 48, 66)),
			size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 14), NumberSequenceKeypoint.new(1, 26) }),
			transparency = NumberSequence.new(0.86, 1),
			lifetime = NumberRange.new(4, 7),
			rate = 2,
			speed = NumberRange.new(1, 3),
			spread = Vector2.new(60, 10),
		})
	end
end

function Builders.tunnel(parent, rng, s0)
	-- rock closing in around the line
	trackBed(parent)
	for _, side in ipairs({ -1, 1 }) do
		Forge.part({
			parent = parent, name = "TunnelWall",
			size = Vector3.new(CHUNK, 26, 6),
			cf = CFrame.new(CHUNK / 2, GROUND_Y + 13, side * 12.5),
			color = Palette.TunnelRock, material = M.Basalt, cancollide = false, canquery = false,
		})
	end
	Forge.part({
		parent = parent, name = "TunnelCeil",
		size = Vector3.new(CHUNK, 4, 31),
		cf = CFrame.new(CHUNK / 2, GROUND_Y + 27, 0),
		color = Palette.TunnelRock, material = M.Basalt, cancollide = false, canquery = false,
	})
	for px = 16, CHUNK - 16, 32 do
		Forge.ring({
			parent = parent, name = "Rib",
			width = 21, height = 24, thick = 1.4, depth = 1.2,
			cf = CFrame.new(px, GROUND_Y + 13, 0) * CFrame.Angles(0, math.rad(90), 0),
			color = Color3.fromRGB(36, 32, 30), material = M.Wood,
		})
	end
	-- portal faces at the ends of the feature
	local feature = RunPlan.featureAt(seed, s0 + CHUNK / 2)
	if feature then
		for _, edge in ipairs({ feature.startD, feature.endD }) do
			if edge >= s0 and edge < s0 + CHUNK then
				local lx = edge - s0
				Forge.part({
					parent = parent, name = "PortalTop",
					size = Vector3.new(3, 30, 60),
					cf = CFrame.new(lx, GROUND_Y + 38, 0),
					color = Color3.fromRGB(24, 26, 28), material = M.Rock, cancollide = false, canquery = false,
				})
				for _, side in ipairs({ -1, 1 }) do
					Forge.part({
						parent = parent, name = "PortalSide",
						size = Vector3.new(3, 40, 24),
						cf = CFrame.new(lx, GROUND_Y + 18, side * 24),
						color = Color3.fromRGB(24, 26, 28), material = M.Rock, cancollide = false, canquery = false,
					})
					Forge.part({
						parent = parent, name = "PortalTrim",
						size = Vector3.new(1.6, 22, 1.6),
						cf = CFrame.new(lx, GROUND_Y + 11, side * 11.4),
						color = Color3.fromRGB(52, 48, 44), material = M.Cobble, cancollide = false, canquery = false,
					})
				end
			end
		end
	end
	local _ = rng
end

----------------------------------------------------------------
-- Chunk management
----------------------------------------------------------------
local function chunkKind(i)
	local sMid = i * CHUNK + CHUNK / 2
	local feature = RunPlan.featureAt(seed, sMid)
	if feature then
		return feature.kind
	end
	local biome = RunPlan.biomeAt(seed, sMid)
	return biome
end

local function buildChunk(i)
	local model = Instance.new("Model")
	model.Name = "Chunk_" .. i
	-- pin the pivot to build-space origin BEFORE parts arrive: a fresh Model's
	-- pivot is volatile (bbox center), and PivotTo would center the chunk on
	-- the anchor instead of origin-mapping it — sinking and tearing the world
	model.WorldPivot = CFrame.new()
	local kind = chunkKind(i)
	local rng = Random.new(seed * 17 + i * 131)
	local builder = Builders[kind] or Builders.pine
	builder(model, rng, i * CHUNK)
	model:PivotTo(CFrame.new(i * CHUNK - ClientState.distance, 0, 0))
	model.Parent = chunkFolder
	chunks[i] = { model = model, origin = i * CHUNK }
	return chunks[i]
end

local function buildFarChunk(i)
	local model = Instance.new("Model")
	model.Name = "Far_" .. i
	model.WorldPivot = CFrame.new()
	local rng = Random.new(seed * 29 + i * 977)
	for _, side in ipairs({ -1, 1 }) do
		local count = rng:NextInteger(2, 3)
		for k = 1, count do
			local w = rng:NextNumber(120, 260)
			local h = rng:NextNumber(60, 150)
			Forge.wedge({
				parent = model, name = "Ridge",
				size = Vector3.new(w, h, rng:NextNumber(40, 80)),
				cf = CFrame.new(rng:NextNumber(0, FAR_PITCH), GROUND_Y + h / 2 - 4, side * (Config.Scenery.FarLayerZ + rng:NextNumber(-40, 90)))
					* CFrame.Angles(0, rng:NextNumber() < 0.5 and math.rad(180) or 0, 0),
				color = Palette.MountainFar, material = M.Slate, cancollide = false, canquery = false, castshadow = false,
			})
			local _ = k
		end
	end
	model.Parent = farFolder
	farChunks[i] = { model = model }
	return farChunks[i]
end

local function updateChunks()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local camX = cam.CFrame.Position.X
	local d = ClientState.distance
	local sCenter = camX + d

	local fromI = math.floor((sCenter - BEHIND * CHUNK) / CHUNK)
	local toI = math.floor((sCenter + AHEAD * CHUNK) / CHUNK)
	for i = fromI, toI do
		if i >= 0 and not chunks[i] then
			buildChunk(i)
		end
	end
	for i, chunk in pairs(chunks) do
		if i < fromI or i > toI then
			chunk.model:Destroy()
			chunks[i] = nil
		else
			chunk.model:PivotTo(CFrame.new(i * CHUNK - d, 0, 0))
		end
	end

	-- far ridge line at parallax speed
	local dFar = d * Config.Scenery.FarParallax
	local sFarCenter = camX + dFar
	local fFrom = math.floor((sFarCenter - 1400) / FAR_PITCH)
	local fTo = math.floor((sFarCenter + 1700) / FAR_PITCH)
	for i = fFrom, fTo do
		if not farChunks[i] then
			buildFarChunk(i)
		end
	end
	for i, chunk in pairs(farChunks) do
		if i < fFrom or i > fTo then
			chunk.model:Destroy()
			farChunks[i] = nil
		else
			chunk.model:PivotTo(CFrame.new(i * FAR_PITCH - dFar, 0, 0))
		end
	end

	-- the moon stands still no matter how far you run
	if moon then
		moon.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(240, 210, -520))
	end

	-- set pieces pinned to the track (the terminus at dawn)
	for _, special in ipairs(specials) do
		special.model:PivotTo(CFrame.new(special.s - d, 0, 0))
		if special.lanternEmitter and not special.lanternEmitter.Enabled and ClientState.speed < 3 then
			special.lanternEmitter.Enabled = true
		end
	end
end

----------------------------------------------------------------
-- The beam sweep (gorge low ironwork)
----------------------------------------------------------------
local function beamSweep(eta)
	task.delay(math.max(eta - 0.05, 0), function()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local camPos = cam.CFrame.Position
		local arch = Instance.new("Model")
		arch.Name = "BeamSweep"
		arch.WorldPivot = CFrame.new()
		for _, z in ipairs({ -7, 7 }) do
			Forge.part({
				parent = arch, name = "BeamPost",
				size = Vector3.new(2.4, 34, 2.4),
				cf = CFrame.new(0, GROUND_Y + 12, z),
				color = Color3.fromRGB(28, 24, 22), material = M.Wood, cancollide = false, canquery = false,
			})
		end
		Forge.part({
			parent = arch, name = "BeamTop",
			size = Vector3.new(2.6, 2.6, 17),
			cf = CFrame.new(0, 22.6, 0), -- just above a standing head on the roof
			color = Color3.fromRGB(30, 26, 22), material = M.Wood, cancollide = false, canquery = false,
		})
		arch.Parent = fxFolder
		local startX = camPos.X + 340
		local endX = camPos.X - 620
		arch:PivotTo(CFrame.new(startX, 0, 0))
		SoundBank.play("BeamWhoosh", Vector3.new(camPos.X + 60, 20, 0), { max = 300 })
		local start = os.clock()
		local DURATION = 1.15
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local t = (os.clock() - start) / DURATION
			if t >= 1 or not arch.Parent then
				conn:Disconnect()
				arch:Destroy()
				return
			end
			arch:PivotTo(CFrame.new(startX + (endX - startX) * t, 0, 0))
		end)
	end)
end

----------------------------------------------------------------
-- One-off set pieces pinned to track coordinates (victory terminus)
----------------------------------------------------------------
local function clearSpecials()
	for _, special in ipairs(specials) do
		special.model:Destroy()
	end
	table.clear(specials)
end

local function buildTerminus()
	local model = Instance.new("Model")
	model.Name = "TerminusArrival"
	model.WorldPivot = CFrame.new()
	-- anchored ahead of the camera so it slides up beside the cars as they slow
	local cam = workspace.CurrentCamera
	local camX = cam and cam.CFrame.Position.X or (Config.Train.Cars * Config.Train.CarPitch)
	local s = ClientState.distance + camX + 150

	local function part(spec)
		spec.parent = model
		spec.cancollide = false
		spec.canquery = false
		return Forge.part(spec)
	end
	-- warm ground and platform running alongside
	part({
		size = Vector3.new(560, 1, 220),
		cf = CFrame.new(280, GROUND_Y - 0.4, 40),
		color = Color3.fromRGB(46, 44, 40), material = M.Ground,
	})
	part({
		size = Vector3.new(240, 1.2, 14),
		cf = CFrame.new(160, Config.Train.FloorY - 0.6, Config.Train.CarWidth / 2 + 7.5),
		color = Palette.Gravel, material = M.Concrete,
	})
	local board = part({
		size = Vector3.new(22, 4, 0.8),
		cf = CFrame.new(160, Config.Train.FloorY + 7, Config.Train.CarWidth / 2 + 13),
		color = Color3.fromRGB(24, 26, 28), material = M.Wood,
	})
	Forge.surfaceText(board, Enum.NormalId.Front, "T E R M I N U S", {
		color = Palette.CarLetters, font = Palette.FontHeader, pps = 36,
	})
	for px = 70, 250, 30 do
		part({
			size = Vector3.new(0.5, 6.5, 0.5),
			cf = CFrame.new(px, Config.Train.FloorY + 3.25, Config.Train.CarWidth / 2 + 6),
			color = Color3.fromRGB(30, 32, 34), material = M.Metal,
		})
		local head = part({
			size = Vector3.new(1, 1.2, 1),
			cf = CFrame.new(px, Config.Train.FloorY + 7, Config.Train.CarWidth / 2 + 6),
			color = Palette.LampGlass, material = M.Neon,
		})
		local light = Instance.new("PointLight")
		light.Color = Palette.LampGlow
		light.Range = 18
		light.Brightness = 1
		light.Parent = head
	end
	-- the ones who waited, lanterns raised
	for k = 1, 3 do
		local gx = 120 + k * 26
		local gz = Config.Train.CarWidth / 2 + 9
		part({
			size = Vector3.new(1.4, 4.6, 0.9),
			cf = CFrame.new(gx, Config.Train.FloorY + 2.3, gz),
			color = Color3.fromRGB(18, 17, 20), material = M.Fabric,
		})
		part({
			size = Vector3.new(0.8, 0.9, 0.8),
			cf = CFrame.new(gx, Config.Train.FloorY + 5.1, gz),
			color = Color3.fromRGB(18, 17, 20), material = M.Fabric,
		})
		local lantern = part({
			size = Vector3.new(0.5, 0.7, 0.5),
			cf = CFrame.new(gx + (k == 2 and 1.1 or 0.8), Config.Train.FloorY + (k == 2 and 5.6 or 3.4), gz - 0.8),
			color = Palette.LampGlass, material = M.Neon,
		})
		local glow = Instance.new("PointLight")
		glow.Color = Palette.LampGlow
		glow.Range = 12
		glow.Brightness = 0.9
		glow.Parent = lantern
	end
	-- sky lanterns released as the cars come to rest
	local release = part({
		size = Vector3.new(160, 0.5, 8),
		cf = CFrame.new(160, Config.Train.FloorY + 4, Config.Train.CarWidth / 2 + 9),
		color = Color3.new(0, 0, 0), material = M.Smooth, transparency = 1,
	})
	local att = Instance.new("Attachment")
	att.Parent = release
	local emitterInst = Instance.new("ParticleEmitter")
	emitterInst.Color = ColorSequence.new(Palette.LampGlow, Color3.fromRGB(255, 140, 90))
	emitterInst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0.4) })
	emitterInst.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.85, 0.35), NumberSequenceKeypoint.new(1, 1) })
	emitterInst.Lifetime = NumberRange.new(6, 9)
	emitterInst.Rate = 2.5
	emitterInst.Speed = NumberRange.new(2, 4)
	emitterInst.SpreadAngle = Vector2.new(14, 14)
	emitterInst.Acceleration = Vector3.new(0.6, 2.2, 0)
	emitterInst.LightEmission = 1
	emitterInst.LightInfluence = 0
	emitterInst.Enabled = false
	emitterInst.Parent = att

	model.Parent = fxFolder
	table.insert(specials, { model = model, s = s, lanternEmitter = emitterInst })
end

----------------------------------------------------------------
-- The Parallel: freezes when watched, closes when it isn't
----------------------------------------------------------------
local parallel = nil -- {model, car, side, endsAt, parts, closeness}

local function clearParallel()
	if parallel then
		if parallel.model then
			parallel.model:Destroy()
		end
		parallel = nil
	end
end

local function spawnParallel(data)
	clearParallel()
	local model = Instance.new("Model")
	model.Name = "Parallel"
	local rng = Random.new(data.seed or 1)

	local torso = Forge.part({
		parent = model, name = "PTorso",
		size = Vector3.new(1.4, 3.4, 0.9),
		color = Palette.ParallelSkin, material = M.Smooth,
		cancollide = false, canquery = false, castshadow = false,
	})
	local head = Forge.part({
		parent = model, name = "PHead",
		size = Vector3.new(0.85, 1.1, 0.85),
		color = Palette.ParallelSkin, material = Enum.Material.SmoothPlastic,
		cancollide = false, canquery = false, castshadow = false,
	})
	local legs = {}
	for k = 1, 2 do
		legs[k] = Forge.part({
			parent = model, name = "PLeg",
			size = Vector3.new(0.5, 3.2, 0.5),
			color = Palette.ParallelSkin, material = Enum.Material.SmoothPlastic,
			cancollide = false, canquery = false, castshadow = false,
		})
	end
	model.Parent = fxFolder

	parallel = {
		model = model,
		car = data.car,
		side = data.side,
		endsAt = os.clock() + (data.duration or 25),
		torso = torso,
		head = head,
		legs = legs,
		phase = rng:NextNumber(0, 6),
		gazeAccum = 0,
		runPhase = 0,
		closeness = 0,       -- 0 = out in the fields, ~0.9 = at the glass
		unwatchedFor = 0,
		lastWhisper = 0,
	}
end

local function parallelStep(dt)
	local p = parallel
	if not p then
		return
	end
	if os.clock() > p.endsAt or not p.model.Parent then
		clearParallel()
		return
	end

	local cam = workspace.CurrentCamera
	local inItsCar = ClientState.carIndex == p.car and not ClientState.isGhost()
	local carX0 = (p.car - 1) * Config.Train.CarPitch

	-- position: distance from the train shrinks as it goes unwatched
	local pos
	if p.side == 0 then
		-- flatcar deck: it stands at the far end and simply ends up nearer
		local myRoot = ClientState.localRoot()
		local targetX = (inItsCar and myRoot) and myRoot.Position.X or (carX0 + 6)
		local farX = carX0 + 40
		pos = Vector3.new(
			farX + (targetX - farX) * p.closeness * 0.8,
			Config.Train.FloorY + 3.4,
			4.2 - p.closeness * 1.6
		)
	else
		local reach = 17 - p.closeness * 12 -- down to ~5: breathing on the glass
		local drift = math.sin(os.clock() * 0.6 + p.phase) * 9 * (1 - p.closeness)
		pos = Vector3.new(
			carX0 + 22 + drift,
			Config.Train.FloorY + 3.2 + p.closeness * 0.9,
			p.side * (reach + math.sin(os.clock() * 0.9 + p.phase) * 2 * (1 - p.closeness))
		)
	end

	-- am I looking at it?
	local watched = false
	local dot = -1
	if cam then
		local toIt = pos - cam.CFrame.Position
		if toIt.Magnitude > 1 then
			dot = cam.CFrame.LookVector:Dot(toIt.Unit)
			watched = inItsCar and dot > 0.78
		end
	end

	if watched then
		p.unwatchedFor = 0
	else
		p.unwatchedFor += dt
		if p.unwatchedFor >= 1.6 and inItsCar then
			p.unwatchedFor = 0
			p.closeness = math.min(p.closeness + 0.14, 0.9)
		end
	end

	-- pose: it only moves while nobody holds it in their eye
	if not watched then
		p.runPhase += dt * 9
	end
	local runPhase = p.runPhase
	local look = CFrame.lookAt(pos, Vector3.new(pos.X, pos.Y, 0))
	p.torso.CFrame = look * CFrame.new(0, math.abs(math.sin(runPhase)) * 0.3, 0)
	if watched and cam then
		-- frozen mid-stride, head wrong: it has already found your face
		local headPos = (p.torso.CFrame * CFrame.new(0, 2.2, 0)).Position
		p.head.CFrame = CFrame.lookAt(headPos, cam.CFrame.Position) * CFrame.Angles(0, 0, math.rad(9))
	else
		p.head.CFrame = p.torso.CFrame * CFrame.new(0, 2.2, 0)
	end
	p.legs[1].CFrame = p.torso.CFrame * CFrame.new(-0.35, -3.2, 0) * CFrame.Angles(math.sin(runPhase) * 0.8, 0, 0)
	p.legs[2].CFrame = p.torso.CFrame * CFrame.new(0.35, -3.2, 0) * CFrame.Angles(-math.sin(runPhase) * 0.8, 0, 0)

	-- the nearer it stands, the more it has to say
	if inItsCar and p.closeness > 0.3 and os.clock() - p.lastWhisper > 4.5 then
		p.lastWhisper = os.clock()
		SoundBank.play("ParallelWhisper", pos, { volumeScale = 0.3 + p.closeness * 0.5, max = 60 })
	end

	-- gaze arbitration stays server-side and unchanged
	if watched then
		p.gazeAccum += dt
		if p.gazeAccum >= 0.25 then
			Net.fire(Net.T.GazeReport, { car = p.car, side = p.side, seconds = math.min(p.gazeAccum, 0.4) })
			p.gazeAccum = 0
		end
	end
end

----------------------------------------------------------------
-- Start
----------------------------------------------------------------
function SceneryController.start()
	root = Instance.new("Folder")
	root.Name = "LocalScenery"
	root.Parent = workspace
	chunkFolder = Forge.folder("Chunks", root)
	farFolder = Forge.folder("Far", root)
	fxFolder = Forge.folder("FX", root)

	moon = Forge.ball({
		parent = root, name = "Moon",
		size = Vector3.new(34, 34, 34),
		cf = CFrame.new(0, 300, -600),
		color = Palette.Moon, material = M.Neon,
		cancollide = false, canquery = false, castshadow = false,
	})
	local halo = Instance.new("PointLight")
	halo.Color = Palette.Moonlight
	halo.Brightness = 0.3
	halo.Range = 60
	halo.Parent = moon

	seed = workspace:GetAttribute("RunSeed") or 1
	workspace:GetAttributeChangedSignal("RunSeed"):Connect(function()
		seed = workspace:GetAttribute("RunSeed") or 1
		for i, chunk in pairs(chunks) do
			chunk.model:Destroy()
			chunks[i] = nil
		end
		for i, chunk in pairs(farChunks) do
			chunk.model:Destroy()
			farChunks[i] = nil
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		updateChunks()
		parallelStep(dt)
	end)

	ClientState.signals.runStateChanged:connect(function(state)
		if state == "Victory" then
			buildTerminus()
		elseif state == "Lobby" then
			clearSpecials()
			clearParallel()
		end
	end)

	Net.on(Net.T.BeamWarn, function(data)
		beamSweep(data.eta or 3)
	end)
	Net.on(Net.T.ParallelSpawn, spawnParallel)
	Net.on(Net.T.ParallelBreak, function(data)
		-- glass burst at my car's nearest window line
		if parallel and data.car == parallel.car then
			local p = parallel
			local burst = Instance.new("Part")
			burst.Anchored = true
			burst.CanCollide = false
			burst.Transparency = 1
			burst.Size = Vector3.new(1, 1, 1)
			burst.CFrame = CFrame.new((p.car - 1) * Config.Train.CarPitch + 22, Config.Train.FloorY + 5, (p.side ~= 0 and p.side or 1) * 5.4)
			burst.Parent = fxFolder
			local att = Instance.new("Attachment")
			att.Parent = burst
			Forge.particles(att, {
				color = ColorSequence.new(Color3.fromRGB(200, 220, 255)),
				size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.05) }),
				lifetime = NumberRange.new(0.4, 0.9),
				rate = 0,
				speed = NumberRange.new(6, 16),
				spread = Vector2.new(70, 70),
				lightEmission = 0.6,
			})
			local emitter = att:FindFirstChildOfClass("ParticleEmitter")
			if emitter then
				emitter:Emit(50)
			end
			game:GetService("Debris"):AddItem(burst, 2)
		end
		clearParallel()
	end)
end

return SceneryController
