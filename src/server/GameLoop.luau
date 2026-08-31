--[[
	GameLoop.luau
	The run state machine and the train's motion model.

	States: Lobby -> Journey <-> Station -> Finale -> Victory | Defeat -> Lobby
	The train never moves through space; `distance` is how much night has
	been pulled past the windows. Everything with a schedule keys off it.
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local RunPlan = require(Shared.RunPlan)
local SoundBank = require(Shared.SoundBank)
local Tags = require(Shared.Tags)

local GameLoop = {}

local ctx
local state = "Boot"
local distance = 0
local speed = 0
local targetSpeed = 0
local brake = nil -- {startD, startSpeed, stopD}
local stationsDone = {}
local approachingStation = nil
local boardingThread = nil
local finaleStarted = false
local runCounter = 0

local ATTR_UPDATE = 0.1
local sinceAttr = 0
local sinceDistAttr = 0

----------------------------------------------------------------
-- State helpers
----------------------------------------------------------------
function GameLoop.state()
	return state
end

function GameLoop.distance()
	return distance
end

function GameLoop.speed()
	return speed
end

function GameLoop.isMoving()
	return speed > 1
end

local function setState(next)
	if state == next then
		return
	end
	state = next
	workspace:SetAttribute("RunState", next)
	Net.fireAll(Net.T.RunState, { state = next, seed = ctx.plan and ctx.plan.seed or 0 })
	ctx.signals.runStateChanged:fire(next)
end

----------------------------------------------------------------
-- Run lifecycle
----------------------------------------------------------------
local function startRun()
	runCounter += 1
	local seed = ctx.rng:NextInteger(1, 2 ^ 30)
	ctx.plan = RunPlan.build(seed)
	ctx.runSeed = seed
	distance = 0
	speed = 0
	targetSpeed = 0
	brake = nil
	stationsDone = {}
	approachingStation = nil
	finaleStarted = false
	workspace:SetAttribute("RunSeed", seed)
	workspace:SetAttribute("TrainDistance", 0)
	workspace:SetAttribute("TrainSpeed", 0)

	ctx.LootSystem.resetRun()
	ctx.StationService.cleanup()
	ctx.TrainBuilder.beginRun(ctx.plan)
	ctx.PlayerService.spawnAllAtLobby()
	setState("Lobby")
end

local function scoopPlatformPlayers()
	for _, player in ipairs(Players:GetPlayers()) do
		local char, _, root = ctx.util.aliveCharacter(player)
		if char and (player:GetAttribute("CarIndex") or 0) < 1 then
			local cf = ctx.TrainBuilder.interiorSpawn(1)
			root.CFrame = cf + Vector3.new(ctx.rng:NextNumber(-1, 1), 0, ctx.rng:NextNumber(-1, 1))
		end
	end
end

local function depart()
	scoopPlatformPlayers()
	ctx.TrainBuilder.clearLobby()
	setState("Journey")
	targetSpeed = Config.Train.CruiseSpeed
	Net.fireAll(Net.T.BoardingState, { phase = "departed" })
	Net.fireAll(Net.T.Stinger, { name = "Whistle" })
	Net.fireAll(Net.T.Subtitle, { text = "The 11:59 departs. Nobody sold you these tickets.", seconds = 5 })
	SoundBank.play("Whistle", ctx.TrainBuilder.carPosition(1))
	ctx.signals.departed:fire()
	ctx.Timetable.startRun()
end

-- Boarding watcher: once anyone is aboard, the countdown runs; if the
-- caboose empties out, it stands down.
local function boardingWatch()
	while state == "Lobby" do
		task.wait(1)
		if state ~= "Lobby" then
			return
		end
		local aboard = 0
		for _, player in ipairs(ctx.util.livingPlayers(true)) do
			if (player:GetAttribute("CarIndex") or 0) >= 1 then
				aboard += 1
			end
		end
		if aboard > 0 then
			local seconds = Config.Run.LobbyCountdown
			Net.fireAll(Net.T.BoardingState, { phase = "count", seconds = seconds })
			SoundBank.play("StationBell", ctx.TrainBuilder.carPosition(1))
			local abort = false
			for remaining = seconds, 1, -1 do
				task.wait(1)
				if state ~= "Lobby" then
					return
				end
				local stillAboard = 0
				for _, player in ipairs(ctx.util.livingPlayers(true)) do
					if (player:GetAttribute("CarIndex") or 0) >= 1 then
						stillAboard += 1
					end
				end
				if stillAboard == 0 then
					abort = true
					break
				end
				if remaining == 10 then
					Net.fireAll(Net.T.Subtitle, { text = "Last call for the 11:59.", seconds = 4 })
					SoundBank.play("WhistleFar", ctx.TrainBuilder.carPosition(1))
				end
			end
			if not abort and state == "Lobby" then
				depart()
				return
			else
				Net.fireAll(Net.T.BoardingState, { phase = "idle" })
			end
		end
	end
end

function GameLoop.victory()
	if state == "Victory" then
		return
	end
	setState("Victory")
	ctx.Timetable.stopRun()
	targetSpeed = 10
	brake = nil
	Net.fireAll(Net.T.VictoryCine, {})
	Net.fireAll(Net.T.Announce, {
		title = "UNCOUPLED",
		sub = "The engine takes its appetite elsewhere. Dawn finds the cars coasting home.",
		seconds = 8, tone = "good",
	})
	ctx.StatsService.recordRunEnd(true)
	task.delay(12, function()
		if state == "Victory" then
			targetSpeed = 0
		end
	end)
	task.delay(Config.Run.VictoryResetSeconds, function()
		if state == "Victory" then
			startRun()
		end
	end)
end

function GameLoop.defeat(reason)
	if state == "Defeat" or state == "Victory" or state == "Lobby" then
		return
	end
	setState("Defeat")
	ctx.Timetable.stopRun()
	targetSpeed = Config.Train.CruiseSpeed * 1.3 -- the train keeps its schedule without you
	Net.fireAll(Net.T.DefeatCine, {})
	Net.fireAll(Net.T.Announce, {
		title = "THE LINE KEEPS YOU",
		sub = reason or "No riders reached the engine.",
		seconds = 8, tone = "bad",
	})
	ctx.StatsService.recordRunEnd(false)
	task.delay(Config.Run.DefeatResetSeconds, function()
		if state == "Defeat" then
			startRun()
		end
	end)
end

----------------------------------------------------------------
-- Stations
----------------------------------------------------------------
local function beginApproach(stationNumber)
	approachingStation = stationNumber
	-- keep the platform's stretch of track clear of tunnels and gorges
	local stationCar = Config.Run.StationCars[stationNumber]
	local sOffset = (stationCar - 0.5) * Config.Train.CarPitch
	local clearS = RunPlan.clearStretchAfter(ctx.runSeed, distance + sOffset + 350, 1100)
	local stopD = clearS - sOffset
	brake = nil
	-- Let the Timetable know braking will start when we get close.
	task.spawn(function()
		ctx.StationService.approach(stationNumber)
		while state == "Journey" and approachingStation == stationNumber do
			local remaining = stopD - distance
			local brakingDistance = speed * Config.Train.AccelSeconds * 0.55 + 40
			if remaining <= brakingDistance then
				brake = { startD = distance, startSpeed = speed, stopD = stopD }
				break
			end
			task.wait(0.1)
		end
	end)
end

local function arriveStation(stationNumber)
	setState("Station")
	approachingStation = nil
	task.spawn(function()
		ctx.StationService.arrive(stationNumber)
		-- StationService calls GameLoop.resume() when the whistle blows
	end)
end

function GameLoop.resume()
	if state ~= "Station" then
		return
	end
	setState("Journey")
	targetSpeed = Config.Train.CruiseSpeed
	brake = nil
	Net.fireAll(Net.T.Stinger, { name = "Whistle" })
end

----------------------------------------------------------------
-- Car build window
----------------------------------------------------------------
local function carWindowStep()
	local minCar, maxCar = math.huge, 1
	local anyRider = false
	for _, player in ipairs(Players:GetPlayers()) do
		if not player:GetAttribute("Ghost") then
			local car = player:GetAttribute("CarIndex") or 0
			if car >= 1 then
				anyRider = true
				minCar = math.min(minCar, car)
				maxCar = math.max(maxCar, car)
			end
		end
	end
	if not anyRider then
		minCar = 1
		maxCar = 1
	end

	local buildTo = math.min(maxCar + Config.Train.BuildAhead, Config.Train.Cars)
	for i = ctx.TrainBuilder.rearMostBuilt(), buildTo do
		if not ctx.TrainBuilder.isBuilt(i) then
			ctx.TrainBuilder.buildCar(i)
		end
	end
	workspace:SetAttribute("FrontCar", buildTo)

	if state == "Journey" or state == "Finale" then
		local dropBelow = minCar - Config.Train.KeepBehind
		ctx.TrainBuilder.unbuildBefore(dropBelow)
	end
end

----------------------------------------------------------------
-- Heartbeat
----------------------------------------------------------------
local function heartbeat(dt)
	-- Motion
	local accel = Config.Train.CruiseSpeed / Config.Train.AccelSeconds
	if brake then
		local stretch = math.max(brake.stopD - brake.startD, 1)
		local remaining = brake.stopD - distance
		if remaining <= 1 then
			speed = 0
			local station = approachingStation
			brake = nil
			targetSpeed = 0
			if station then
				arriveStation(station)
			end
		else
			local t = math.clamp(remaining / stretch, 0, 1)
			speed = math.max(brake.startSpeed * (t ^ 0.7), 2)
		end
	elseif speed < targetSpeed then
		speed = math.min(speed + accel * dt, targetSpeed)
	elseif speed > targetSpeed then
		speed = math.max(speed - accel * dt, targetSpeed)
	end
	distance += speed * dt

	sinceAttr += dt
	sinceDistAttr += dt
	if sinceAttr >= ATTR_UPDATE then
		sinceAttr = 0
		workspace:SetAttribute("TrainSpeed", speed)
	end
	if sinceDistAttr >= 0.5 then
		sinceDistAttr = 0
		workspace:SetAttribute("TrainDistance", distance)
	end
end

----------------------------------------------------------------
-- Wiring
----------------------------------------------------------------
function GameLoop.init(c)
	ctx = c
	ctx.GameLoopRef = GameLoop

	-- the caboose brake wheel: skip the countdown and go
	local CollectionService = game:GetService("CollectionService")
	local function wireLever(lever)
		local prompt = lever:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				if state == "Lobby" and not player:GetAttribute("Ghost")
					and (player:GetAttribute("CarIndex") or 0) >= 1 then
					depart()
				end
			end)
		end
	end
	CollectionService:GetInstanceAddedSignal(Tags.BoardLever):Connect(wireLever)
	for _, lever in ipairs(CollectionService:GetTagged(Tags.BoardLever)) do
		wireLever(lever)
	end

	ctx.signals.carEntered:connect(function(player, carIndex)
		if player:GetAttribute("Ghost") then
			return
		end
		-- Station triggers
		if state == "Journey" and not approachingStation then
			for k, stationCar in ipairs(Config.Run.StationCars) do
				if carIndex == stationCar and not stationsDone[k] then
					stationsDone[k] = true
					beginApproach(k)
				end
			end
		end
		-- Finale trigger
		if carIndex >= Config.Train.Cars and not finaleStarted and (state == "Journey" or state == "Station") then
			finaleStarted = true
			setState("Finale")
			ctx.Entities.Engineer.startFinale()
		end
	end)

	ctx.signals.runStateChanged:connect(function(next)
		if next == "Lobby" then
			if boardingThread then
				pcall(task.cancel, boardingThread)
			end
			boardingThread = task.spawn(boardingWatch)
		end
	end)
end

function GameLoop.start()
	RunService.Heartbeat:Connect(heartbeat)

	task.spawn(function()
		while true do
			task.wait(0.7)
			carWindowStep()
		end
	end)

	-- Defeat watch: a run with riders that ends up all ghosts is over.
	task.spawn(function()
		while true do
			task.wait(2)
			if state == "Journey" or state == "Finale" or state == "Station" then
				local riders = 0
				for _, player in ipairs(Players:GetPlayers()) do
					if not player:GetAttribute("Ghost") then
						riders += 1
					end
				end
				if riders == 0 and #Players:GetPlayers() > 0 then
					GameLoop.defeat("Every rider joined the manifest.")
				end
			end
		end
	end)

	startRun()
end

return GameLoop
