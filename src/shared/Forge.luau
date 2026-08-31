--[[
	Forge.luau
	Everything in THE 11:59 is built from parts at runtime — no uploaded
	assets. Forge is the tiny construction language that keeps that sane.
	All geometry is anchored; the world does not simulate, it performs.
]]

local Tags = require(script.Parent.Tags)
local CollectionService = game:GetService("CollectionService")

local Forge = {}

local function apply(part, spec)
	part.Anchored = spec.anchored ~= false
	part.CanCollide = spec.cancollide ~= false
	part.CanQuery = spec.canquery ~= false
	part.CanTouch = spec.cantouch ~= false
	part.CastShadow = spec.castshadow ~= false
	if spec.size then part.Size = spec.size end
	if spec.cf then part.CFrame = spec.cf end
	if spec.color then part.Color = spec.color end
	if spec.material then part.Material = spec.material end
	if spec.transparency then part.Transparency = spec.transparency end
	if spec.reflectance then part.Reflectance = spec.reflectance end
	if spec.name then part.Name = spec.name end
	if spec.tag then CollectionService:AddTag(part, spec.tag) end
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = spec.parent
	return part
end

function Forge.part(spec)
	return apply(Instance.new("Part"), spec)
end

function Forge.wedge(spec)
	return apply(Instance.new("WedgePart"), spec)
end

function Forge.corner(spec)
	return apply(Instance.new("CornerWedgePart"), spec)
end

function Forge.cyl(spec)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder -- axis along local X
	return apply(part, spec)
end

function Forge.ball(spec)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	return apply(part, spec)
end

function Forge.truss(spec)
	return apply(Instance.new("TrussPart"), spec)
end

function Forge.seat(spec)
	local seat = Instance.new("Seat")
	seat.Disabled = spec.disabled == true
	return apply(seat, spec)
end

-- Invisible volume used for zones and hide spots.
function Forge.zone(spec)
	spec.cancollide = false
	spec.transparency = 1
	spec.castshadow = false
	local part = Forge.part(spec)
	part.CanTouch = spec.cantouch ~= false
	return part
end

function Forge.model(name, parent)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

function Forge.folder(name, parent)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function Forge.attach(part, cf)
	local att = Instance.new("Attachment")
	if cf then
		att.CFrame = cf
	end
	att.Parent = part
	return att
end

function Forge.light(parent, spec)
	local class = "PointLight"
	if spec.kind == "spot" then
		class = "SpotLight"
	elseif spec.kind == "surface" then
		class = "SurfaceLight"
	end
	local light = Instance.new(class)
	light.Color = spec.color or Color3.new(1, 1, 1)
	light.Brightness = spec.brightness or 1
	light.Range = spec.range or 12
	light.Shadows = spec.shadows == true
	if class ~= "PointLight" then
		light.Angle = spec.angle or 90
		light.Face = spec.face or Enum.NormalId.Front
	end
	if spec.flicker then
		CollectionService:AddTag(light, Tags.Flicker)
	end
	light.Enabled = spec.enabled ~= false
	light.Parent = parent
	return light
end

function Forge.particles(parent, spec)
	local pe = Instance.new("ParticleEmitter")
	-- No texture id: Roblox's default soft sprite. Reads as ember/dust/mist
	-- depending on color, size and speed.
	pe.Color = spec.color or ColorSequence.new(Color3.new(1, 1, 1))
	pe.Size = spec.size or NumberSequence.new(0.4)
	pe.Transparency = spec.transparency or NumberSequence.new(0.4, 1)
	pe.Lifetime = spec.lifetime or NumberRange.new(1, 2)
	pe.Rate = spec.rate or 8
	pe.Speed = spec.speed or NumberRange.new(0.5, 1.5)
	pe.SpreadAngle = spec.spread or Vector2.new(15, 15)
	pe.Acceleration = spec.accel or Vector3.zero
	pe.LightEmission = spec.lightEmission or 0
	pe.LightInfluence = spec.lightInfluence or 1
	pe.Rotation = spec.rotation or NumberRange.new(0, 360)
	pe.RotSpeed = spec.rotSpeed or NumberRange.new(-20, 20)
	pe.Drag = spec.drag or 0
	pe.ZOffset = spec.zoffset or 0
	pe.Enabled = spec.enabled ~= false
	pe.Parent = parent
	return pe
end

function Forge.prompt(parent, spec)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = spec.action or "Use"
	prompt.ObjectText = spec.object or ""
	prompt.HoldDuration = spec.hold or 0
	prompt.MaxActivationDistance = spec.distance or 8
	prompt.RequiresLineOfSight = spec.los == true
	prompt.Style = Enum.ProximityPromptStyle.Custom -- drawn by the client theme
	prompt.KeyboardKeyCode = spec.key or Enum.KeyCode.E
	prompt.GamepadKeyCode = spec.pad or Enum.KeyCode.ButtonX
	prompt.ClickablePrompt = true
	prompt.Exclusivity = spec.exclusivity or Enum.ProximityPromptExclusivity.OnePerButton
	if spec.id then
		prompt:SetAttribute("PromptId", spec.id)
	end
	CollectionService:AddTag(prompt, Tags.ThemedPrompt)
	if spec.tag then
		CollectionService:AddTag(prompt, spec.tag)
	end
	prompt.Enabled = spec.enabled ~= false
	prompt.Parent = parent
	return prompt
end

function Forge.surfaceText(part, face, text, spec)
	spec = spec or {}
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = spec.pps or 50
	gui.LightInfluence = spec.lightInfluence or 0.6
	gui.Brightness = spec.brightness or 1
	gui.AlwaysOnTop = false
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = spec.font or Enum.Font.SpecialElite
	label.Text = text
	label.TextColor3 = spec.color or Color3.new(1, 1, 1)
	label.TextScaled = spec.scaled ~= false
	label.TextTransparency = spec.textTransparency or 0
	label.TextStrokeTransparency = 1
	label.Parent = gui
	if spec.maxSize then
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = spec.maxSize
		constraint.Parent = label
	end
	return gui, label
end

function Forge.sound(parent, id, spec)
	spec = spec or {}
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = spec.volume or 0.5
	sound.PlaybackSpeed = spec.speed or 1
	sound.Looped = spec.looped == true
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = spec.min or 8
	sound.RollOffMaxDistance = spec.max or 90
	if spec.group then
		sound.SoundGroup = spec.group
	end
	sound.Parent = parent
	if spec.play then
		sound:Play()
	end
	return sound
end

-- A four-legged box frame; the accordion rings between cars, crate frames, etc.
function Forge.ring(spec)
	local model = Forge.model(spec.name or "Ring", spec.parent)
	local w, h, t, d = spec.width, spec.height, spec.thick or 0.4, spec.depth or 0.4
	local cf = spec.cf
	local color = spec.color
	local material = spec.material
	Forge.part({ parent = model, size = Vector3.new(d, t, w), cf = cf * CFrame.new(0, h / 2 - t / 2, 0), color = color, material = material, cancollide = false })
	Forge.part({ parent = model, size = Vector3.new(d, t, w), cf = cf * CFrame.new(0, -h / 2 + t / 2, 0), color = color, material = material, cancollide = false })
	Forge.part({ parent = model, size = Vector3.new(d, h - t * 2, t), cf = cf * CFrame.new(0, 0, w / 2 - t / 2), color = color, material = material, cancollide = false })
	Forge.part({ parent = model, size = Vector3.new(d, h - t * 2, t), cf = cf * CFrame.new(0, 0, -w / 2 + t / 2), color = color, material = material, cancollide = false })
	return model
end

return Forge
