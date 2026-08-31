--[[
	Main.server.luau
	Boot order for THE 11:59. Builds the service context, initializes
	everything in two phases (init: wire refs, start: begin work), then
	hands control to GameLoop.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Util = require(Shared.Util)
local Config = require(Shared.Config)

local Server = script.Parent

-- Manual character lifecycle: ghosts, lobby spawns, station revivals.
Players.CharacterAutoLoads = false

Net.server()

-- Collision groups: ghosts drift through the living and the hostile.
PhysicsService:RegisterCollisionGroup("Rider")
PhysicsService:RegisterCollisionGroup("Ghost")
PhysicsService:RegisterCollisionGroup("Entity")
PhysicsService:RegisterCollisionGroup("Door") -- doors stop the living, not the dead
PhysicsService:CollisionGroupSetCollidable("Ghost", "Rider", false)
PhysicsService:CollisionGroupSetCollidable("Ghost", "Entity", false)
PhysicsService:CollisionGroupSetCollidable("Ghost", "Ghost", false)
PhysicsService:CollisionGroupSetCollidable("Ghost", "Door", false)
PhysicsService:CollisionGroupSetCollidable("Entity", "Rider", false)
PhysicsService:CollisionGroupSetCollidable("Entity", "Entity", false)
PhysicsService:CollisionGroupSetCollidable("Entity", "Door", false)

local ctx = {}
ctx.net = Net
ctx.config = Config
ctx.util = Util
ctx.rng = Random.new()

local Workspace = workspace
local function folder(name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = Workspace
	return f
end

ctx.folders = {
	train = folder("Train"),
	entities = folder("Entities"),
	pickups = folder("Pickups"),
	station = folder("Station"),
	lobby = folder("Lobby"),
}

ctx.signals = {
	carEntered = Util.Signal.new(),      -- (player, carIndex, prevIndex)
	runStateChanged = Util.Signal.new(), -- (state)
	departed = Util.Signal.new(),        -- ()
	arrivedStation = Util.Signal.new(),  -- (stationNumber)
	leftStation = Util.Signal.new(),     -- (stationNumber)
	playerDamaged = Util.Signal.new(),   -- (player, amount, cause)
	playerDowned = Util.Signal.new(),    -- (player)
	playerGhosted = Util.Signal.new(),   -- (player, reason)
	noiseEvent = Util.Signal.new(),      -- (player, amount, position)
	furnaceCar = Util.Signal.new(),      -- (carIndex) as it thunders through
}

-- Services (order matters only for readability; init wires, start runs)
local moduleNames = {
	"PlayerService", "TrainBuilder", "CarPlans", "DoorSystem", "HideSystem",
	"LootSystem", "ItemService", "EconomyService", "StationService",
	"StatsService", "EntityUtil", "Timetable", "GameLoop",
}

for _, name in ipairs(moduleNames) do
	ctx[name] = require(Server:WaitForChild(name))
end

ctx.Entities = {}
local entitiesFolder = Server:WaitForChild("entities")
for _, name in ipairs({ "Furnace", "Inspector", "Gloom", "Parallel", "Stowaway", "Sleeper", "Engineer" }) do
	ctx.Entities[name] = require(entitiesFolder:WaitForChild(name))
end

-- Entities only get init(ctx): their `start` methods are gameplay triggers
-- (Inspector.start(visit), Gloom.start(feature)...), invoked by the Timetable.
for _, entity in pairs(ctx.Entities) do
	if entity.init then
		entity.init(ctx)
	end
end
for _, name in ipairs(moduleNames) do
	local service = ctx[name]
	if service.init then
		service.init(ctx)
	end
end
for _, name in ipairs(moduleNames) do
	local service = ctx[name]
	if service.start then
		service.start(ctx)
	end
end

print(("[%s] server up, v%s"):format(Config.GameName, Config.Version))
