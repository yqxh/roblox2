--[[
	ClientState.luau
	One place for everything the client controllers share: the locally
	integrated train motion (smooth at any replication rate), run state,
	where I am, what's happening, and player settings.
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Util = require(Shared.Util)
local RunPlan = require(Shared.RunPlan)

local State = {
	distance = 0,
	speed = 0,
	runState = "Lobby",
	carIndex = 0,
	archetype = "coach",
	inTunnel = false,
	tunnelGloom = false,
	hidden = false,
	hiddenLow = false,
	stance = "stand",
	sprinting = false,
	stamina = 1,
	onRoof = false,
	exposed = false, -- roof or flatcar: weather hits you
	settings = {
		reduceMotion = false,
		subtitles = true,
		ambienceVolume = 1,
		uiVolume = 1,
	},
	signals = {
		runStateChanged = Util.Signal.new(),
		carChanged = Util.Signal.new(),
		tunnelChanged = Util.Signal.new(),
		hiddenChanged = Util.Signal.new(),
		exposedChanged = Util.Signal.new(),
	},
}

local player = Players.LocalPlayer

function State.localRoot()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

function State.localHumanoid()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

function State.isGhost()
	return player:GetAttribute("Ghost") == true
end

function State.isDowned()
	return player:GetAttribute("Downed") == true
end

function State.start()
	-- Motion integration: follow TrainSpeed, gently correct to TrainDistance
	State.speed = workspace:GetAttribute("TrainSpeed") or 0
	State.distance = workspace:GetAttribute("TrainDistance") or 0
	RunService.Heartbeat:Connect(function(dt)
		local targetSpeed = workspace:GetAttribute("TrainSpeed") or 0
		State.speed = Util.lerp(State.speed, targetSpeed, math.clamp(dt * 2.2, 0, 1))
		State.distance += State.speed * dt
		local serverDistance = workspace:GetAttribute("TrainDistance") or State.distance
		State.distance += (serverDistance - State.distance) * math.clamp(dt * 0.6, 0, 1)

		-- where am I
		local root = State.localRoot()
		if root then
			local pos = root.Position
			State.onRoof = pos.Y > 19.5
			local exposed = State.onRoof or (State.archetype == "flatcar" and State.carIndex > 0) or State.archetype == "tender"
			if exposed ~= State.exposed then
				State.exposed = exposed
				State.signals.exposedChanged:fire(exposed)
			end

			-- my own stretch of track: tunnels are positional, judged locally
			local seed = workspace:GetAttribute("RunSeed")
			if seed then
				local myTrack = State.distance + pos.X
				local feature = RunPlan.featureAt(seed, myTrack)
				local inTunnel = feature ~= nil and feature.kind == "tunnel"
				if inTunnel ~= State.inTunnel then
					State.inTunnel = inTunnel
					State.signals.tunnelChanged:fire(inTunnel, State.tunnelGloom)
				end
			end
		end
	end)

	Net.on(Net.T.RunState, function(data)
		State.runState = data.state
		State.signals.runStateChanged:fire(data.state)
	end)

	Net.on(Net.T.CarEntered, function(data)
		State.carIndex = data.car
		State.archetype = data.archetype
		State.signals.carChanged:fire(data.car, data.label, data.archetype)
	end)

	Net.on(Net.T.TunnelState, function(data)
		-- geometry timing is judged locally; the server only tells us
		-- whether something lives in this stretch of dark
		State.tunnelGloom = data.active == true and data.gloom == true
	end)

	Net.on(Net.T.HideState, function(data)
		State.hidden = data.hidden == true
		State.hiddenLow = data.low == true
		State.signals.hiddenChanged:fire(State.hidden)
	end)
end

return State
