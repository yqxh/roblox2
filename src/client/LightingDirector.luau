--[[
	LightingDirector.luau
	The film grade. Roblox has no custom shader pipeline, so the look is
	built from everything it does expose, pushed hard: Future lighting with
	a true-darkness ambient floor and environment specular (brass glints,
	rail shine), a per-mode Atmosphere/CC/Bloom/DoF stack, per-biome fog
	shifts, gaslight flicker, swinging fixtures, tunnel blackouts with
	emergency strips, and a real dawn when you win.
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
	offset = 0.42,
	atmoColor = Color3.fromRGB(22, 29, 50),
	decay = Color3.fromRGB(11, 13, 26),
	glare = 0.14,
	haze = 1.8,
	contrast = 0.10,
	saturation = -0.10,
	tint = Color3.fromRGB(206, 216, 246),
	brightness = 0,
	outdoorAmbient = Color3.fromRGB(17, 23, 40),
}

local mode = "exterior" -- exterior | interior | tunnel | dawn | defeat
local currentBiome = "pine"

local function biomeAtmo()
	local fog = Palette.BiomeFog[currentBiome] or BASE.atmoColor
	local density, haze, glare = BASE.density, BASE.haze, BASE.glare
	local decay = BASE.decay
	if currentBiome == "marsh" then
		density += 0.06
		haze += 0.5
	elseif currentBiome == "fields" then
		density -= 0.04
		haze -= 0.2
	elseif currentBiome == "yard" then
		density += 0.03
		haze += 0.3
		decay = Color3.fromRGB(20, 16, 24)
	elseif currentBiome == "gorge" then
		density -= 0.08
		haze -= 0.4
		glare += 0.08
	end
	return fog, density, haze, glare, decay
end

local function buildEffects()
	Lighting:ClearAllChildren()

	-- service baseline: the reason night reads cinematic instead of muddy
	Lighting.Brightness = 1.4
	Lighting.ClockTime = 1.5 -- the moon rakes in at an angle, not from zenith
	Lighting.GeographicLatitude = 41
	Lighting.ExposureCompensation = 0.1
	Lighting.Ambient = Color3.fromRGB(7, 8, 12)          -- true darkness floor
	Lighting.OutdoorAmbient = BASE.outdoorAmbient        -- cold moonlit fill
	Lighting.ColorShift_Top = Color3.fromRGB(112, 132, 188)
	Lighting.EnvironmentDiffuseScale = 0.18
	Lighting.EnvironmentSpecularScale = 0.5              -- metal/brass/glass glint
	Lighting.ShadowSoftness = 0.15

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
	bloom.Intensity = 0.5
	bloom.Size = 40
	bloom.Threshold = 1.4 -- hugs Neon and speculars; no frame-wide haze
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
	dof.FarIntensity = 0.25
	dof.FocusDistance = 55
	dof.InFocusRadius = 40
	dof.NearIntensity = 0.12
	dof.Parent = Lighting

	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
		clouds.Cover = 0.52
		clouds.Density = 0.32
		clouds.Color = Color3.fromRGB(44, 52, 78)
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

local function tweenDoF(props, seconds)
	TweenService:Create(dof, TweenInfo.new(seconds or 1.2, Enum.EasingStyle.Sine), props):Play()
end

local function tweenBloom(props, seconds)
	TweenService:Create(bloom, TweenInfo.new(seconds or 1.2, Enum.EasingStyle.Sine), props):Play()
end

local function tweenOutdoor(color, seconds)
	TweenService:Create(Lighting, TweenInfo.new(seconds or 1.2, Enum.EasingStyle.Sine), { OutdoorAmbient = color }):Play()
end

local function applyMode(next)
	if mode == next then
		return
	end
	mode = next
	local fog, density, haze, glare, decay = biomeAtmo()

	if next == "tunnel" then
		tweenAtmo({ Density = 0.60, Offset = 0.10, Color = Color3.fromRGB(7, 7, 10), Decay = Color3.fromRGB(3, 3, 6), Haze = 2.8, Glare = 0 }, 1.4)
		tweenGrade({ Contrast = 0.16, Saturation = -0.35, TintColor = Color3.fromRGB(196, 200, 216), Brightness = -0.05 }, 1.4)
		tweenBloom({ Intensity = 0.65, Threshold = 1.15 }, 1.4)
		tweenDoF({ FarIntensity = 0.35, FocusDistance = 30, InFocusRadius = 20, NearIntensity = 0.10 }, 1.4)
		tweenOutdoor(Color3.fromRGB(6, 6, 10), 1.4)
	elseif next == "interior" then
		tweenAtmo({ Density = density - 0.04, Offset = 0.34, Color = fog, Decay = decay, Haze = haze - 0.2, Glare = 0.12 }, 1.2)
		tweenGrade({ Contrast = 0.10, Saturation = 0, TintColor = Color3.fromRGB(240, 228, 212), Brightness = 0.01 }, 1.2)
		tweenBloom({ Intensity = 0.5, Threshold = 1.4 }, 1.2)
		tweenDoF({ FarIntensity = 0.12, FocusDistance = 26, InFocusRadius = 22, NearIntensity = 0.08 }, 1.2)
		tweenOutdoor(BASE.outdoorAmbient, 1.2)
	elseif next == "exterior" then
		tweenAtmo({ Density = density + 0.06, Offset = 0.50, Color = fog, Decay = decay, Haze = haze + 0.2, Glare = glare + 0.04 }, 1.2)
		tweenGrade({ Contrast = BASE.contrast, Saturation = BASE.saturation, TintColor = BASE.tint, Brightness = BASE.brightness }, 1.2)
		tweenBloom({ Intensity = 0.5, Threshold = 1.4 }, 1.2)
		tweenDoF({ FarIntensity = 0.25, FocusDistance = 55, InFocusRadius = 40, NearIntensity = 0.12 }, 1.2)
		tweenOutdoor(BASE.outdoorAmbient, 1.2)
	elseif next == "dawn" then
		TweenService:Create(Lighting, TweenInfo.new(22, Enum.EasingStyle.Sine), {
			ClockTime = 6.6, ExposureCompensation = 0.5,
			OutdoorAmbient = Color3.fromRGB(72, 58, 62),
			ColorShift_Top = Color3.fromRGB(255, 196, 150),
		}):Play()
		tweenAtmo({ Density = 0.22, Offset = 0.60, Color = Color3.fromRGB(255, 158, 112), Decay = Color3.fromRGB(98, 72, 110), Glare = 0.42, Haze = 2.1 }, 20)
		tweenGrade({ Contrast = 0.04, Saturation = 0.08, TintColor = Color3.fromRGB(255, 238, 220), Brightness = 0.03 }, 20)
		tweenBloom({ Intensity = 0.8, Size = 56, Threshold = 0.9 }, 20)
		tweenDoF({ FarIntensity = 0.08, FocusDistance = 80, InFocusRadius = 70, NearIntensity = 0.05 }, 20)
	elseif next == "defeat" then
		tweenGrade({ Contrast = 0.20, Saturation = -0.70, TintColor = Color3.fromRGB(188, 194, 208), Brightness = -0.05 }, 2.5)
		tweenAtmo({ Density = 0.52, Haze = 2.9, Color = Color3.fromRGB(26, 30, 40) }, 2.5)
	end
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

-- Biome fog shifts: called by SceneryController as the land changes
function LightingDirector.setBiome(kind)
	if kind == currentBiome or not Palette.BiomeFog[kind] then
		return
	end
	currentBiome = kind
	if mode == "exterior" or mode == "interior" then
		local fog, density, haze, glare, decay = biomeAtmo()
		local outside = mode == "exterior"
		tweenAtmo({
			Color = fog,
			Density = outside and density + 0.06 or density - 0.04,
			Haze = outside and haze + 0.2 or haze - 0.2,
			Glare = glare,
			Decay = decay,
		}, 4)
	end
end

----------------------------------------------------------------
-- Emergency strips (tunnels)
----------------------------------------------------------------
local function setStrips(on)
	for _, strip in ipairs(CollectionService:GetTagged(Tags.EmergencyStrip)) do
		if strip:IsA("BasePart") then
			strip.Material = on and Enum.Material.Neon or Enum.Material.Glass
			strip.Transparency = on and 0 or 0.5
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
-- Pulses + scare hooks
----------------------------------------------------------------
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
					Saturation = (mode == "interior" and 0 or BASE.saturation) + target,
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
			Lighting.ClockTime = 1.5
			Lighting.ExposureCompensation = 0.1
			Lighting.ColorShift_Top = Color3.fromRGB(112, 132, 188)
			Lighting.OutdoorAmbient = BASE.outdoorAmbient
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
