--[[
	TrainBuilder.luau
	Owns which cars exist. Geometry lives in CarPlans; doors in DoorSystem;
	this module orchestrates building/unbuilding as the group advances,
	the lobby platform, lamps, and the void seal behind the last kept car.

	Layout: car i occupies X in [(i-1)*Pitch, (i-1)*Pitch + CarLength].
	The gap up to the next car holds the gangway (DoorSystem's boundary).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Forge = require(Shared.Forge)
local Palette = require(Shared.Palette)

local TrainBuilder = {}

local ctx
local cars = {}       -- [i] = meta from CarPlans
local plan = nil
local lobbyModel = nil
local voidSeal = nil
local rearMost = 1

local T = Config.Train

function TrainBuilder.init(c)
	ctx = c
end

----------------------------------------------------------------
-- Coordinates
----------------------------------------------------------------
function TrainBuilder.carOriginX(i)
	return (i - 1) * T.CarPitch
end

function TrainBuilder.carPosition(i)
	return Vector3.new(TrainBuilder.carOriginX(i) + T.CarLength / 2, T.FloorY + 4, 0)
end

function TrainBuilder.interiorSpawn(i)
	return CFrame.new(TrainBuilder.carOriginX(i) + 7, T.FloorY + 3.5, 0)
end

function TrainBuilder.carIndexAt(pos)
	-- half-width plus a whisker: platform-standers are NOT aboard
	if math.abs(pos.Z) > T.CarWidth / 2 + 1 then
		return nil
	end
	local i = math.floor(pos.X / T.CarPitch) + 1
	if i < 1 or i > T.Cars then
		return nil
	end
	return i
end

function TrainBuilder.isOnRoof(pos)
	return pos.Y > T.FloorY + T.CarHeight + 0.5
end

----------------------------------------------------------------
-- Cars
----------------------------------------------------------------
function TrainBuilder.isBuilt(i)
	return cars[i] ~= nil
end

function TrainBuilder.carMeta(i)
	return cars[i]
end

function TrainBuilder.frontMostBuilt()
	local front = 1
	for i in pairs(cars) do
		front = math.max(front, i)
	end
	return front
end

function TrainBuilder.rearMostBuilt()
	return rearMost
end

function TrainBuilder.buildCar(i)
	if cars[i] or not plan then
		return
	end
	local entry = plan.cars[i]
	if not entry then
		return
	end
	local meta = ctx.CarPlans.buildCar(entry, ctx.folders.train)
	cars[i] = meta

	ctx.HideSystem.registerCar(i, meta)
	ctx.LootSystem.populateCar(i, meta)
	ctx.DoorSystem.wireCar(i, meta)

	-- Boundary (gangway + door) ahead of this car, once its neighbor exists
	-- or immediately: the boundary belongs to car i and leads to i+1.
	if i < T.Cars then
		ctx.DoorSystem.buildBoundary(i, entry, plan.cars[i + 1])
	end
	if i > 1 and cars[i - 1] == nil and i - 1 >= rearMost then
		-- built out of order (shouldn't happen, but stay safe)
		TrainBuilder.buildCar(i - 1)
	end
	return meta
end

local function destroyCar(i)
	local meta = cars[i]
	if not meta then
		return
	end
	cars[i] = nil
	ctx.HideSystem.unregisterCar(i)
	ctx.LootSystem.unregisterCar(i)
	ctx.DoorSystem.destroyBoundary(i)
	if meta.model then
		meta.model:Destroy()
	end
end

-- The dark curtain that eats the rear of the train.
local function placeVoidSeal(behindCar)
	if voidSeal then
		voidSeal:Destroy()
	end
	local x = TrainBuilder.carOriginX(behindCar) - 2
	voidSeal = Forge.model("VoidSeal", ctx.folders.train)
	Forge.part({
		parent = voidSeal, name = "Wall",
		size = Vector3.new(1, 22, 18),
		cf = CFrame.new(x, T.FloorY + 8, 0),
		color = Color3.new(0, 0, 0), material = Palette.M.Smooth,
	})
	local mist = Forge.part({
		parent = voidSeal, name = "Mist",
		size = Vector3.new(0.5, 12, 10),
		cf = CFrame.new(x + 1, T.FloorY + 5, 0),
		color = Color3.new(0, 0, 0), material = Palette.M.Smooth,
		transparency = 1, cancollide = false,
	})
	Forge.particles(mist, {
		color = ColorSequence.new(Color3.fromRGB(10, 10, 14)),
		size = NumberSequence.new(3, 6),
		transparency = NumberSequence.new(0.55, 1),
		lifetime = NumberRange.new(1.5, 2.5),
		rate = 14,
		speed = NumberRange.new(0.5, 2),
		spread = Vector2.new(40, 40),
	})
	ctx.DoorSystem.sealRearOf(behindCar)
end

function TrainBuilder.unbuildBefore(i)
	local target = math.max(i, 1)
	if target <= rearMost then
		return
	end
	for k = rearMost, target - 1 do
		destroyCar(k)
	end
	rearMost = target
	if rearMost > 1 then
		placeVoidSeal(rearMost)
	end
end

----------------------------------------------------------------
-- Lamps (the Furnace shatters them; stations rekindle them)
----------------------------------------------------------------
function TrainBuilder.setLamps(i, lit)
	local meta = cars[i]
	if not meta then
		return
	end
	meta.lampsLit = lit
	for _, lamp in ipairs(meta.lamps or {}) do
		if lamp.light then
			lamp.light.Enabled = lit
		end
		if lamp.glow then
			lamp.glow.Material = lit and Palette.M.Neon or Palette.M.Glass
			lamp.glow.Color = lit and Palette.LampGlass or Color3.fromRGB(60, 56, 50)
		end
	end
end

function TrainBuilder.lampsLit(i)
	local meta = cars[i]
	return meta and meta.lampsLit ~= false
end

function TrainBuilder.relightAll()
	for i in pairs(cars) do
		TrainBuilder.setLamps(i, true)
	end
end

-- Stations board up what the Parallel broke.
function TrainBuilder.repairWindows()
	for _, meta in pairs(cars) do
		for _, win in ipairs(meta.windows or {}) do
			if win.broken and win.glass and win.glass.Parent then
				win.broken = false
				win.glass.Transparency = 0.42
				win.glass.CanCollide = true
				win.model:SetAttribute("Broken", false)
			end
		end
	end
end

----------------------------------------------------------------
-- Lobby platform (Terminus)
----------------------------------------------------------------
local function buildLobby()
	lobbyModel = Forge.model("Terminus", ctx.folders.lobby)
	local M = Palette.M
	local floorY = T.FloorY
	local zNear = T.CarWidth / 2 + 0.5 -- platform edge against the car side

	-- solid ground around the terminus so nobody strolls into the void
	Forge.part({
		parent = lobbyModel, name = "Ground",
		size = Vector3.new(340, 1, 220),
		cf = CFrame.new(40, 5.4, 40),
		color = Palette.GroundNight, material = M.Ground,
	})

	-- Platform slab, flush with the car floor for step-free boarding
	Forge.part({
		parent = lobbyModel, name = "Slab",
		size = Vector3.new(120, 1.2, 16),
		cf = CFrame.new(30, floorY - 0.6, zNear + 8),
		color = Palette.Gravel, material = M.Concrete,
	})
	Forge.part({
		parent = lobbyModel, name = "Edge",
		size = Vector3.new(120, 0.4, 1.2),
		cf = CFrame.new(30, floorY - 0.2 + 0.2, zNear + 0.6),
		color = Color3.fromRGB(200, 190, 170), material = M.Concrete,
	})
	-- Steps down at the back so nobody is trapped
	for s = 1, 4 do
		Forge.part({
			parent = lobbyModel,
			size = Vector3.new(10, 1.2, 2),
			cf = CFrame.new(30, floorY - 0.6 - s * 1.2, zNear + 16 + s * 1),
			color = Palette.Gravel, material = M.Concrete,
		})
	end

	-- Canopy with columns
	for x = -10, 110, 24 do
		Forge.cyl({
			parent = lobbyModel,
			size = Vector3.new(9.5, 0.8, 0.8),
			cf = CFrame.new(x + 40 - 40, floorY + 4.75, zNear + 12) * CFrame.Angles(0, 0, math.rad(90)),
			color = Color3.fromRGB(40, 44, 48), material = M.Metal,
		})
	end
	Forge.part({
		parent = lobbyModel, name = "Canopy",
		size = Vector3.new(124, 0.5, 12),
		cf = CFrame.new(30, floorY + 9.6, zNear + 11),
		color = Palette.CarRoof, material = M.Slate,
	})

	-- Gas lamps along the platform
	for x = -6, 106, 16 do
		local post = Forge.part({
			parent = lobbyModel,
			size = Vector3.new(0.5, 6.5, 0.5),
			cf = CFrame.new(x, floorY + 3.25, zNear + 6),
			color = Color3.fromRGB(30, 32, 34), material = M.Metal,
		})
		local head = Forge.part({
			parent = lobbyModel,
			size = Vector3.new(1, 1.2, 1),
			cf = CFrame.new(x, floorY + 7, zNear + 6),
			color = Palette.LampGlass, material = M.Neon,
		})
		head.Name = "LampHead"
		Forge.light(head, { color = Palette.LampGlow, range = 17, brightness = 0.9, flicker = true, shadows = true })
		post.Name = "LampPost"
	end

	-- Station board
	local board = Forge.part({
		parent = lobbyModel, name = "Board",
		size = Vector3.new(14, 4, 0.6),
		cf = CFrame.new(30, floorY + 7, zNear + 13.5),
		color = Color3.fromRGB(22, 24, 26), material = M.Wood,
	})
	Forge.surfaceText(board, Enum.NormalId.Front, "TERMINUS · THE VALLEY LINE\n11:59 — LAST SERVICE — ALL CARS", {
		color = Palette.CarLetters, font = Palette.FontHeader, pps = 40,
	})

	-- The clock that never passes midnight
	local clock = Forge.cyl({
		parent = lobbyModel, name = "Clock",
		size = Vector3.new(0.5, 3.4, 3.4),
		cf = CFrame.new(56, floorY + 8, zNear + 11.8) * CFrame.Angles(0, math.rad(90), 0),
		color = Color3.fromRGB(228, 220, 200), material = M.Smooth,
	})
	Forge.surfaceText(clock, Enum.NormalId.Right, "11:59", {
		color = Palette.UIInk, font = Palette.FontHeader, pps = 60,
	})

	-- Benches
	for x = 8, 96, 22 do
		Forge.part({
			parent = lobbyModel,
			size = Vector3.new(6, 0.5, 1.6),
			cf = CFrame.new(x, floorY + 1.4, zNear + 9),
			color = Palette.SleeperWood, material = M.Wood,
		})
		Forge.part({
			parent = lobbyModel,
			size = Vector3.new(6, 1.4, 0.4),
			cf = CFrame.new(x, floorY + 2.2, zNear + 9.7),
			color = Palette.SleeperWood, material = M.Wood,
		})
	end
end

function TrainBuilder.lobbySpawnCF()
	local x = 20 + math.random() * 30
	return CFrame.new(x, T.FloorY + 3.5, T.CarWidth / 2 + 6)
		* CFrame.Angles(0, math.rad(180), 0) -- face the train
end

function TrainBuilder.hasLobby()
	return lobbyModel ~= nil
end

function TrainBuilder.clearLobby()
	if lobbyModel then
		lobbyModel:Destroy()
		lobbyModel = nil
	end
end

----------------------------------------------------------------
-- Run lifecycle
----------------------------------------------------------------
function TrainBuilder.beginRun(newPlan)
	TrainBuilder.teardown()
	plan = newPlan
	rearMost = 1
	buildLobby()
	for i = 1, 3 do
		TrainBuilder.buildCar(i)
	end
end

function TrainBuilder.teardown()
	for i in pairs(cars) do
		destroyCar(i)
	end
	cars = {}
	if voidSeal then
		voidSeal:Destroy()
		voidSeal = nil
	end
	TrainBuilder.clearLobby()
	ctx.DoorSystem.teardown()
	ctx.folders.train:ClearAllChildren()
	ctx.folders.pickups:ClearAllChildren()
	ctx.folders.entities:ClearAllChildren()
	ctx.folders.station:ClearAllChildren()
end

return TrainBuilder
