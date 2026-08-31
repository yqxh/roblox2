--[[
	Timetable.luau
	The director. The 11:59 runs on a schedule — Furnace passes, ticket
	inspections, tunnels, gorges — bent by mercy (grace after a mauling)
	and spite (linger anywhere too long and something is sent to fetch you).
	Holders of the Conductor's Watch get to read a little of it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local RunPlan = require(Shared.RunPlan)
local Util = require(Shared.Util)

local Timetable = {}
local ctx

local running = false
local threads = {}

local nextFurnaceAt = 0
local lastFurnaceAt = 0
local inspectorDone = {}
local parallelCooldownUntil = 0
local currentFeature = nil
local firedBeams = {}
local maxCarSeen = 1

local E = Config.Entities
local TT = Config.Timetable

function Timetable.init(c)
	ctx = c
	ctx.lastGroupDamage = 0
end

----------------------------------------------------------------
-- Conditions
----------------------------------------------------------------
local function graceHolds()
	return os.clock() - (ctx.lastGroupDamage or 0) < TT.GraceAfterDamageSeconds
end

local function journeyActive()
	local state = ctx.GameLoop.state()
	return running and (state == "Journey" or state == "Finale")
end

local function canFurnace()
	return journeyActive()
		and ctx.GameLoop.state() ~= "Finale"
		and ctx.GameLoop.isMoving()
		and not ctx.Entities.Furnace.isActive()
		and not ctx.Entities.Inspector.isActive()
		and not graceHolds()
		and maxCarSeen >= TT.FirstEventCar
end

local function scheduleFurnace(delayOverride)
	local rng = ctx.rng
	local gap = delayOverride or rng:NextNumber(E.Furnace.MinGapSeconds, E.Furnace.MaxGapSeconds)
	nextFurnaceAt = os.clock() + gap
end

function Timetable.forceFurnace(delay)
	nextFurnaceAt = math.min(nextFurnaceAt, os.clock() + (delay or 2))
end

----------------------------------------------------------------
-- Features (tunnels / gorges) follow the distance line
----------------------------------------------------------------
local function featureStep()
	-- judge features from where the riders actually are, not the caboose
	local _, maxOccupied = ctx.EntityUtil.occupiedRange()
	local offset = ((maxOccupied or 1) - 0.5) * Config.Train.CarPitch
	local d = ctx.GameLoop.distance() + offset
	local feature = RunPlan.featureAt(ctx.runSeed, d)

	local currentKey = currentFeature and (currentFeature.kind .. currentFeature.index) or nil
	local newKey = feature and (feature.kind .. feature.index) or nil
	if currentKey == newKey then
		-- still inside (or still outside)
		if feature and feature.kind == "gorge" then
			-- beam checks
			local speed = ctx.GameLoop.speed()
			for _, beamD in ipairs(RunPlan.beamsFor(feature)) do
				local id = feature.index .. ":" .. math.floor(beamD)
				if not firedBeams[id] then
					local eta = (beamD - d) / math.max(speed, 1)
					if eta <= 3 and eta > 0 then
						firedBeams[id] = "warned"
						Net.fireAll(Net.T.BeamWarn, { eta = eta })
					end
				elseif firedBeams[id] == "warned" and d >= beamD then
					firedBeams[id] = "done"
					-- anyone standing tall on the roof meets the ironwork
					for _, player in ipairs(Players:GetPlayers()) do
						if not player:GetAttribute("Ghost") then
							local char, _, root = Util.aliveCharacter(player)
							if char and ctx.TrainBuilder.isOnRoof(root.Position)
								and player:GetAttribute("Stance") ~= "crouch" then
								ctx.PlayerService.damage(player, 45, "beam")
								Net.fireClient(player, Net.T.Subtitle, { text = "The bridge does not duck.", seconds = 3 })
							end
						end
					end
				end
			end
		end
		return
	end

	-- leaving one
	if currentFeature then
		if currentFeature.kind == "tunnel" then
			Net.fireAll(Net.T.TunnelState, { active = false })
			ctx.Entities.Gloom.stop()
		end
		currentFeature = nil
	end
	-- entering one
	if feature then
		currentFeature = feature
		if feature.kind == "tunnel" then
			Net.fireAll(Net.T.TunnelState, { active = true, gloom = feature.gloomy == true })
			Net.fireAll(Net.T.Stinger, { name = "TunnelIn" })
			if feature.gloomy then
				ctx.Entities.Gloom.start(feature)
				Net.fireAll(Net.T.Subtitle, { text = "Darkness swallows the line. Douse your lights.", seconds = 5 })
			else
				Net.fireAll(Net.T.Subtitle, { text = "A tunnel. Hold your nerve.", seconds = 4 })
			end
		elseif feature.kind == "gorge" then
			Net.fireAll(Net.T.Subtitle, { text = "The gorge. If you ride the roof, ride it low.", seconds = 5 })
		end
	end
end

----------------------------------------------------------------
-- The pocketwatch page
----------------------------------------------------------------
local function nextEntries()
	local entries = {}
	local now = os.clock()
	local d = ctx.GameLoop.distance()
	local speed = math.max(ctx.GameLoop.speed(), 1)

	if ctx.Entities.Furnace.isActive() then
		table.insert(entries, { label = "THE FURNACE", eta = 0 })
	elseif nextFurnaceAt > now and canFurnace() ~= false then
		table.insert(entries, { label = "The Furnace", eta = math.floor(nextFurnaceAt - now) })
	end

	local dOffset = (maxCarSeen - 0.5) * Config.Train.CarPitch
	d += dOffset
	for _, feature in ipairs(RunPlan.featuresBetween(ctx.runSeed, d, d + 2600)) do
		if feature.startD > d then
			local label = feature.kind == "tunnel"
				and (feature.gloomy and "Dark tunnel — something inside" or "Tunnel")
				or "The gorge (mind the roof)"
			table.insert(entries, { label = label, eta = math.floor((feature.startD - d) / speed) })
		end
	end

	for k, car in ipairs(Config.Run.InspectorCars) do
		if not inspectorDone[k] and car > maxCarSeen then
			table.insert(entries, { label = ("Inspection waits at CAR %02d"):format(car) })
			break
		end
	end
	for _, car in ipairs(Config.Run.StationCars) do
		if car > maxCarSeen then
			table.insert(entries, { label = ("Next stop at CAR %02d"):format(car) })
			break
		end
	end

	table.sort(entries, function(a, b)
		return (a.eta or 9999) < (b.eta or 9999)
	end)
	local trimmed = {}
	for i = 1, math.min(3, #entries) do
		table.insert(trimmed, entries[i])
	end
	return trimmed
end

----------------------------------------------------------------
-- Main loops
----------------------------------------------------------------
local function directorLoop()
	while running do
		task.wait(0.25)
		if not journeyActive() then
			continue
		end
		featureStep()

		-- Furnace scheduling
		if os.clock() >= nextFurnaceAt then
			if canFurnace() then
				lastFurnaceAt = os.clock()
				task.spawn(function()
					ctx.Entities.Furnace.run()
					scheduleFurnace()
				end)
				nextFurnaceAt = math.huge -- Furnace.run reschedules via closure above
			else
				nextFurnaceAt = os.clock() + 6 -- try again shortly
			end
		end
	end
end

local function campLoop()
	while running do
		task.wait(5)
		if not journeyActive() or ctx.GameLoop.state() == "Finale" then
			continue
		end
		for _, player in ipairs(Players:GetPlayers()) do
			if not player:GetAttribute("Ghost") and ctx.PlayerService.dwellOf(player) > E.Furnace.CampSeconds then
				if not ctx.Entities.Furnace.isActive() and os.clock() - lastFurnaceAt > 40 then
					Net.fireClient(player, Net.T.Subtitle, { text = "You have lingered. The line notices lingering.", seconds = 4 })
					Timetable.forceFurnace(4)
				end
				ctx.PlayerService.resetDwell(player)
			end
		end
	end
end

local function watchLoop()
	while running do
		task.wait(1)
		local holders = ctx.ItemService.watchHolderList()
		if #holders > 0 then
			local entries = nextEntries()
			for _, player in ipairs(holders) do
				Net.fireClient(player, Net.T.TimetableNext, { entries = entries })
			end
		end
	end
end

----------------------------------------------------------------
-- Car-entry triggers
----------------------------------------------------------------
local function currentFeatureIsTunnel()
	return currentFeature ~= nil and currentFeature.kind == "tunnel"
end

local function onCarEntered(player, carIndex)
	if not running or player:GetAttribute("Ghost") then
		return
	end
	maxCarSeen = math.max(maxCarSeen, carIndex)

	-- inspections
	for k, car in ipairs(Config.Run.InspectorCars) do
		if carIndex == car and not inspectorDone[k] then
			inspectorDone[k] = true
			task.spawn(ctx.Entities.Inspector.start, k)
		end
	end

	-- the sleeper's car
	if ctx.plan and carIndex == ctx.plan.sleeperCar then
		ctx.Entities.Sleeper.activate(carIndex)
	end

	-- the parallel walker at the windows
	local plan = ctx.plan and ctx.plan.cars[carIndex]
	if plan then
		if plan.archetype == "redcar" then
			ctx.Entities.Parallel.start(carIndex, true)
		elseif carIndex == maxCarSeen and carIndex >= TT.FirstEventCar
			and os.clock() > parallelCooldownUntil
			and plan.archetype ~= "tender"
			and ctx.GameLoop.isMoving()
			and not currentFeatureIsTunnel() then
			if ctx.rng:NextNumber() < E.Parallel.CarChance then
				parallelCooldownUntil = os.clock() + E.Parallel.CooldownSeconds
				ctx.Entities.Parallel.start(carIndex, false)
			end
		end
	end
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------
function Timetable.startRun()
	running = true
	inspectorDone = {}
	firedBeams = {}
	currentFeature = nil
	parallelCooldownUntil = 0
	maxCarSeen = 1
	lastFurnaceAt = os.clock()
	scheduleFurnace(ctx.rng:NextNumber(50, 80)) -- first pass comes gently late
	table.insert(threads, task.spawn(directorLoop))
	table.insert(threads, task.spawn(campLoop))
	table.insert(threads, task.spawn(watchLoop))
end

function Timetable.stopRun()
	running = false
	for _, thread in ipairs(threads) do
		pcall(task.cancel, thread)
	end
	threads = {}
	for _, entity in pairs(ctx.Entities) do
		if entity.stop then
			pcall(entity.stop)
		end
	end
end

function Timetable.start()
	ctx.signals.carEntered:connect(onCarEntered)
end

return Timetable
