--[[
	Sleeper.luau
	One car on the line is a nest, and the nest is full. A car-wide noise
	meter climbs while riders are inside — faster for the sprinting, the
	door-slamming, the flare-striking. Wake it and everyone in the car
	pays, and it howls the Furnace down the line early.
	The loot around the nest is the whole temptation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local SoundBank = require(Shared.SoundBank)
local Util = require(Shared.Util)
local Palette = require(Shared.Palette)

local Sleeper = {}
local ctx

local E = Config.Entities.Sleeper

local carIndex = nil
local level = 0
local stage = "sleep" -- sleep | stir | panic
local loopThread = nil
local wakeCooldownUntil = 0

-- Direct noise injections (flares, slams) while inside its car hit harder.
local function onNoiseEvent(_player, amount, position)
	if not carIndex or not position then
		return
	end
	local car = math.floor(position.X / Config.Train.CarPitch) + 1
	if car == carIndex then
		level = math.clamp(level + amount * 0.55, 0, 1)
	end
end

function Sleeper.init(c)
	ctx = c
	ctx.signals.noiseEvent:connect(onNoiseEvent)
end

local function setEyes(open)
	local meta = carIndex and ctx.TrainBuilder.carMeta(carIndex)
	if not meta then
		return
	end
	for _, eye in ipairs(meta.sleeperEyes or {}) do
		if eye.Parent then
			eye.Material = open and Enum.Material.Neon or Enum.Material.Glass
			eye.Color = open and Palette.EyeShine or Color3.fromRGB(50, 46, 40)
		end
	end
end

local function setStage(next)
	if stage == next then
		return
	end
	stage = next
	Net.fireAll(Net.T.SleeperStage, { stage = next, level = level })
	local pos = carIndex and ctx.TrainBuilder.carPosition(carIndex)
	if next == "stir" then
		setEyes(false)
		if pos then
			SoundBank.play("SleeperGrowl", pos, { max = 160 })
		end
	elseif next == "panic" then
		setEyes(true)
		if pos then
			SoundBank.play("SleeperGrowl", pos, { max = 200, pitchScale = 0.8 })
		end
	else
		setEyes(false)
	end
end

local function wake()
	wakeCooldownUntil = os.clock() + 10
	level = 0.35
	setStage("sleep")
	local pos = ctx.TrainBuilder.carPosition(carIndex)
	SoundBank.play("SleeperWake", pos, { max = 400 })
	Net.fireAll(Net.T.SleeperStage, { stage = "wake", level = 1 })
	Net.fireAll(Net.T.Subtitle, { text = "It wakes. The whole car is its mouth for a moment.", seconds = 5 })
	for _, player in ipairs(ctx.EntityUtil.playersInCar(carIndex, false)) do
		ctx.PlayerService.damage(player, E.WakeDamage, "sleeper")
		local char, hum, root = Util.aliveCharacter(player)
		if char and root then
			-- hurled toward the rear door, away from the nest
			root.CFrame = root.CFrame * CFrame.new(0, 0.5, 0) + Vector3.new(-9, 1.5, ctx.rng:NextNumber(-2, 2))
			if hum then
				hum:ChangeState(Enum.HumanoidStateType.FallingDown)
			end
		end
	end
	-- it howls; the Furnace answers
	ctx.Timetable.forceFurnace(5)
end

local function loop()
	while carIndex do
		task.wait(0.25)
		if not ctx.TrainBuilder.isBuilt(carIndex) then
			task.wait(2)
			continue
		end
		local occupants = ctx.EntityUtil.playersInCar(carIndex, true)
		local rise = 0
		for _, player in ipairs(occupants) do
			rise += ctx.PlayerService.noiseOf(player) * 0.09
		end
		level = math.clamp(level + rise - E.MeterDecayPerSecond * 0.25, 0, 1)

		if os.clock() > wakeCooldownUntil then
			if level >= 1 then
				wake()
			elseif level >= E.PanicAt then
				setStage("panic")
			elseif level >= E.StirAt then
				setStage("stir")
			else
				setStage("sleep")
			end
		end

		if #occupants > 0 then
			Net.fireList(occupants, Net.T.SleeperStage, { stage = stage, level = level })
		end
	end
end

function Sleeper.activate(car)
	if carIndex == car then
		return
	end
	carIndex = car
	level = 0.12
	stage = "sleep"
	Net.fireAll(Net.T.Subtitle, { text = "Bedding, torn and mounded. Breathing, slow. Do not wake it.", seconds = 5 })
	if not loopThread then
		loopThread = task.spawn(loop)
	end
end

function Sleeper.stop()
	carIndex = nil
	level = 0
	stage = "sleep"
	if loopThread then
		pcall(task.cancel, loopThread)
		loopThread = nil
	end
end

return Sleeper
