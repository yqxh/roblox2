--[[
	AudioController.luau
	The mix: wheel rhythm under everything, wind that rises on the roof,
	a low drone, distant moans of the engine, tunnel muffling, the
	heartbeat when you are hurt or hiding from something close.
	All sourced from engine-shipped audio bent via SoundBank.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local SoundBank = require(Shared.SoundBank)
local ClientState = require(script.Parent:WaitForChild("ClientState"))

local AudioController = {}

local groups = {}
local loops = {}
local eq = nil

local function makeGroups()
	for _, name in ipairs({ "Ambience", "SFX", "UI" }) do
		local group = Instance.new("SoundGroup")
		group.Name = "T59_" .. name
		group.Volume = 1
		group.Parent = SoundService
		groups[name] = group
	end
	eq = Instance.new("EqualizerSoundEffect")
	eq.HighGain = 0
	eq.MidGain = 0
	eq.LowGain = 0
	eq.Parent = groups.Ambience
end

----------------------------------------------------------------
-- Beds
----------------------------------------------------------------
local function startBeds()
	-- rolling rumble: footstep loop pitched into the floor
	loops.rumble = SoundBank.loop("Steps", SoundService, {
		volume = 0, pitch = 0.3, group = groups.Ambience,
	})
	-- wind: the falling loop stretched thin
	loops.wind = SoundBank.loop("Falling", SoundService, {
		volume = 0, pitch = 0.42, group = groups.Ambience,
	})
	-- deep drone: a moan slowed to weather
	loops.drone = SoundBank.loop("Moan", SoundService, {
		volume = 0.05, pitch = 0.24, group = groups.Ambience,
	})

	task.spawn(function()
		while true do
			task.wait(0.25)
			local speedFrac = math.clamp(ClientState.speed / 38, 0, 1.2)
			local ambVol = ClientState.settings.ambienceVolume
			loops.rumble.Volume = 0.22 * speedFrac * ambVol
			local windTarget = 0.05 + (ClientState.exposed and 0.3 or 0.04) * speedFrac
			if ClientState.inTunnel then
				windTarget *= 0.4
			end
			loops.wind.Volume = windTarget * ambVol
			loops.wind.PlaybackSpeed = 0.38 + speedFrac * 0.14 + (ClientState.exposed and 0.06 or 0)
			loops.drone.Volume = (ClientState.inTunnel and 0.11 or 0.05) * ambVol
		end
	end)
end

-- clickety-clack pairs, spaced by speed
local function startWheelRhythm()
	task.spawn(function()
		local flip = false
		while true do
			local speed = ClientState.speed
			if speed < 4 then
				task.wait(0.4)
				continue
			end
			local period = math.clamp(42 / speed, 0.55, 3)
			flip = not flip
			SoundBank.play(flip and "Clack" or "Clack2", nil, {
				volumeScale = math.clamp(speed / 38, 0.3, 1) * 0.85 * ClientState.settings.ambienceVolume
					* (ClientState.hidden and 0.5 or 1),
				group = groups.Ambience,
				jitter = 0.06,
			})
			task.wait(period)
		end
	end)
end

-- the engine moans somewhere ahead, now and then — even at the platform
local function startDistantMoans()
	task.spawn(function()
		while true do
			task.wait(math.random(70, 160))
			if not ClientState.inTunnel then
				local moving = ClientState.speed > 10
				if moving or ClientState.runState == "Lobby" then
					SoundBank.play("WhistleFar", nil, {
						volumeScale = (moving and 0.5 or 0.3) * ClientState.settings.ambienceVolume,
						group = groups.Ambience,
					})
				end
			end
		end
	end)
end

----------------------------------------------------------------
-- Heartbeat
----------------------------------------------------------------
local heartbeatRate = 0 -- beats per second; 0 = quiet
local function startHeartbeat()
	task.spawn(function()
		while true do
			local hum = ClientState.localHumanoid()
			local frac = hum and hum.Health / math.max(hum.MaxHealth, 1) or 1
			local target = 0
			if ClientState.isDowned() then
				target = 1.5
			elseif frac < 0.35 then
				target = 1.1
			elseif ClientState.hidden then
				target = 0.8
			end
			heartbeatRate = target
			if heartbeatRate > 0 then
				SoundBank.play("HeartThump", nil, {
					volumeScale = 0.7,
					group = groups.SFX,
				})
				task.wait(1 / heartbeatRate)
			else
				task.wait(0.5)
			end
		end
	end)
end

----------------------------------------------------------------
-- Muffling
----------------------------------------------------------------
local function refreshMuffle()
	local muffled = ClientState.hidden
	eq.HighGain = muffled and -18 or (ClientState.inTunnel and -6 or 0)
	eq.MidGain = muffled and -6 or 0
end

----------------------------------------------------------------
-- Start
----------------------------------------------------------------
function AudioController.start()
	makeGroups()
	startBeds()
	startWheelRhythm()
	startDistantMoans()
	startHeartbeat()

	ClientState.signals.hiddenChanged:connect(refreshMuffle)
	ClientState.signals.tunnelChanged:connect(function(active)
		refreshMuffle()
		if active then
			SoundBank.play("TunnelIn", nil, { group = groups.Ambience, volumeScale = 0.8 })
		end
	end)

	Net.on(Net.T.Stinger, function(data)
		if type(data) == "table" and type(data.name) == "string" and SoundBank.Cues[data.name] then
			SoundBank.play(data.name, nil, { group = groups.SFX })
		end
	end)

	-- UI ticks are fired directly from UIKit via SoundBank; expose groups
	AudioController.groups = groups
end

return AudioController
