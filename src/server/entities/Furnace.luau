--[[
	Furnace.luau
	The engine's appetite, loose in the corridors. Lamps burst car by car
	ahead of it; pistons hammer; then it tears through the aisle at speed.
	Counterplay: a hide spot, or the roof. It occasionally doubles back.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Forge = require(Shared.Forge)
local Palette = require(Shared.Palette)
local SoundBank = require(Shared.SoundBank)
local Util = require(Shared.Util)
local Tags = require(Shared.Tags)

local Furnace = {}
local ctx

local E = Config.Entities.Furnace
local T = Config.Train

local active = false

function Furnace.init(c)
	ctx = c
end

function Furnace.isActive()
	return active
end

local function buildRig()
	local model = Forge.model("Furnace", ctx.folders.entities)
	local CollectionService = game:GetService("CollectionService")
	CollectionService:AddTag(model, Tags.EntityRig)
	model:SetAttribute("EntityKind", "Furnace")

	local core = Forge.ball({
		parent = model, name = "Core",
		size = Vector3.new(2.6, 2.6, 2.6),
		color = Palette.FurnaceCore, material = Enum.Material.Neon,
		cancollide = false, castshadow = false,
	})
	Forge.light(core, { color = Palette.FurnaceCore, range = 26, brightness = 3, shadows = true })
	local att = Forge.attach(core, CFrame.new())
	Forge.particles(att, {
		color = ColorSequence.new(Palette.FurnaceEmber, Color3.fromRGB(120, 20, 8)),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0.1) }),
		lifetime = NumberRange.new(0.4, 1),
		rate = 90,
		speed = NumberRange.new(4, 9),
		spread = Vector2.new(60, 60),
		lightEmission = 1,
		lightInfluence = 0,
	})
	Forge.particles(att, {
		color = ColorSequence.new(Color3.fromRGB(30, 30, 32)),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 4) }),
		transparency = NumberSequence.new(0.5, 1),
		lifetime = NumberRange.new(0.8, 1.6),
		rate = 30,
		speed = NumberRange.new(1, 3),
		spread = Vector2.new(40, 40),
	})
	return model, core
end

local function sweep(fromX, toX, hitSet)
	local model, core = buildRig()
	local dir = toX > fromX and 1 or -1
	local x = fromX
	local lastCar = nil
	local lastPiston = 0
	local aliveSweep = true

	while aliveSweep and (toX - x) * dir > 0 do
		local dt = RunService.Heartbeat:Wait()
		if not core.Parent or not active then -- torn down mid-sweep (run reset)
			break
		end
		x += E.Speed * dt * dir
		local wobble = math.sin(os.clock() * 30) * 0.25
		core.CFrame = CFrame.new(x, T.FloorY + 2.8 + wobble, math.sin(os.clock() * 17) * 0.6)

		if os.clock() - lastPiston > 0.33 then
			lastPiston = os.clock()
			SoundBank.play("FurnacePiston", core.Position, { max = 240, volumeScale = 1 })
		end

		local carHere = math.floor(x / T.CarPitch) + 1
		if carHere ~= lastCar and carHere >= 1 and carHere <= T.Cars then
			lastCar = carHere
			if ctx.TrainBuilder.isBuilt(carHere) then
				Net.fireAll(Net.T.FurnacePass, { car = carHere })
				ctx.TrainBuilder.setLamps(carHere, false)
				ctx.signals.furnaceCar:fire(carHere)
				SoundBank.play("LampBurst", ctx.TrainBuilder.carPosition(carHere))
				task.delay(E.LampRelightSeconds, function()
					if ctx.TrainBuilder.isBuilt(carHere) then
						ctx.TrainBuilder.setLamps(carHere, true)
						SoundBank.play("LampRelight", ctx.TrainBuilder.carPosition(carHere))
					end
				end)
			end
			-- doors do not argue with it
			local boundary = dir > 0 and carHere or carHere - 1
			ctx.DoorSystem.forceOpen(boundary, true)
		end

		-- the toll (the downed are beneath its notice; they are already coal)
		for _, player in ipairs(Util.livingPlayers()) do
			if not hitSet[player] then
				local char, _, root = Util.aliveCharacter(player)
				if char then
					local sameCar = (player:GetAttribute("CarIndex") or 0) == carHere
					local close = math.abs(root.Position.X - x) < 5
					if sameCar and close and ctx.EntityUtil.isExposed(player) then
						hitSet[player] = true
						ctx.PlayerService.damage(player, E.Damage, "furnace")
						Net.fireClient(player, Net.T.Subtitle, { text = "It went through you like a shovel through coal.", seconds = 4 })
					end
				end
			end
		end

		if math.abs(x) > (T.Cars + 4) * T.CarPitch then
			aliveSweep = false
		end
	end
	model:Destroy()
end

function Furnace.run()
	if active then
		return
	end
	active = true

	local front = ctx.TrainBuilder.frontMostBuilt()
	local rear = ctx.TrainBuilder.rearMostBuilt()
	local fromX = (front) * T.CarPitch + 8
	local toX = (rear - 1) * T.CarPitch - 12

	Net.fireAll(Net.T.FurnaceWarn, { eta = E.WarnSeconds })
	Net.fireAll(Net.T.Subtitle, { text = "Down the line, the lamps begin to die.", seconds = 4 })
	SoundBank.play("FurnaceRoar", Vector3.new(fromX, T.FloorY + 3, 0), { max = 400 })
	task.wait(E.WarnSeconds)

	if ctx.GameLoop.state() == "Journey" then
		local hitSet = {}
		sweep(fromX, toX, hitSet)

		if ctx.rng:NextNumber() < E.RepassChance and ctx.GameLoop.state() == "Journey" then
			task.wait(1.2)
			Net.fireAll(Net.T.FurnaceWarn, { eta = 3 })
			Net.fireAll(Net.T.Subtitle, { text = "It is not finished.", seconds = 3 })
			SoundBank.play("FurnaceRoar", Vector3.new(toX, T.FloorY + 3, 0), { max = 400, pitchScale = 1.2 })
			task.wait(3)
			sweep(toX, fromX + T.CarPitch, {})
		end
	end
	active = false
end

function Furnace.stop()
	active = false
end

return Furnace
