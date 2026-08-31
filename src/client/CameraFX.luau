--[[
	CameraFX.luau
	The train in your spine: constant rumble scaled by speed, paired
	rail-joint jolts, sprint FOV, damage kicks, the Furnace's rising
	quake, and the Engineer-sized thumps. Everything respects the
	reduce-motion setting.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local ClientState = require(script.Parent:WaitForChild("ClientState"))

local CameraFX = {}

local trauma = 0          -- 0..1 decaying shake energy
local furnaceRampUntil = 0
local baseFOV = 70

local function addTrauma(amount)
	trauma = math.clamp(trauma + amount, 0, 1)
end

CameraFX.addTrauma = addTrauma

local function motionScale()
	return ClientState.settings.reduceMotion and 0.25 or 1
end

function CameraFX.start()
	local camera = workspace.CurrentCamera
	camera.FieldOfView = baseFOV

	RunService:BindToRenderStep("T59CameraFX", Enum.RenderPriority.Camera.Value + 10, function(dt)
		camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local now = os.clock()
		local scale = motionScale()

		-- rumble floor from speed
		local speedFrac = math.clamp(ClientState.speed / 38, 0, 1.4)
		local rumble = 0.014 * speedFrac
		if ClientState.exposed then
			rumble *= 1.9
		end
		if ClientState.hidden then
			rumble *= 0.4
		end

		-- furnace approach ramps the floor up
		if now < furnaceRampUntil then
			local remain = furnaceRampUntil - now
			rumble += 0.05 * math.clamp(1 - remain / 6, 0, 1)
		end

		trauma = math.max(trauma - dt * 1.4, 0)
		local shake = trauma * trauma * 0.45

		local amp = (rumble + shake) * scale
		if amp > 0.0004 then
			local t = now * 19
			local offset = CFrame.new(
				math.noise(t, 1.7) * amp * 2.4,
				math.noise(t, 9.1) * amp * 3.2,
				0
			) * CFrame.Angles(
				math.noise(t, 4.3) * amp * 0.9,
				math.noise(t, 6.2) * amp * 0.7,
				math.noise(t, 12.8) * amp * 1.6
			)
			camera.CFrame = camera.CFrame * offset
		end
	end)

	-- FOV: sprint stretch
	task.spawn(function()
		while true do
			task.wait(0.1)
			local target = baseFOV
			if ClientState.sprinting then
				target = baseFOV + 6
			elseif ClientState.hidden then
				target = baseFOV - 6
			end
			local cam = workspace.CurrentCamera
			if cam and math.abs(cam.FieldOfView - target) > 0.5 then
				TweenService:Create(cam, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { FieldOfView = target }):Play()
			end
		end
	end)

	Net.on(Net.T.Damage, function(data)
		addTrauma(math.clamp((data.amount or 10) / 70, 0.25, 0.9))
	end)
	Net.on(Net.T.FurnaceWarn, function(data)
		furnaceRampUntil = os.clock() + (data.eta or 6)
	end)
	Net.on(Net.T.FurnacePass, function(data)
		local away = math.abs((data.car or 0) - ClientState.carIndex)
		if away <= 2 then
			addTrauma(0.7 - away * 0.2)
		end
	end)
	Net.on(Net.T.BeamWarn, function(data)
		task.delay(data.eta or 3, function()
			addTrauma(ClientState.onRoof and 0.5 or 0.2)
		end)
	end)
	Net.on(Net.T.SleeperStage, function(data)
		if data.stage == "wake" then
			addTrauma(0.85)
		end
	end)
	Net.on(Net.T.ParallelBreak, function(data)
		if data.car == ClientState.carIndex then
			addTrauma(0.6)
		end
	end)
end

return CameraFX
