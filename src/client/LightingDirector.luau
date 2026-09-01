--[[
	LightingDirector.luau
	The film grade. Roblox has no custom shader pipeline, so the look is
	built from everything it does expose, pushed hard: Future lighting
	(set in the place file), a tuned Atmosphere, layered ColorCorrection,
	Bloom, DepthOfField, dynamic Clouds, gaslight flicker, swinging lamp
	fixtures, tunnel blackouts with emergency strips, and a real dawn
	when you win.
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Tags = require(Shared.Tags)
local Palette = require(Shared.Palette)
local ClientState = require(script.Parent:WaitForChild("ClientState"))

local LightingDirector = {}

local atmosphere, bloom, gradeCC, pulseCC, dof, clouds

local BASE = {
	density = 0.34,
	offset = 0.28,
	atmoColor = Color3.fromRGB(24, 30, 52),
	decay = Color3.fromRGB(14, 16, 30),
	glare = 0.12,
	haze = 1.7,
	contrast = 0.07,
	saturation = -0.12,
	tint = Color3.fromRGB(216, 224, 248),
	brightness = 0.015,
}

local mode = "exterior" -- exterior | interior | tunnel | dawn | defeat

local function buildEffects()
	Lighting:ClearAllChildren()

	-- our moon hangs low over the valley; hide the sky's own, keep its stars
	local sky = Instance.new("Sky")
	sky.MoonAngularSize = 0
	sky.SunAngularSize = 13 -- the dawn payoff gets a real sun disc
	sky.StarCount = 4500
	sky.Parent = Lighting

	atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = BASE.density
	atmosphere.Offset = BASE.offset
	atmosphere.Color = BASE.atmoColor
	atmosphere.Decay = BASE.decay
	atmosphere.Glare = BASE.glare
	atmosphere.Haze = BASE.haze
	atmosphere.Parent = Lighting

	bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.38
	bloom.Size = 24
	bloom.Threshold = 1.08
	bloom.Parent = Lighting

	gradeCC = Instance.new("ColorCorrectionEffect")
	gradeCC.Name = "Grade"
	gradeCC.Contrast = BASE.contrast
	gradeCC.Saturation = BASE.saturation
	gradeCC.TintColor = BASE.tint
	gradeCC.Brightness = BASE.brightness
	gradeCC.Parent = Lighting

	pulseCC = Instance.new("ColorCorrectionEffect")
	pulseCC.Name = "Pulse"
	pulseCC.Parent = Lighting

	dof = Instance.new("DepthOfFieldEffect")
	dof.FarIntensity = 0.18
	dof.FocusDistance = 42
	dof.InFocusRadius = 34
	dof.NearIntensity = 0.32
	dof.Parent = Lighting

	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
		clouds.Cover = 0.68
		clouds.Density = 0.24
		clouds.Color = Color3.fromRGB(120, 128, 150)
		clouds.Parent = terrain
	end
end

----------------------------------------------------------------
-- Mode grades
----------------------------------------------------------------
local function tweenAtmo(props, seconds)
	TweenService:Create(atmosphere, TweenInfo.new(seconds or 1.2, Enum.EasingStyle.Sine), props):Play()
end

local function tweenGrade(props, seconds)
	TweenService:Create(gradeCC, TweenInfo.new(seconds or 1.2, Enum.EasingStyle.Sine), props):Play()
end

local function applyMode(next)
	if mode == next then
		return
	end
	local from = mode
	mode = next
	if next == "tunnel" then
		tweenAtmo({ Density = 0.58, Color = Color3.fromRGB(8, 8, 12), Decay = Color3.fromRGB(4, 4, 8), Haze = 2.6, Glare = 0 }, 1.4)
		tweenGrade({ Contrast = 0.12, Saturation = -0.3, TintColor = Color3.fromRGB(200, 202, 218), Brightness = -0.03 }, 1.4)
	elseif next == "interior" then
		tweenAtmo({ Density = BASE.density - 0.03, Color = BASE.atmoColor, Decay = BASE.decay, Haze = BASE.haze, Glare = BASE.glare }, 1.2)
		tweenGrade({ Contrast = BASE.contrast + 0.02, Saturation = BASE.saturation + 0.04, TintColor = Color3.fromRGB(236, 226, 214), Brightness = BASE.brightness }, 1.2)
	elseif next == "exterior" then
		tweenAtmo({ Density = BASE.density + 0.04, Color = BASE.atmoColor, Decay = BASE.decay, Haze = BASE.haze + 0.3, Glare = BASE.glare }, 1.2)
		tweenGrade({ Contrast = BASE.contrast, Saturation = BASE.saturation, TintColor = BASE.tint, Brightness = BASE.brightness }, 1.2)
	elseif next == "dawn" then
		TweenService:Create(Lighting, TweenInfo.new(22, Enum.EasingStyle.Sine), { ClockTime = 6.6, ExposureCompensation = 0.35 }):Play()
		tweenAtmo({ Density = 0.26, Color = Color3.fromRGB(255, 170, 130), Decay = Color3.fromRGB(120, 80, 90), Glare = 0.35, Haze = 2.2 }, 20)
		tweenGrade({ Contrast = 0.05, Saturation = 0.06, TintColor = Color3.fromRGB(255, 236, 220), Brightness = 0.02 }, 20)
		TweenService:Create(bloom, TweenInfo.new(20), { Intensity = 0.55 }):Play()
	elseif next == "defeat" then
		tweenGrade({ Contrast = 0.18, Saturation = -0.65, TintColor = Color3.fromRGB(190, 196, 210), Brightness = -0.04 }, 2.5)
		tweenAtmo({ Density = 0.5, Haze = 2.8 }, 2.5)
	end
	return from
end

local function refreshContextMode()
	if mode == "dawn" or mode == "defeat" then
		return
	end
	if ClientState.inTunnel then
		applyMode("tunnel")
	elseif ClientState.carIndex > 0 and not ClientState.exposed then
		applyMode("interior")
	else
		applyMode("exterior")
	end
end

----------------------------------------------------------------
-- Emergency strips (tunnels)
----------------------------------------------------------------
local function setStrips(on)
	for _, strip in ipairs(CollectionService:GetTagged(Tags.EmergencyStrip)) do
		if strip:IsA("BasePart") then
			strip.Material = on and Enum.Material.Neon or Enum.Material.Glass
			strip.Transparency = on and 0.05 or 0.5
		end
	end
end

----------------------------------------------------------------
-- Flicker + swing
----------------------------------------------------------------
local flickerLights = {}
local swingParts = {}
local furnaceFlickerUntil = 0

local function trackTag(tag, map, onAdd)
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		map[inst] = onAdd(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
		map[inst] = onAdd(inst)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
		map[inst] = nil
	end)
end

local function flickerStep(now)
	local camPos = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position
	if not camPos then
		return
	end
	local storm = now < furnaceFlickerUntil
	for light, base in pairs(flickerLights) do
		if not light.Parent then
			flickerLights[light] = nil
			continue
		end
		local host = light.Parent
		if host:IsA("BasePart") and (host.Position - camPos).Magnitude < 90 then
			local phase = base.phase
			local flicker = 0.82 + 0.26 * math.noise(now * 6.5, phase)
			if storm then
				flicker *= (math.noise(now * 26, phase) > 0.18 and 0.15 or 1.05)
			end
			light.Brightness = base.brightness * math.clamp(flicker, 0.05, 1.3)
		end
	end
	for part, base in pairs(swingParts) do
		if not part.Parent then
			swingParts[part] = nil
			continue
		end
		if (part.Position - camPos).Magnitude < 70 then
			local sway = math.noise(now * 0.7, base.phase) * math.clamp(ClientState.speed / 38, 0, 1)
			part.CFrame = base.cf * CFrame.Angles(sway * 0.16, 0, math.sin(now * 1.7 + base.phase) * 0.1 * math.clamp(ClientState.speed / 38, 0.1, 1))
		end
	end
end

----------------------------------------------------------------
-- Pulses
----------------------------------------------------------------
-- Exposed hooks for the ambient scare system
function LightingDirector.stormFor(seconds)
	furnaceFlickerUntil = math.max(furnaceFlickerUntil, os.clock() + (seconds or 1.2))
end

function LightingDirector.coldPulse()
	pulseCC.TintColor = Color3.fromRGB(170, 195, 235)
	pulseCC.Contrast = 0.1
	pulseCC.Saturation = -0.3
	TweenService:Create(pulseCC, TweenInfo.new(1.6, Enum.EasingStyle.Sine), {
		TintColor = Color3.new(1, 1, 1), Contrast = 0, Saturation = 0,
	}):Play()
end

local function damagePulse()
	pulseCC.TintColor = Color3.fromRGB(255, 120, 110)
	pulseCC.Contrast = 0.25
	pulseCC.Saturation = -0.4
	TweenService:Create(pulseCC, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {
		TintColor = Color3.new(1, 1, 1), Contrast = 0, Saturation = 0,
	}):Play()
end

local function furnaceFlash()
	pulseCC.TintColor = Color3.fromRGB(255, 190, 140)
	pulseCC.Brightness = 0.18
	TweenService:Create(pulseCC, TweenInfo.new(1.1, Enum.EasingStyle.Quad), {
		TintColor = Color3.new(1, 1, 1), Brightness = 0,
	}):Play()
end

----------------------------------------------------------------
-- Health desaturation
----------------------------------------------------------------
local function healthLoop()
	while true do
		task.wait(0.5)
		local hum = ClientState.localHumanoid()
		if hum and mode ~= "defeat" and mode ~= "dawn" then
			local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
			local hurt = 1 - frac
			if hurt > 0.55 then
				local target = -0.35 * (hurt - 0.55) / 0.45
				TweenService:Create(gradeCC, TweenInfo.new(0.6), {
					Saturation = (mode == "interior" and BASE.saturation + 0.04 or BASE.saturation) + target,
				}):Play()
			end
		end
	end
end

----------------------------------------------------------------
-- Start
----------------------------------------------------------------
function LightingDirector.start()
	buildEffects()

	trackTag(Tags.Flicker, flickerLights, function(light)
		return { brightness = light:IsA("Light") and light.Brightness or 1, phase = math.random() * 100 }
	end)
	trackTag(Tags.SwingLamp, swingParts, function(part)
		return { cf = part:IsA("BasePart") and part.CFrame or CFrame.new(), phase = math.random() * 100 }
	end)

	RunService.Heartbeat:Connect(function()
		flickerStep(os.clock())
	end)

	ClientState.signals.tunnelChanged:connect(function(active)
		setStrips(active)
		refreshContextMode()
	end)
	ClientState.signals.carChanged:connect(refreshContextMode)
	ClientState.signals.exposedChanged:connect(refreshContextMode)
	ClientState.signals.runStateChanged:connect(function(state)
		if state == "Victory" then
			applyMode("dawn")
		elseif state == "Defeat" then
			applyMode("defeat")
		elseif state == "Lobby" or state == "Journey" then
			-- fresh night
			Lighting.ClockTime = 0.05
			Lighting.ExposureCompensation = 0.15
			mode = "none"
			refreshContextMode()
		end
	end)

	Net.on(Net.T.FurnaceWarn, function(data)
		furnaceFlickerUntil = os.clock() + (data.eta or 6)
	end)
	Net.on(Net.T.FurnacePass, function(data)
		if math.abs((data.car or 0) - ClientState.carIndex) <= 1 then
			furnaceFlash()
		end
	end)
	Net.on(Net.T.Damage, damagePulse)
	Net.on(Net.T.ParallelBreak, function(data)
		if data.car == ClientState.carIndex then
			damagePulse()
		end
	end)

	task.spawn(healthLoop)

	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal("Ghost"):Connect(function()
		if player:GetAttribute("Ghost") then
			tweenGrade({ Saturation = -0.5, TintColor = Color3.fromRGB(170, 205, 255) }, 1.5)
		else
			mode = "none"
			refreshContextMode()
		end
	end)
end

return LightingDirector
