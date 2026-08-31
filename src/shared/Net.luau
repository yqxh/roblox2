--[[
	Net.luau
	One RemoteEvent + one RemoteFunction with string topics.
	Server: Net.server() once at boot, then Net.on / Net.fireClient / Net.fireAll.
	Client: Net.client() once at boot, then Net.on / Net.fire / Net.invoke.

	Every topic used anywhere lives in Net.T so typos die at the require site.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

Net.T = {
	-- server -> client
	RunState = "RunState",           -- {state, seed?}
	Subtitle = "Subtitle",           -- {text, seconds?, voice?}
	Announce = "Announce",           -- {title, sub?, seconds?, tone?}
	Toast = "Toast",                 -- {text, tone?}
	Damage = "Damage",               -- {amount, cause}
	FurnaceWarn = "FurnaceWarn",     -- {eta}
	FurnacePass = "FurnacePass",     -- {car} (lamps burst in this car)
	LampsSet = "LampsSet",           -- {car, lit}
	TunnelState = "TunnelState",     -- {active, gloom?}
	ParallelSpawn = "ParallelSpawn", -- {car, side, duration, seed}
	ParallelBreak = "ParallelBreak", -- {car, side} (window smash fx)
	InspectorState = "InspectorState", -- {phase} warn|walk|done
	SleeperStage = "SleeperStage",   -- {stage, level}
	StationState = "StationState",   -- {phase, seconds?, name?}
	BoardingState = "BoardingState", -- {phase, seconds?}
	GustSchedule = "GustSchedule",   -- {period, strength}
	BeamWarn = "BeamWarn",           -- {eta} roof beam approaching (gorge)
	Ping = "Ping",                   -- {pos, name, ghost}
	TimetableNext = "TimetableNext", -- {label, eta} for pocketwatch holders
	VictoryCine = "VictoryCine",     -- {}
	DefeatCine = "DefeatCine",       -- {}
	ShopResult = "ShopResult",       -- {ok, item?, reason?}
	HideState = "HideState",         -- {hidden, spotId?}
	ItemState = "ItemState",         -- {slot="Flashlight", on=bool, fuel=number}
	CarEntered = "CarEntered",       -- {car, label, archetype}
	Heartbeat = "HeartbeatCue",      -- {rate} client heartbeat audio hint
	Stinger = "Stinger",             -- {name} one-shot audio/visual cue

	-- client -> server
	SetStance = "SetStance",         -- {stance="stand"|"crouch"}
	SendPing = "SendPing",           -- {pos}
	GazeReport = "GazeReport",       -- {car, side, seconds}
	ExitHide = "ExitHide",           -- {}
	ToolAction = "ToolAction",       -- {tool, action, data?}
	Buy = "Buy",                     -- {item, machineId}
	BoardLever = "BoardLever",       -- {}
	ReadyForPlan = "ReadyForPlan",   -- {} ask for seed replay after join
}

local REMOTE_NAME = "T59_Net"
local RFUNC_NAME = "T59_NetRF"

local handlers = {}
local remote = nil
local rfunc = nil

local function dispatch(topic, ...)
	local fns = handlers[topic]
	if fns then
		for _, fn in ipairs(fns) do
			task.spawn(fn, ...)
		end
	end
end

function Net.on(topic, fn)
	local list = handlers[topic]
	if not list then
		list = {}
		handlers[topic] = list
	end
	table.insert(list, fn)
end

----------------------------------------------------------------
-- Server side
----------------------------------------------------------------
function Net.server()
	assert(RunService:IsServer(), "Net.server() on client")
	remote = Instance.new("RemoteEvent")
	remote.Name = REMOTE_NAME
	remote.Parent = ReplicatedStorage
	rfunc = Instance.new("RemoteFunction")
	rfunc.Name = RFUNC_NAME
	rfunc.Parent = ReplicatedStorage

	-- Simple per-player, per-topic rate limiting.
	local buckets = {}
	local LIMITS = {
		[Net.T.GazeReport] = 20,
		[Net.T.SetStance] = 10,
		[Net.T.SendPing] = 2,
		[Net.T.ToolAction] = 12,
		[Net.T.Buy] = 4,
	}
	task.spawn(function()
		while true do
			task.wait(1)
			table.clear(buckets)
		end
	end)

	remote.OnServerEvent:Connect(function(player, topic, data)
		if type(topic) ~= "string" then
			return
		end
		local key = player.UserId .. topic
		local used = (buckets[key] or 0) + 1
		buckets[key] = used
		if used > (LIMITS[topic] or 8) then
			return
		end
		dispatch(topic, player, data)
	end)
end

function Net.bindInvoke(fn)
	assert(rfunc, "Net.server() first")
	rfunc.OnServerInvoke = fn
end

function Net.fireClient(player, topic, data)
	remote:FireClient(player, topic, data)
end

function Net.fireAll(topic, data)
	remote:FireAllClients(topic, data)
end

function Net.fireList(players, topic, data)
	for _, player in ipairs(players) do
		remote:FireClient(player, topic, data)
	end
end

----------------------------------------------------------------
-- Client side
----------------------------------------------------------------
function Net.client()
	assert(RunService:IsClient(), "Net.client() on server")
	remote = ReplicatedStorage:WaitForChild(REMOTE_NAME)
	rfunc = ReplicatedStorage:WaitForChild(RFUNC_NAME)
	remote.OnClientEvent:Connect(function(topic, data)
		dispatch(topic, data)
	end)
end

function Net.fire(topic, data)
	remote:FireServer(topic, data)
end

function Net.invoke(topic, data)
	return rfunc:InvokeServer(topic, data)
end

return Net
