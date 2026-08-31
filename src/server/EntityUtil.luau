--[[
	EntityUtil.luau
	Common bones for the things on the train: aisle math, occupancy
	queries, and a procedural biped rig with a stepped walk cycle.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Forge = require(Shared.Forge)
local Tags = require(Shared.Tags)
local Util = require(Shared.Util)

local EntityUtil = {}
local ctx

local T = Config.Train
local FLOOR = T.FloorY

function EntityUtil.init(c)
	ctx = c
end

----------------------------------------------------------------
-- Queries
----------------------------------------------------------------
function EntityUtil.aislePos(x, height)
	return Vector3.new(x, FLOOR + (height or 2.6), 0)
end

function EntityUtil.playersInCar(carIndex, includeDowned)
	local out = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if not player:GetAttribute("Ghost") and (player:GetAttribute("CarIndex") or 0) == carIndex then
			if includeDowned or not player:GetAttribute("Downed") then
				local char = Util.aliveCharacter(player)
				if char then
					table.insert(out, player)
				end
			end
		end
	end
	return out
end

function EntityUtil.occupiedRange()
	local minCar, maxCar = nil, nil
	for _, player in ipairs(Players:GetPlayers()) do
		if not player:GetAttribute("Ghost") then
			local car = player:GetAttribute("CarIndex") or 0
			if car >= 1 then
				minCar = math.min(minCar or car, car)
				maxCar = math.max(maxCar or car, car)
			end
		end
	end
	return minCar, maxCar
end

function EntityUtil.isExposed(player)
	-- not hidden, not on the roof: fair game for aisle sweepers
	local char, _, root = Util.aliveCharacter(player)
	if not char then
		return false
	end
	if player:GetAttribute("HiddenSpot") ~= "" and player:GetAttribute("HiddenSpot") ~= nil then
		return false
	end
	if ctx.TrainBuilder.isOnRoof(root.Position) then
		return false
	end
	return true
end

----------------------------------------------------------------
-- Rigs
----------------------------------------------------------------
--[[
	Builds a tall anchored biped from parts. spec:
	  height (total), coat (color), skin, name, glowEyes (bool), scale
	Returns rig = { model, root, head, legL, legR, armL, armR, setCF, stride }
	setCF places the pelvis; stride(t, speed) animates legs/arms/bob.
]]
function EntityUtil.buildBiped(spec)
	local height = spec.height or 7
	local unit = height / 7
	local model = Forge.model(spec.name or "Figure", ctx.folders.entities)
	CollectionService:AddTag(model, Tags.EntityRig)

	local coat = spec.coat or Color3.fromRGB(24, 22, 26)
	local material = spec.material or Enum.Material.Fabric

	local torso = Forge.part({
		parent = model, name = "Torso",
		size = Vector3.new(2 * unit, 2.6 * unit, 1.1 * unit),
		color = coat, material = material, cancollide = false,
	})
	local head = Forge.part({
		parent = model, name = "Head",
		size = Vector3.new(0.95 * unit, 1.15 * unit, 0.95 * unit),
		color = spec.skin or Color3.fromRGB(214, 200, 186),
		material = spec.skinMaterial or Enum.Material.SmoothPlastic,
		cancollide = false,
	})
	local limbs = {}
	for _, limbSpec in ipairs({
		{ "ArmL", 0.55, 2.4, -1 }, { "ArmR", 0.55, 2.4, 1 },
		{ "LegL", 0.62, 2.6, -1 }, { "LegR", 0.62, 2.6, 1 },
	}) do
		limbs[limbSpec[1]] = Forge.part({
			parent = model, name = limbSpec[1],
			size = Vector3.new(limbSpec[2] * unit, limbSpec[3] * unit, limbSpec[2] * unit),
			color = coat, material = material, cancollide = false,
		})
	end

	local eyes = {}
	if spec.glowEyes then
		for _, side in ipairs({ -0.22, 0.22 }) do
			local eye = Forge.part({
				parent = model, name = "Eye",
				size = Vector3.new(0.16 * unit, 0.1 * unit, 0.1 * unit),
				color = spec.eyeColor or Color3.fromRGB(255, 244, 180),
				material = Enum.Material.Neon, cancollide = false, castshadow = false,
			})
			table.insert(eyes, { part = eye, offset = Vector3.new(side * unit, 0.12 * unit, -0.45 * unit) })
		end
	end

	local rig = {
		model = model,
		torso = torso,
		head = head,
		limbs = limbs,
		eyes = eyes,
		unit = unit,
		phase = 0,
	}

	-- pelvisCF: position of hip center, facing = LookVector
	function rig.setCF(pelvisCF, dt, moveSpeed)
		local u = unit
		local speed = moveSpeed or 0
		rig.phase += (dt or 0.03) * math.clamp(speed, 0, 20) * 1.6
		local swing = math.sin(rig.phase)
		local bob = math.abs(math.cos(rig.phase)) * 0.12 * u * math.clamp(speed / 6, 0, 1)

		local base = pelvisCF * CFrame.new(0, bob, 0)
		torso.CFrame = base * CFrame.new(0, 1.9 * u, 0) * CFrame.Angles(math.rad(3), 0, 0)
		head.CFrame = base * CFrame.new(0, 3.6 * u, 0) * CFrame.Angles(math.rad(spec.headTilt or -4), 0, 0)
		for _, eye in ipairs(eyes) do
			eye.part.CFrame = head.CFrame * CFrame.new(eye.offset)
		end
		local armAng = swing * 0.5 * math.clamp(speed / 6, 0, 1)
		local legAng = swing * 0.7 * math.clamp(speed / 6, 0, 1)
		limbs.ArmL.CFrame = base * CFrame.new(-1.25 * u, 2.2 * u, 0) * CFrame.Angles(armAng, 0, math.rad(4)) * CFrame.new(0, -1 * u, 0)
		limbs.ArmR.CFrame = base * CFrame.new(1.25 * u, 2.2 * u, 0) * CFrame.Angles(-armAng, 0, math.rad(-4)) * CFrame.new(0, -1 * u, 0)
		limbs.LegL.CFrame = base * CFrame.new(-0.5 * u, 0.6 * u, 0) * CFrame.Angles(-legAng, 0, 0) * CFrame.new(0, -1.2 * u, 0)
		limbs.LegR.CFrame = base * CFrame.new(0.5 * u, 0.6 * u, 0) * CFrame.Angles(legAng, 0, 0) * CFrame.new(0, -1.2 * u, 0)
	end

	function rig.destroy()
		model:Destroy()
	end

	return rig
end

-- Walks a rig from its current x to targetX along the aisle; yields.
-- onStep(x) may return true to pause the walk while it returns true.
function EntityUtil.walkAisle(rig, fromX, targetX, speed, onStep)
	local x = fromX
	local dir = targetX > fromX and 1 or -1
	-- pelvis sits at hip height; the legs hang 2.45 units below
	local pelvisY = FLOOR + 2.45 * rig.unit
	while (targetX - x) * dir > 0.5 do
		local dt = task.wait()
		local hold = onStep and onStep(x)
		if hold == "stop" then
			return "stopped"
		end
		local step = hold and 0 or speed * dt * dir
		x += step
		local look = CFrame.lookAt(Vector3.new(x, pelvisY, 0), Vector3.new(x + dir * 4, pelvisY, 0))
		rig.setCF(look, dt, hold and 0 or speed)
	end
	return "arrived"
end

return EntityUtil
