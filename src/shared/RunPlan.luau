--[[
	RunPlan.luau
	Everything random about a run derives from one seed, through pure
	functions, so the server (gameplay) and every client (scenery) agree
	on the same night without shipping the world over the wire.

	Distances are studs of track travelled since departure.
]]

local Config = require(script.Parent.Config)
local Util = require(script.Parent.Util)

local RunPlan = {}

local WINDOW = 3200 -- one possible feature (tunnel/gorge) per window

RunPlan.WINDOW = WINDOW

local STATION_NAMES = {
	"WICK HOLLOW", "MOURNBROOK", "LOWER EAVES", "CANDLE JUNCTION",
	"HARROW FEN", "PALE SIDING", "VESPER MILL", "COLDWATER",
}

local ARCHETYPE_WEIGHTS = {
	{ weight = 30, value = "coach" },
	{ weight = 18, value = "sleeper" },
	{ weight = 14, value = "diner" },
	{ weight = 11, value = "lounge" },
	{ weight = 16, value = "freight" },
	{ weight = 8, value = "mail" },
}

----------------------------------------------------------------
-- Car plan
----------------------------------------------------------------
function RunPlan.build(seed)
	local rng = Random.new(seed)
	local run = Config.Run
	local plan = {
		seed = seed,
		cars = {},
		stationNames = {},
		sleeperCar = rng:NextInteger(run.SleeperCarRange[1], run.SleeperCarRange[2]),
		redCar = rng:NextInteger(run.RedCarRange[1], run.RedCarRange[2]),
	}

	-- Station names, no repeats
	local pool = table.clone(STATION_NAMES)
	for _ = 1, #run.StationCars do
		local i = rng:NextInteger(1, #pool)
		table.insert(plan.stationNames, pool[i])
		table.remove(pool, i)
	end

	local flatSet = {}
	for _, c in ipairs(run.FlatcarCars) do
		flatSet[c] = true
	end
	local stationSet = {}
	for _, c in ipairs(run.StationCars) do
		stationSet[c] = true
	end

	for i = 1, Config.Train.Cars do
		local archetype
		if i == 1 then
			archetype = "caboose"
		elseif i == Config.Train.Cars then
			archetype = "tender"
		elseif i == plan.sleeperCar then
			archetype = "sleeperboss"
		elseif i == plan.redCar then
			archetype = "redcar"
		elseif flatSet[i] then
			archetype = "flatcar"
		elseif i <= 3 then
			archetype = "coach"
		else
			archetype = Util.weightedPick(rng, ARCHETYPE_WEIGHTS)
		end

		-- Front door of car i = the door leading onward into car i+1.
		local doorState = "free"
		if i >= 5 and i < Config.Train.Cars - 1 and not stationSet[i + 1] and archetype ~= "redcar" then
			local roll = rng:NextNumber()
			if roll < 0.2 then
				doorState = "jammed"
			end
		end

		plan.cars[i] = {
			index = i,
			archetype = archetype,
			doorState = doorState,
			paint = rng:NextNumber() < 0.28 and "oxblood" or "green",
			variant = rng:NextInteger(1, 1e6), -- interior detail seed
		}
	end

	-- Exactly two locked doors per run, keys guaranteed one/two cars earlier.
	local lockable = {}
	for i = 8, Config.Train.Cars - 3 do
		local car = plan.cars[i]
		if car.doorState == "free" and car.archetype ~= "redcar"
			and not stationSet[i + 1] and not stationSet[i] then
			table.insert(lockable, i)
		end
	end
	local locked = 0
	while locked < 2 and #lockable > 0 do
		local pickIndex = rng:NextInteger(1, #lockable)
		local carIndex = lockable[pickIndex]
		table.remove(lockable, pickIndex)
		-- keep locked doors apart
		local nearOther = false
		for j = carIndex - 2, carIndex + 2 do
			if plan.cars[j] and plan.cars[j].doorState == "locked" then
				nearOther = true
			end
		end
		if not nearOther then
			plan.cars[carIndex].doorState = "locked"
			-- key spawns in this car or the one before
			plan.cars[carIndex].keyCar = carIndex - rng:NextInteger(0, 1)
			locked += 1
		end
	end

	return plan
end

----------------------------------------------------------------
-- Track features: tunnels and gorge trestles, one possible per window
----------------------------------------------------------------
local function windowFeature(seed, w)
	if w < 2 then
		return nil -- open country while everyone learns to walk
	end
	local rng = Random.new(seed * 31 + w * 7919)
	local roll = rng:NextNumber()
	local kind = nil
	if roll < 0.42 then
		kind = "tunnel"
	elseif roll < 0.68 then
		kind = "gorge"
	else
		return nil
	end

	local lead = rng:NextNumber(400, 900)
	local length
	if kind == "tunnel" then
		length = rng:NextNumber(Config.Timetable.TunnelMinLength, Config.Timetable.TunnelMaxLength)
	else
		length = Config.Timetable.GorgeLength * rng:NextNumber(0.8, 1.1)
	end
	length = math.min(length, WINDOW - lead - 300)

	local startD = w * WINDOW + lead
	return {
		kind = kind,
		index = w,
		startD = startD,
		endD = startD + length,
		gloomy = rng:NextNumber() < 0.65, -- tunnels only: does something live in it
	}
end

-- The feature covering distance d, if any.
function RunPlan.featureAt(seed, d)
	local w = math.floor(d / WINDOW)
	local feature = windowFeature(seed, w)
	if feature and d >= feature.startD and d <= feature.endD then
		return feature
	end
	return nil
end

-- All features intersecting [d0, d1].
function RunPlan.featuresBetween(seed, d0, d1)
	local out = {}
	for w = math.floor(d0 / WINDOW), math.floor(d1 / WINDOW) do
		local feature = windowFeature(seed, w)
		if feature and feature.endD >= d0 and feature.startD <= d1 then
			table.insert(out, feature)
		end
	end
	return out
end

-- Nearest distance >= from where [d, d+span] holds no feature (for stations).
function RunPlan.clearStretchAfter(seed, from, span)
	local d = from
	for _ = 1, 12 do
		local blocking = nil
		for _, feature in ipairs(RunPlan.featuresBetween(seed, d - 150, d + span)) do
			blocking = feature
		end
		if not blocking then
			return d
		end
		d = blocking.endD + 200
	end
	return d
end

-- Low beams over the roof while crossing a gorge.
function RunPlan.beamsFor(feature)
	local beams = {}
	local spacing = Config.Timetable.BeamSpacing
	local d = feature.startD + spacing * 0.6
	while d < feature.endD - 100 do
		table.insert(beams, d)
		d += spacing
	end
	return beams
end

----------------------------------------------------------------
-- Biomes (visual bands; gorges/tunnels override visuals while active)
----------------------------------------------------------------
local BIOME_WEIGHTS = {
	{ weight = 4, value = "pine" },
	{ weight = 2, value = "marsh" },
	{ weight = 3, value = "fields" },
	{ weight = 1.5, value = "yard" },
}

function RunPlan.biomeAt(seed, d)
	local bandLength = Config.Scenery.BiomeBandLength
	local b = math.floor(d / bandLength)
	if b <= 1 then
		return "pine", b
	end
	local rng = Random.new(seed * 13 + b * 104729)
	return Util.weightedPick(rng, BIOME_WEIGHTS), b
end

return RunPlan
