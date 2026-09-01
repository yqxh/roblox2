--[[
	EntityFX.luau
	The server keeps its monsters cheap; every client dresses them up.
	Furnace gets a molten trail and leaves scorched, ember-raining aisles;
	the Engineer's grate spits sparks; the caboose stove smokes politely.
]]

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Tags = require(Shared.Tags)
local Palette = require(Shared.Palette)

local EntityFX = {}

local T = Config.Train

local function emitter(parent, spec)
	local pe = Instance.new("ParticleEmitter")
	pe.Color = spec.color
	pe.Size = spec.size
	pe.Transparency = spec.transparency or NumberSequence.new(0.2, 1)
	pe.Lifetime = spec.lifetime or NumberRange.new(0.4, 1)
	pe.Rate = spec.rate or 20
	pe.Speed = spec.speed or NumberRange.new(1, 3)
	pe.SpreadAngle = spec.spread or Vector2.new(25, 25)
	pe.LightEmission = spec.lightEmission or 1
	pe.LightInfluence = 0
	pe.Acceleration = spec.accel or Vector3.zero
	pe.Enabled = spec.enabled ~= false
	pe.Parent = parent
	return pe
end

----------------------------------------------------------------
-- Rig dressing
----------------------------------------------------------------
local function dressFurnace(model)
	local core = model:WaitForChild("Core", 3)
	if not core then
		return
	end
	-- molten wake
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1, 0)
	a0.Parent = core
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1, 0)
	a1.Parent = core
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Palette.FurnaceCore, Color3.fromRGB(120, 20, 8))
	trail.Transparency = NumberSequence.new(0.15, 1)
	trail.Lifetime = 0.45
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Parent = core
	-- extra spitting sparks, local only
	emitter(a0, {
		color = ColorSequence.new(Color3.fromRGB(255, 210, 130), Palette.FurnaceCore),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.05) }),
		lifetime = NumberRange.new(0.5, 1.2),
		rate = 60,
		speed = NumberRange.new(6, 14),
		spread = Vector2.new(180, 180),
		accel = Vector3.new(0, -14, 0),
	})
end

local function dressEngineer(model)
	local grate = model:WaitForChild("Grate", 3)
	if not grate then
		return
	end
	local att = Instance.new("Attachment")
	att.Parent = grate
	emitter(att, {
		color = ColorSequence.new(Palette.FurnaceEmber, Color3.fromRGB(90, 16, 8)),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.16), NumberSequenceKeypoint.new(1, 0.03) }),
		lifetime = NumberRange.new(0.4, 0.9),
		rate = 14,
		speed = NumberRange.new(1, 3),
		spread = Vector2.new(40, 40),
		accel = Vector3.new(0, -6, 0),
	})
end

local function onRig(model)
	local kind = model:GetAttribute("EntityKind")
	if kind == "Furnace" then
		task.spawn(dressFurnace, model)
	elseif kind == "Engineer" then
		task.spawn(dressEngineer, model)
	end
end

----------------------------------------------------------------
-- The Furnace's wake: scorched aisle + ember rain in the struck car
----------------------------------------------------------------
local function scorchCar(carIndex)
	local x0 = (carIndex - 1) * T.CarPitch
	local scorch = Instance.new("Part")
	scorch.Anchored = true
	scorch.CanCollide = false
	scorch.CanQuery = false
	scorch.CastShadow = false
	scorch.Size = Vector3.new(T.CarLength - 4, 0.06, 3.4)
	scorch.CFrame = CFrame.new(x0 + T.CarLength / 2, T.FloorY + 0.06, 0)
	scorch.Color = Palette.FurnaceEmber
	scorch.Material = Enum.Material.Neon
	scorch.Transparency = 0.35
	scorch.Parent = workspace
	TweenService:Create(scorch, TweenInfo.new(9, Enum.EasingStyle.Sine), {
		Transparency = 1,
		Color = Color3.fromRGB(60, 14, 8),
	}):Play()
	Debris:AddItem(scorch, 9.5)

	-- embers sift down from the burst lamps for a while
	local rain = Instance.new("Part")
	rain.Anchored = true
	rain.CanCollide = false
	rain.CanQuery = false
	rain.Transparency = 1
	rain.Size = Vector3.new(T.CarLength - 8, 0.2, 6)
	rain.CFrame = CFrame.new(x0 + T.CarLength / 2, T.FloorY + T.CarHeight - 1, 0)
	rain.Parent = workspace
	local att = Instance.new("Attachment")
	att.Parent = rain
	local pe = emitter(att, {
		color = ColorSequence.new(Palette.FurnaceEmber, Color3.fromRGB(80, 20, 10)),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0.02) }),
		lifetime = NumberRange.new(1.2, 2.4),
		rate = 22,
		speed = NumberRange.new(0.5, 1.5),
		spread = Vector2.new(160, 20),
		accel = Vector3.new(0, -5, 0),
	})
	task.delay(6, function()
		pe.Enabled = false
	end)
	Debris:AddItem(rain, 10)
end

----------------------------------------------------------------
-- Caboose comfort: the stove pipe smokes while we sit in the lobby
----------------------------------------------------------------
local stoveSmoke = nil
local function refreshStoveSmoke()
	if stoveSmoke and not stoveSmoke.Parent then
		stoveSmoke = nil
	end
	if stoveSmoke then
		return
	end
	local train = workspace:FindFirstChild("Train")
	local caboose = train and train:FindFirstChild("Car_01")
	local pipe = caboose and caboose:FindFirstChild("StovePipe")
	if not pipe then
		return
	end
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(4.4, 0, 0) -- pipe is a cylinder laid along X after rotation
	att.Parent = pipe
	emitter(att, {
		color = ColorSequence.new(Color3.fromRGB(120, 116, 112), Color3.fromRGB(40, 40, 44)),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.4) }),
		transparency = NumberSequence.new(0.55, 1),
		lifetime = NumberRange.new(2, 3.5),
		rate = 6,
		speed = NumberRange.new(1.5, 3),
		spread = Vector2.new(12, 12),
		lightEmission = 0,
		accel = Vector3.new(-2, 3, 0),
	})
	stoveSmoke = att
end

----------------------------------------------------------------
-- Start
----------------------------------------------------------------
function EntityFX.start()
	for _, model in ipairs(CollectionService:GetTagged(Tags.EntityRig)) do
		onRig(model)
	end
	CollectionService:GetInstanceAddedSignal(Tags.EntityRig):Connect(onRig)

	Net.on(Net.T.FurnacePass, function(data)
		if type(data) == "table" and type(data.car) == "number" then
			scorchCar(data.car)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(3)
			refreshStoveSmoke()
		end
	end)
end

return EntityFX
