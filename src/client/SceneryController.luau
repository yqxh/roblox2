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
local LightingDirector = require(script.Parent:WaitForChild("LightingDirector"))

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
local moonHaloInner = nil
local moonHaloOuter = nil
local lastBiomeSent = nil

local chunks = {}    -- index -> {model}
local farChunks = {} -- index -> {model}
local specials = {}  -- one-off set pieces pinned to track coordinates
local seed = 0

----------------------------------------------------------------
-- Piece builders (local coordinates: x in [0, CHUNK), z world)
-- Every scenery part: cancollide/canquery false, castshadow false —
-- the sun is down; shadow flags on a thousand night parts are pure cost.
----------------------------------------------------------------
local function scen(parent, spec)
	spec.parent = parent
	spec.cancollide = false
	spec.canquery = false
	spec.castshadow = false
	if spec.shape == "wedge" then
		spec.shape = nil
		return Forge.wedge(spec)
	elseif spec.shape == "cyl" then
		spec.shape = nil
		return Forge.cyl(spec)
	elseif spec.shape == "ball" then
		spec.shape = nil
		return Forge.ball(spec)
	end
	return Forge.part(spec)
end

local function jitterColor(rng, color, amount)
	local a = amount or 6
	local r = math.clamp(color.R * 255 + rng:NextNumber(-a, a), 0, 255)
	local g = math.clamp(color.G * 255 + rng:NextNumber(-a, a), 0, 255)
	local b = math.clamp(color.B * 255 + rng:NextNumber(-a, a), 0, 255)
	return Color3.fromRGB(r, g, b)
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
			color = Palette.RailSteel, material = M.Metal, reflectance = 0.35,
			cancollide = false, canquery = false, castshadow = false,
		})
	end
end

-- Layered roadbed: three receding ground terraces, value patches, ballast
-- shoulders, and a drainage ditch — kills the flat-slab look everywhere.
local function roadbed(parent, rng, verge, mid, far, material, opts)
	opts = opts or {}
	for _, side in ipairs({ -1, 1 }) do
		scen(parent, { name = "Verge", size = Vector3.new(96, 1, 25.1), cf = CFrame.new(48, 5.10, side * 21.45), color = verge, material = material })
		scen(parent, { name = "Mid", size = Vector3.new(96, 1, 70), cf = CFrame.new(48, 4.85, side * 69), color = mid, material = material })
		scen(parent, { name = "Far", size = Vector3.new(96, 1, 110), cf = CFrame.new(48, 4.55, side * 159), color = far, material = material })
	end
	for _ = 1, 3 do
		local px = rng:NextNumber(8, 88)
		local pside = rng:NextNumber() < 0.5 and -1 or 1
		local pz = pside * rng:NextNumber(12, 90)
		local strip = math.abs(pz) < 34 and verge or (math.abs(pz) < 104 and mid or far)
		local top = math.abs(pz) < 34 and 5.60 or (math.abs(pz) < 104 and 5.35 or 5.05)
		scen(parent, {
			name = "Patch",
			size = Vector3.new(rng:NextNumber(14, 30), 0.18, rng:NextNumber(10, 22)),
			cf = CFrame.new(px, top + 0.05, pz),
			color = jitterColor(rng, strip, 6), material = material,
		})
	end
	for _, side in ipairs({ -1, 1 }) do
		scen(parent, {
			shape = "wedge", name = "Shoulder",
			size = Vector3.new(96, 0.8, 2.2),
			cf = CFrame.new(48, 5.90, side * 5.1) * CFrame.Angles(0, side * math.rad(90), 0),
			color = Palette.Gravel, material = M.Slate,
		})
		if opts.wetDitch then
			scen(parent, {
				name = "Ditch", size = Vector3.new(96, 0.3, 2.7),
				cf = CFrame.new(48, 5.13, side * 7.55),
				color = Palette.MarshWater, material = M.Glass,
				transparency = 0.25, reflectance = 0.35,
			})
		else
			scen(parent, {
				name = "Ditch", size = Vector3.new(96, 0.3, 2.7),
				cf = CFrame.new(48, 5.13, side * 7.55),
				color = Palette.DitchDark, material = M.Slate,
			})
		end
	end
	trackBed(parent)
end

local function telegraphPoleV2(parent, rng, x, side, leanRange)
	local lr = leanRange or 0.06
	local lean = CFrame.Angles(rng:NextNumber(-0.04, 0.04), 0, rng:NextNumber(-lr, lr))
	local base = CFrame.new(x, GROUND_Y, side * 22) * lean
	scen(parent, {
		name = "Pole", size = Vector3.new(0.5, 13, 0.5),
		cf = base * CFrame.new(0, 6.5, 0),
		color = Palette.SnagWood, material = M.Wood,
	})
	scen(parent, {
		name = "Crossarm", size = Vector3.new(0.3, 0.3, 3.4),
		cf = base * CFrame.new(0, 11.6, 0),
		color = Palette.SnagWood, material = M.Wood,
	})
	scen(parent, {
		name = "Wire", size = Vector3.new(CHUNK, 0.08, 0.08),
		cf = CFrame.new(x + CHUNK / 2, GROUND_Y + 11.1, side * 22) * CFrame.Angles(0, 0, math.rad(1.2)),
		color = Color3.fromRGB(20, 20, 22), material = M.Metal,
	})
end

local function pineTreeV2(parent, rng, x, z)
	local h = rng:NextNumber(10, 24)
	local lean = CFrame.Angles(rng:NextNumber(-0.03, 0.03), 0, rng:NextNumber(-0.03, 0.03))
	local base = CFrame.new(x, GROUND_Y, z) * lean
	scen(parent, {
		name = "Trunk", size = Vector3.new(0.9, h * 0.35, 0.9),
		cf = base * CFrame.new(0, h * 0.175, 0),
		color = Palette.PineTrunk, material = M.Wood,
	})
	local treeColor = Palette.PineDark:Lerp(Palette.PineMid, rng:NextNumber())
	for t = 0, 3 do
		local w = math.max((4.2 - t) * h / 16, 0.9)
		scen(parent, {
			name = "Canopy", size = Vector3.new(w * 2, h * 0.22, w * 2),
			cf = CFrame.new(x, GROUND_Y + h * (0.34 + 0.19 * t), z) * CFrame.Angles(0, rng:NextNumber(0, 3.14), 0),
			color = jitterColor(rng, treeColor, 4), material = M.Grass,
		})
	end
	scen(parent, {
		name = "Tip", size = Vector3.new(0.9, h * 0.14, 0.9),
		cf = CFrame.new(x, GROUND_Y + h * 0.99, z),
		color = jitterColor(rng, Palette.PineDark, 3), material = M.Grass,
	})
end

-- Serrated silhouette wall: reads as a full treeline for 7 parts.
local function treelineWall(parent, rng, side, zPush)
	local boxes = {}
	local specs = {
		{ 52, rng:NextNumber(14, 18), rng:NextNumber(20, 28), rng:NextNumber(50, 56) },
		{ 56, rng:NextNumber(10, 14), rng:NextNumber(68, 76), rng:NextNumber(52, 58) },
	}
	for _, s in ipairs(specs) do
		local w, h, xc, zc = s[1], s[2], s[3], s[4]
		zc = zPush and (zPush + (zc - 53)) or zc
		local box = scen(parent, {
			name = "Treeline", size = Vector3.new(w, h, 7),
			cf = CFrame.new(xc, 5.0 + h / 2, side * zc),
			color = Palette.TreelineDark, material = M.Grass,
		})
		table.insert(boxes, { part = box, xc = xc, w = w, zc = zc, topY = 5.0 + h })
	end
	for k = 0, 4 do
		local tx = 8 + k * 18 + rng:NextNumber(-3, 3)
		local host = (math.abs(tx - boxes[1].xc) < boxes[1].w / 2 + 4) and boxes[1] or boxes[2]
		local th = rng:NextNumber(7, 12)
		scen(parent, {
			shape = "wedge", name = "Serration",
			size = Vector3.new(10, th, 7),
			cf = CFrame.new(tx, host.topY + th / 2, side * host.zc)
				* CFrame.Angles(0, rng:NextNumber() < 0.5 and math.rad(90) or math.rad(270), 0),
			color = Palette.TreelineDark, material = M.Grass,
		})
	end
end

local function rock(parent, rng, x, z, recolor)
	local sy = rng:NextNumber(1.2, 2.2)
	scen(parent, {
		name = "Rock",
		size = Vector3.new(rng:NextNumber(2, 4), sy, rng:NextNumber(2, 4)),
		cf = CFrame.new(x, GROUND_Y + sy * 0.25, z)
			* CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, 3.14), rng:NextNumber(-0.35, 0.35)),
		color = recolor or Palette.RockGray, material = M.Slate,
	})
end

local function stump(parent, rng, x, z)
	scen(parent, {
		shape = "cyl", name = "Stump",
		size = Vector3.new(rng:NextNumber(0.9, 1.4), 1.7, 1.7),
		cf = CFrame.new(x, GROUND_Y + 0.5, z) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(rng:NextNumber(-0.06, 0.06), 0, 0),
		color = Palette.PineTrunk, material = M.Wood,
	})
end

local function bush(parent, rng, x, z)
	local d = rng:NextNumber(2.4, 4.2)
	scen(parent, {
		shape = "ball", name = "Bush",
		size = Vector3.new(d, d * 0.62, d),
		cf = CFrame.new(x, GROUND_Y + d * 0.2, z),
		color = Palette.TreelineDark:Lerp(Palette.PineDark, rng:NextNumber()), material = M.Grass,
	})
end

local function mistCard(parent, rng, x, z, scale)
	scen(parent, {
		name = "Mist",
		size = Vector3.new(rng:NextNumber(30, 46) * (scale or 1), 1.4, rng:NextNumber(14, 22) * (scale or 1)),
		cf = CFrame.new(x, GROUND_Y + 0.9 + rng:NextNumber(0, 0.8), z) * CFrame.Angles(0, rng:NextNumber(0, 3.14), 0),
		color = Palette.MistBlue, material = M.Smooth, transparency = 0.86,
	})
end

local function fogBank(parent, rng, x, z)
	scen(parent, {
		name = "FogBank",
		size = Vector3.new(rng:NextNumber(34, 48), rng:NextNumber(6, 9), 0.6),
		cf = CFrame.new(x, GROUND_Y + 4, z) * CFrame.Angles(0, rng:NextNumber(0, 3.14), 0),
		color = Palette.MistBlue, material = M.Smooth, transparency = 0.88,
	})
end

----------------------------------------------------------------
-- Biome chunks
----------------------------------------------------------------
local Builders = {}

local GROUND_TRIPLETS = {
	pine = { Color3.fromRGB(30, 37, 34), Color3.fromRGB(23, 29, 28), Color3.fromRGB(17, 22, 23), M.Grass },
	marsh = { Color3.fromRGB(26, 32, 30), Color3.fromRGB(20, 26, 26), Color3.fromRGB(15, 20, 21), M.Mud },
	fields = { Color3.fromRGB(36, 38, 29), Color3.fromRGB(28, 30, 24), Color3.fromRGB(20, 22, 19), M.Grass },
	yard = { Color3.fromRGB(38, 38, 40), Color3.fromRGB(30, 30, 33), Color3.fromRGB(22, 22, 25), M.Ground },
}

function Builders.pine(parent, rng)
	local t = GROUND_TRIPLETS.pine
	roadbed(parent, rng, t[1], t[2], t[3], t[4])
	telegraphPoleV2(parent, rng, 8, -1)
	telegraphPoleV2(parent, rng, 56, 1)
	treelineWall(parent, rng, -1)
	treelineWall(parent, rng, 1)
	-- individual pines only in the parseable band; the walls do the rest
	local placedZ = {}
	for _ = 1, 4 do
		local x = rng:NextNumber(4, 92)
		local side = rng:NextNumber() < 0.5 and -1 or 1
		local z = side * rng:NextNumber(13, 40)
		local retryZ = side * rng:NextNumber(13, 40) -- always burn the retry draw
		for _, prev in ipairs(placedZ) do
			if math.abs(prev.x - x) < 6 and math.abs(prev.z - z) < 5 then
				z = retryZ
				break
			end
		end
		table.insert(placedZ, { x = x, z = z })
		pineTreeV2(parent, rng, x, z)
	end
	if rng:NextNumber() < 0.5 then
		pineTreeV2(parent, rng, rng:NextNumber(4, 92), (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(13, 40))
	end
	rock(parent, rng, rng:NextNumber(6, 90), (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(11, 30))
	bush(parent, rng, rng:NextNumber(6, 90), (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(10, 26))
	stump(parent, rng, rng:NextNumber(6, 90), (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(11, 32))
	mistCard(parent, rng, rng:NextNumber(20, 76), -rng:NextNumber(14, 30), 1)
	if rng:NextNumber() < 0.12 then
		scen(parent, {
			name = "Snag", size = Vector3.new(0.9, 14, 0.9),
			cf = CFrame.new(rng:NextNumber(10, 80), GROUND_Y + 6.5, -rng:NextNumber(25, 60))
				* CFrame.Angles(0, 0, rng:NextNumber(-0.2, 0.2)),
			color = Palette.SnagWood, material = M.Wood,
		})
	end
end

local function fireflies(parent, x, z)
	local anchor = Forge.part({
		parent = parent, name = "FireflyAnchor",
		size = Vector3.new(1, 1, 1),
		cf = CFrame.new(x, GROUND_Y + 4, z),
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

function Builders.marsh(parent, rng)
	local t = GROUND_TRIPLETS.marsh
	roadbed(parent, rng, t[1], t[2], t[3], t[4], { wetDitch = true })
	telegraphPoleV2(parent, rng, 8, -1, 0.09)
	telegraphPoleV2(parent, rng, 56, 1, 0.09)

	-- still water sheets; drowned trees stand in them
	local rects = {}
	for _ = 1, 2 do
		local w, d = rng:NextNumber(34, 72), rng:NextNumber(30, 72)
		local x = rng:NextNumber(15, 80)
		local side = rng:NextNumber() < 0.5 and -1 or 1
		local z = side * rng:NextNumber(26, 110)
		scen(parent, {
			name = "Water", size = Vector3.new(w, 0.2, d),
			cf = CFrame.new(x, GROUND_Y - 0.18, z),
			color = Palette.MarshWater, material = M.Glass,
			transparency = 0.10, reflectance = 0.55,
		})
		table.insert(rects, { x = x, z = z, w = w, d = d })
	end

	for _ = 1, 5 do
		local x = rng:NextNumber(4, CHUNK - 4)
		local side = rng:NextNumber() < 0.5 and -1 or 1
		local z = side * rng:NextNumber(20, 110)
		if rng:NextNumber() < 0.6 then
			local r = rects[rng:NextInteger(1, #rects)]
			x = r.x + rng:NextNumber(-r.w / 2 + 3, r.w / 2 - 3)
			z = r.z + rng:NextNumber(-r.d / 2 + 3, r.d / 2 - 3)
		end
		local trunkH = rng:NextNumber(8, 14)
		local lean = CFrame.Angles(rng:NextNumber(-0.12, 0.12), 0, rng:NextNumber(-0.18, 0.18))
		local base = CFrame.new(x, GROUND_Y, z) * lean
		scen(parent, {
			name = "DeadTree", size = Vector3.new(0.7, trunkH, 0.7),
			cf = base * CFrame.new(0, trunkH / 2, 0),
			color = Palette.SnagWood, material = M.Wood,
		})
		for arm = 1, 2 do
			scen(parent, {
				name = "Branch", size = Vector3.new(0.35, rng:NextNumber(2.8, 4), 0.35),
				cf = base * CFrame.new(0, trunkH * (arm == 1 and 0.62 or 0.78), 0)
					* CFrame.Angles(0, rng:NextNumber(0, 3.14), math.rad(rng:NextNumber(50, 75))),
				color = Palette.SnagWood, material = M.Wood,
			})
		end
	end

	for _ = 1, 3 do
		local r = rects[rng:NextInteger(1, #rects)]
		local rx = r.x + rng:NextNumber(-r.w / 2 - 4, r.w / 2 + 4)
		local rz = r.z + (rng:NextNumber() < 0.5 and -1 or 1) * (r.d / 2 + rng:NextNumber(1, 4))
		scen(parent, {
			name = "Reeds", size = Vector3.new(2.6, 2.4, 0.3),
			cf = CFrame.new(rx, GROUND_Y + 1.2, rz) * CFrame.Angles(0, rng:NextNumber(0, 3.14), 0),
			color = Palette.MarshReed, material = M.Grass,
		})
		scen(parent, {
			name = "Reeds", size = Vector3.new(0.3, 2.4, 2.6),
			cf = CFrame.new(rx, GROUND_Y + 1.2, rz) * CFrame.Angles(0, rng:NextNumber(0, 3.14), 0),
			color = Palette.MarshReed, material = M.Grass,
		})
	end

	scen(parent, {
		shape = "cyl", name = "SunkLog",
		size = Vector3.new(rng:NextNumber(5, 8), 1.6, 1.6),
		cf = CFrame.new(rng:NextNumber(10, 86), GROUND_Y + 0.2, (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(12, 40))
			* CFrame.Angles(0, rng:NextNumber(0, 3.14), 0),
		color = Palette.SnagWood, material = M.Wood,
	})

	for k = 1, 2 do
		local r = rects[k]
		mistCard(parent, rng, r.x, r.z, 1.3)
	end
	fogBank(parent, rng, rng:NextNumber(20, 76), (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(30, 60))
	fireflies(parent, rects[1].x, rects[1].z)
	fireflies(parent, rects[2].x, rects[2].z)

	-- marsh horizons stay open on one side
	treelineWall(parent, rng, rng:NextNumber() < 0.5 and -1 or 1, rng:NextNumber(62, 70))
end

function Builders.fields(parent, rng)
	local t = GROUND_TRIPLETS.fields
	roadbed(parent, rng, t[1], t[2], t[3], t[4])
	telegraphPoleV2(parent, rng, 8, -1)
	telegraphPoleV2(parent, rng, 56, 1)

	-- crop windrows: parallel furrows racing past the glass
	local rowSide = rng:NextNumber() < 0.5 and -1 or 1
	for k, zBand in ipairs({ 15.5, 20.5, 25.5, 30.5 }) do
		scen(parent, {
			name = "CropRow", size = Vector3.new(96, 0.45, 1.6),
			cf = CFrame.new(48, 5.62, rowSide * zBand),
			color = k % 2 == 1 and Palette.CropRow or Palette.CropRowAlt, material = M.Grass,
		})
	end

	-- fence runs on the second terrace
	for _, side in ipairs({ -1, 1 }) do
		if rng:NextNumber() < 0.8 then
			local z = side * rng:NextNumber(33, 40)
			for px = 6, 90, 12 do
				scen(parent, {
					name = "FencePost", size = Vector3.new(0.35, 2.4, 0.35),
					cf = CFrame.new(px, GROUND_Y + 0.9, z) * CFrame.Angles(0, 0, rng:NextNumber(-0.08, 0.08)),
					color = Palette.SnagWood, material = M.Wood,
				})
			end
			for _, railY in ipairs({ 6.8, 7.6 }) do
				scen(parent, {
					name = "FenceRail", size = Vector3.new(96, 0.22, 0.22),
					cf = CFrame.new(48, railY, z),
					color = Palette.SnagWood, material = M.Wood,
				})
			end
		end
	end

	-- haystacks
	for _ = 1, 3 do
		local x = rng:NextNumber(8, 88)
		local z = (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(44, 95)
		scen(parent, {
			shape = "cyl", name = "HayBase", size = Vector3.new(2.2, 6.4, 6.4),
			cf = CFrame.new(x, GROUND_Y + 1.1, z) * CFrame.Angles(0, 0, math.rad(90)),
			color = Palette.HayStraw, material = M.Grass,
		})
		scen(parent, {
			shape = "ball", name = "HayTop", size = Vector3.new(5.6, 4.2, 5.6),
			cf = CFrame.new(x, GROUND_Y + 3.4, z),
			color = Palette.HayStraw, material = M.Grass,
		})
	end

	-- lone oak
	do
		local x = rng:NextNumber(8, 88)
		local z = (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(46, 80)
		scen(parent, {
			name = "OakTrunk", size = Vector3.new(1.2, 7, 1.2),
			cf = CFrame.new(x, GROUND_Y + 3.5, z),
			color = Palette.PineTrunk, material = M.Wood,
		})
		local oakColor = Palette.PineDark:Lerp(Palette.PineMid, rng:NextNumber())
		scen(parent, {
			shape = "ball", name = "OakCanopy", size = Vector3.new(7, 5, 7),
			cf = CFrame.new(x + 1.5, GROUND_Y + 8.2, z + 1.5),
			color = oakColor, material = M.Grass,
		})
		scen(parent, {
			shape = "ball", name = "OakCanopy", size = Vector3.new(5, 3.6, 5),
			cf = CFrame.new(x - 1.5, GROUND_Y + 10.4, z - 1.5),
			color = oakColor, material = M.Grass,
		})
	end

	-- one hero silhouette per fields chunk, or nothing
	local roll = rng:NextNumber()
	local heroSide = rng:NextNumber() < 0.5 and -1 or 1
	if roll < 0.30 then
		-- windmill against the fog line
		local x = rng:NextNumber(20, 76)
		local z = heroSide * rng:NextNumber(120, 170)
		scen(parent, { name = "MillTower", size = Vector3.new(3.4, 14, 3.4), cf = CFrame.new(x, GROUND_Y + 7, z), color = Palette.YardSteel, material = M.Metal })
		scen(parent, { name = "MillTower2", size = Vector3.new(2.2, 10, 2.2), cf = CFrame.new(x, GROUND_Y + 19, z), color = Palette.YardSteel, material = M.Metal })
		scen(parent, { shape = "ball", name = "MillHub", size = Vector3.new(1.6, 1.6, 1.6), cf = CFrame.new(x, GROUND_Y + 24.8, z - heroSide * 0.8), color = Palette.YardSteel, material = M.Metal })
		local bladeOffset = rng:NextNumber(0, 1.57)
		for b = 0, 3 do
			scen(parent, {
				name = "MillBlade", size = Vector3.new(0.5, 9, 1.6),
				cf = CFrame.new(x, GROUND_Y + 24.8, z - heroSide * 1.0)
					* CFrame.Angles(0, 0, bladeOffset + b * math.rad(90))
					* CFrame.new(0, 4.5, 0),
				color = Palette.SnagWood, material = M.Wood,
			})
		end
	elseif roll < 0.55 then
		-- barn + silo
		local x = rng:NextNumber(20, 76)
		local z = heroSide * rng:NextNumber(70, 110)
		scen(parent, { name = "Barn", size = Vector3.new(18, 9, 12), cf = CFrame.new(x, GROUND_Y + 4.5, z), color = Color3.fromRGB(30, 18, 16), material = M.Wood })
		for _, half in ipairs({ -1, 1 }) do
			scen(parent, {
				shape = "wedge", name = "BarnRoof", size = Vector3.new(18, 4.5, 6.2),
				cf = CFrame.new(x, GROUND_Y + 11.25, z + half * 3.1)
					* CFrame.Angles(0, half == 1 and math.rad(180) or 0, 0),
				color = Color3.fromRGB(16, 16, 18), material = M.Slate,
			})
		end
		scen(parent, { shape = "cyl", name = "Silo", size = Vector3.new(11, 7, 7), cf = CFrame.new(x + 12, GROUND_Y + 5.5, z) * CFrame.Angles(0, 0, math.rad(90)), color = Color3.fromRGB(44, 46, 48), material = M.Metal })
		scen(parent, { shape = "ball", name = "SiloDome", size = Vector3.new(7, 3.5, 7), cf = CFrame.new(x + 12, GROUND_Y + 11.5, z), color = Color3.fromRGB(44, 46, 48), material = M.Metal })
	elseif roll < 0.75 then
		-- farmhouse, one window lit for someone long gone
		local x = rng:NextNumber(15, 70)
		local z = heroSide * rng:NextNumber(90, 150)
		scen(parent, { name = "House", size = Vector3.new(14, 8, 10), cf = CFrame.new(x, GROUND_Y + 4, z), color = Color3.fromRGB(20, 20, 24), material = M.Wood })
		scen(parent, { shape = "wedge", name = "HouseRoof", size = Vector3.new(14, 4, 10), cf = CFrame.new(x, GROUND_Y + 10, z), color = Color3.fromRGB(16, 16, 18), material = M.Slate })
		scen(parent, {
			name = "WarmWindow", size = Vector3.new(0.2, 1.4, 1.1),
			cf = CFrame.new(x - 7, GROUND_Y + 4.5, z),
			color = Palette.WarmWindow, material = M.Neon,
		})
	end

	if rng:NextNumber() < 0.5 then
		mistCard(parent, rng, rng:NextNumber(20, 76), rowSide * rng:NextNumber(16, 30), 1)
	end
end

function Builders.yard(parent, rng)
	local t = GROUND_TRIPLETS.yard
	roadbed(parent, rng, t[1], t[2], t[3], t[4])

	-- dead cold light masts, one of them still burning
	for mastIndex, spec in ipairs({ { rng:NextNumber(10, 40), -1 }, { rng:NextNumber(56, 86), 1 } }) do
		local mx, mside = spec[1], spec[2]
		local mz = mside * rng:NextNumber(14, 20)
		scen(parent, { name = "MastPole", size = Vector3.new(0.6, 16, 0.6), cf = CFrame.new(mx, GROUND_Y + 8, mz), color = Palette.YardSteel, material = M.Metal })
		scen(parent, { name = "MastArm", size = Vector3.new(0.4, 0.4, 3.2), cf = CFrame.new(mx, GROUND_Y + 15.6, mz - mside * 1.6), color = Palette.YardSteel, material = M.Metal })
		local head = scen(parent, {
			name = "MastHead", size = Vector3.new(1.1, 0.5, 1.1),
			cf = CFrame.new(mx, GROUND_Y + 15.2, mz - mside * 3.0),
			color = Color3.fromRGB(150, 170, 190), material = M.Neon,
		})
		if mastIndex == 1 then
			Forge.light(head, { kind = "spot", color = Color3.fromRGB(150, 170, 190), brightness = 0.8, range = 40, angle = 70, face = Enum.NormalId.Bottom, shadows = false })
		end
	end

	-- dead sidings
	for _, z in ipairs({ -18, -26 }) do
		scen(parent, {
			name = "SidingRail", size = Vector3.new(96, 0.3, 0.3),
			cf = CFrame.new(48, 6.0, z),
			color = Color3.fromRGB(60, 58, 56), material = M.CorrodedMetal,
		})
	end
	if rng:NextNumber() < 0.55 then
		local bx = rng:NextNumber(20, 70)
		local lean = rng:NextNumber(-0.06, 0.02)
		scen(parent, { name = "DeadCar", size = Vector3.new(26, 9, 9), cf = CFrame.new(bx, GROUND_Y + 4.5, -18) * CFrame.Angles(0, 0, lean), color = Color3.fromRGB(26, 22, 22), material = M.CorrodedMetal })
		scen(parent, { shape = "wedge", name = "DeadCarRoof", size = Vector3.new(26, 2, 9), cf = CFrame.new(bx, GROUND_Y + 10, -18) * CFrame.Angles(0, 0, lean), color = Color3.fromRGB(18, 18, 20), material = M.Slate })
		for _, ax in ipairs({ bx - 9, bx + 9 }) do
			scen(parent, { name = "DeadAxle", size = Vector3.new(2.5, 1.6, 8), cf = CFrame.new(ax, GROUND_Y + 0.8, -18), color = Color3.fromRGB(14, 14, 16), material = M.Metal })
		end
	end

	-- container stacks opposite the siding
	local containerColors = { Palette.ContainerRust, Palette.ContainerBlue, Palette.ContainerOlive }
	for _, sx in ipairs({ rng:NextNumber(8, 34), rng:NextNumber(54, 84) }) do
		local sz = rng:NextNumber(24, 60)
		local baseY = GROUND_Y + 4.2
		scen(parent, { name = "Container", size = Vector3.new(24, 8.4, 8), cf = CFrame.new(sx, baseY, sz), color = containerColors[rng:NextInteger(1, 3)], material = M.CorrodedMetal })
		scen(parent, {
			name = "Container", size = Vector3.new(24, 8.4, 8),
			cf = CFrame.new(sx + rng:NextNumber(-2, 2), baseY + 8.4, sz + rng:NextNumber(-0.6, 0.6)) * CFrame.Angles(0, rng:NextNumber(-0.05, 0.05), 0),
			color = containerColors[rng:NextInteger(1, 3)], material = M.CorrodedMetal,
		})
		if rng:NextNumber() < 0.5 then
			scen(parent, { name = "Container", size = Vector3.new(24, 8.4, 8), cf = CFrame.new(sx + rng:NextNumber(-2, 2), baseY + 16.8, sz) * CFrame.Angles(0, rng:NextNumber(-0.05, 0.05), 0), color = containerColors[rng:NextInteger(1, 3)], material = M.CorrodedMetal })
		else
			scen(parent, { name = "Container", size = Vector3.new(24, 8.4, 8), cf = CFrame.new(sx + rng:NextNumber(-4, 4), baseY, sz + 9) * CFrame.Angles(0, rng:NextNumber(-0.05, 0.05), 0), color = containerColors[rng:NextInteger(1, 3)], material = M.CorrodedMetal })
		end
	end

	-- drums, tie stacks, slag
	local drumColors = { Color3.fromRGB(40, 20, 18), Color3.fromRGB(24, 34, 48), Color3.fromRGB(40, 42, 44) }
	local drumX, drumZ = rng:NextNumber(12, 80), rng:NextNumber(26, 50)
	for d = 1, 3 do
		scen(parent, {
			shape = "cyl", name = "Drum", size = Vector3.new(1.8, 1.4, 1.4),
			cf = CFrame.new(drumX + d * 1.5, GROUND_Y + 0.9, drumZ + (d % 2)) * CFrame.Angles(0, 0, math.rad(90)),
			color = drumColors[d], material = M.CorrodedMetal,
		})
	end
	for _ = 1, 2 do
		scen(parent, {
			name = "TieStack", size = Vector3.new(8, rng:NextNumber(2, 4), 4),
			cf = CFrame.new(rng:NextNumber(8, 88), GROUND_Y + 1.6, (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(24, 60)),
			color = Palette.SleeperWood, material = M.Wood,
		})
	end
	rock(parent, rng, rng:NextNumber(8, 88), rng:NextNumber(12, 40), Color3.fromRGB(30, 30, 33))
	rock(parent, rng, rng:NextNumber(8, 88), -rng:NextNumber(12, 40), Color3.fromRGB(30, 30, 33))

	-- two hero silhouettes per yard chunk, drawn without replacement
	local heroes = { "gantry", "signalbridge", "smokestack", "warehouse" }
	local firstPick = rng:NextInteger(1, 4)
	local secondPick = rng:NextInteger(1, 3)
	if secondPick >= firstPick then
		secondPick += 1
	end
	for _, pick in ipairs({ heroes[firstPick], heroes[secondPick] }) do
		if pick == "gantry" then
			local gx = rng:NextNumber(24, 72)
			for _, gz in ipairs({ -34, -58 }) do
				scen(parent, { name = "GantryLeg", size = Vector3.new(2, 22, 2), cf = CFrame.new(gx, GROUND_Y + 11, gz), color = Palette.YardSteel, material = M.CorrodedMetal })
			end
			scen(parent, { name = "GantryBeam", size = Vector3.new(2.5, 2.5, 28), cf = CFrame.new(gx, GROUND_Y + 22, -46), color = Palette.YardSteel, material = M.CorrodedMetal })
			local tz = rng:NextNumber(-52, -40)
			scen(parent, { name = "GantryTrolley", size = Vector3.new(3, 2, 3), cf = CFrame.new(gx, GROUND_Y + 19.8, tz), color = Palette.YardSteel, material = M.CorrodedMetal })
			local cableLen = rng:NextNumber(4, 7)
			scen(parent, { name = "GantryCable", size = Vector3.new(0.3, cableLen, 0.3), cf = CFrame.new(gx, GROUND_Y + 18.8 - cableLen / 2, tz), color = Palette.YardSteel, material = M.Metal })
			scen(parent, { name = "GantryHook", size = Vector3.new(1.5, 1.5, 1.5), cf = CFrame.new(gx, GROUND_Y + 18 - cableLen, tz), color = Palette.YardSteel, material = M.CorrodedMetal })
		elseif pick == "signalbridge" then
			local bx = rng:NextNumber(20, 80)
			for _, bz in ipairs({ -11, 11 }) do
				local truss = Forge.truss({
					parent = parent, name = "BridgeTruss",
					size = Vector3.new(2, 22, 2),
					cf = CFrame.new(bx, GROUND_Y + 11, bz),
					color = Palette.YardSteel, material = M.Metal,
					cancollide = false, canquery = false,
				})
				truss.CastShadow = false
			end
			scen(parent, { name = "BridgeBeam", size = Vector3.new(1.5, 1.5, 24.5), cf = CFrame.new(bx, GROUND_Y + 21.4, 0), color = Palette.YardSteel, material = M.Metal })
			for _, hz in ipairs({ -3, 0, 3 }) do
				scen(parent, { name = "SignalHood", size = Vector3.new(1.1, 1.4, 0.9), cf = CFrame.new(bx, GROUND_Y + 20, hz), color = Palette.YardSteel, material = M.Metal })
				scen(parent, {
					name = "SignalLens", size = Vector3.new(0.15, 0.45, 0.45),
					cf = CFrame.new(bx - 0.6, GROUND_Y + 20, hz),
					color = rng:NextNumber() < 0.7 and Palette.SignalAmber or Palette.EmergencyRed,
					material = M.Neon,
				})
			end
		elseif pick == "smokestack" then
			local kx = rng:NextNumber(16, 80)
			local kz = (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(130, 170)
			scen(parent, { shape = "cyl", name = "Stack", size = Vector3.new(44, 7, 7), cf = CFrame.new(kx, GROUND_Y + 22, kz) * CFrame.Angles(0, 0, math.rad(90)), color = Color3.fromRGB(36, 26, 24), material = M.Brick })
			scen(parent, { shape = "cyl", name = "StackCap", size = Vector3.new(1.5, 8.5, 8.5), cf = CFrame.new(kx, GROUND_Y + 44.5, kz) * CFrame.Angles(0, 0, math.rad(90)), color = Color3.fromRGB(20, 20, 22), material = M.Metal })
			if rng:NextNumber() < 0.4 then
				scen(parent, { name = "StackBeacon", size = Vector3.new(0.6, 0.6, 0.6), cf = CFrame.new(kx + 3.5, GROUND_Y + 45.5, kz), color = Palette.EmergencyRed, material = M.Neon })
			end
		else
			local wz = (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(80, 130)
			scen(parent, { name = "Warehouse", size = Vector3.new(40, 16, 18), cf = CFrame.new(48, GROUND_Y + 8, wz), color = Color3.fromRGB(18, 18, 22), material = M.Concrete })
			scen(parent, { shape = "wedge", name = "WarehouseRoof", size = Vector3.new(40, 5, 18), cf = CFrame.new(48, GROUND_Y + 18.5, wz), color = Color3.fromRGB(14, 14, 17), material = M.Slate })
			scen(parent, {
				name = "GrimGlow", size = Vector3.new(30, 1.2, 0.3),
				cf = CFrame.new(48, GROUND_Y + 13, wz - math.sign(wz) * 9.2),
				color = Color3.fromRGB(60, 52, 40), material = M.Neon, transparency = 0.35,
			})
		end
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
		transparency = 0.05, reflectance = 0.65, cancollide = false, canquery = false,
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

-- Two depth bands of overlapping ridges + horizon aprons: a continuous
-- rolling skyline instead of lonely teeth, melting into the fog.
local function buildFarChunk(i)
	local model = Instance.new("Model")
	model.Name = "Far_" .. i
	model.WorldPivot = CFrame.new()
	local rng = Random.new(seed * 29 + i * 977)

	for _, side in ipairs({ -1, 1 }) do
		-- Band A: near ridge, slate, slight per-part value jitter
		for _, slot in ipairs({ 32, 192, 352 }) do
			local w = rng:NextNumber(200, 260)
			local h = rng:NextNumber(55, 95)
			scen(model, {
				shape = "wedge", name = "RidgeA",
				size = Vector3.new(w, h, rng:NextNumber(50, 70)),
				cf = CFrame.new(slot + rng:NextNumber(-28, 28), (GROUND_Y - 6) + h / 2, side * (232 + rng:NextNumber(0, 18)))
					* CFrame.Angles(0, rng:NextNumber() < 0.5 and math.rad(180) or 0, 0),
				color = jitterColor(rng, Palette.RidgeNear, 3), material = M.Slate,
			})
		end
		local dA = rng:NextNumber(200, 260)
		scen(model, {
			shape = "ball", name = "HillA",
			size = Vector3.new(dA, 0.6 * dA, dA),
			cf = CFrame.new(rng:NextNumber(60, 324), GROUND_Y - 0.02 * dA, side * (238 + rng:NextNumber(0, 14))),
			color = Palette.RidgeNear, material = M.Slate,
		})

		-- Band B: far ridge, dead flat, one step from vanishing
		for _, slot in ipairs({ 96, 288 }) do
			local w = rng:NextNumber(260, 340)
			local h = rng:NextNumber(95, 150)
			scen(model, {
				shape = "wedge", name = "RidgeB",
				size = Vector3.new(w, h, rng:NextNumber(60, 90)),
				cf = CFrame.new(slot + rng:NextNumber(-40, 40), (GROUND_Y - 8) + h / 2, side * (348 + rng:NextNumber(0, 24)))
					* CFrame.Angles(0, rng:NextNumber() < 0.5 and math.rad(180) or 0, 0),
				color = Palette.RidgeFar, material = M.Smooth,
			})
		end
		local dB = rng:NextNumber(300, 380)
		scen(model, {
			shape = "ball", name = "HillB",
			size = Vector3.new(dB, 0.55 * dB, dB),
			cf = CFrame.new(rng:NextNumber(40, 344), GROUND_Y, side * (352 + rng:NextNumber(0, 20))),
			color = Palette.RidgeFar, material = M.Smooth,
		})

		-- horizon apron: no void ever peeks between ridge bases
		scen(model, {
			name = "Apron", size = Vector3.new(384, 1, 300),
			cf = CFrame.new(192, 4.1, side * 360),
			color = Palette.HorizonApron, material = M.Smooth,
		})
	end

	-- somebody lives out there
	if rng:NextNumber() < 0.12 then
		local side = rng:NextNumber() < 0.5 and -1 or 1
		scen(model, {
			name = "FarWindow", size = Vector3.new(1.2, 1.2, 0.4),
			cf = CFrame.new(rng:NextNumber(60, 324), GROUND_Y + rng:NextNumber(25, 45), side * 236),
			color = Palette.WarmWindow, material = M.Neon,
		})
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

	-- the moon stands still no matter how far you run, rising behind the ridges
	if moon then
		local moonCF = CFrame.new(cam.CFrame.Position + Vector3.new(300, 190, -560))
		moon.CFrame = moonCF
		if moonHaloInner then
			moonHaloInner.CFrame = moonCF
		end
		if moonHaloOuter then
			moonHaloOuter.CFrame = moonCF
		end
	end

	-- as the land changes, so does the air
	local biomeKind
	local feature = RunPlan.featureAt(seed, sCenter)
	if feature and feature.kind == "gorge" then
		biomeKind = "gorge"
	elseif not feature then
		biomeKind = RunPlan.biomeAt(seed, sCenter)
	end
	if biomeKind and biomeKind ~= lastBiomeSent then
		lastBiomeSent = biomeKind
		LightingDirector.setBiome(biomeKind)
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
		size = Vector3.new(46, 46, 46),
		cf = CFrame.new(0, 300, -600),
		color = Palette.Moon, material = M.Neon,
		cancollide = false, canquery = false, castshadow = false,
	})
	-- glow is geometry, not a dead-at-range PointLight: two nested halos
	moonHaloInner = Forge.ball({
		parent = root, name = "MoonHaloInner",
		size = Vector3.new(66, 66, 66),
		cf = moon.CFrame,
		color = Palette.MoonHaloInner, material = M.Neon,
		transparency = 0.72, cancollide = false, canquery = false, castshadow = false,
	})
	moonHaloOuter = Forge.ball({
		parent = root, name = "MoonHaloOuter",
		size = Vector3.new(100, 100, 100),
		cf = moon.CFrame,
		color = Palette.MoonHaloOuter, material = M.Neon,
		transparency = 0.90, cancollide = false, canquery = false, castshadow = false,
	})

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
