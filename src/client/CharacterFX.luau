--[[
	CharacterFX.luau
	Body feel: sprint with a real stamina tank, crouch, footsteps by
	material, landings, wind shoving you around on the roof, pings for
	wordless co-op, and jump-to-slip-out while hidden.
	Movement is client-authoritative in Roblox; the server measures what
	it cares about (velocity → noise) independently.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local SoundBank = require(Shared.SoundBank)
local ClientState = require(script.Parent:WaitForChild("ClientState"))

local CharacterFX = {}

local player = Players.LocalPlayer
local P = Config.Player

local sprintHeld = false
local gustVelocity = Vector3.zero

----------------------------------------------------------------
-- Speed arbitration (stance x sprint x stamina)
----------------------------------------------------------------
local function desiredSpeed()
	if ClientState.stance == "crouch" then
		return P.CrouchSpeed
	end
	if sprintHeld and ClientState.stamina > 0.02 and not ClientState.hidden and not ClientState.isDowned() then
		return P.SprintSpeed
	end
	return P.WalkSpeed
end

local function applySpeed()
	local hum = ClientState.localHumanoid()
	if not hum or ClientState.isGhost() then
		return
	end
	local target = desiredSpeed()
	-- don't fight temporary server buffs (tonic) that push higher
	if hum.WalkSpeed < target or hum.WalkSpeed <= P.SprintSpeed + 0.5 then
		hum.WalkSpeed = target
	end
	ClientState.sprinting = sprintHeld and target >= P.SprintSpeed - 0.5
end

----------------------------------------------------------------
-- Stance / inputs
----------------------------------------------------------------
local function setStance(stance)
	if ClientState.stance == stance then
		return
	end
	ClientState.stance = stance
	Net.fire(Net.T.SetStance, { stance = stance })
	local hum = ClientState.localHumanoid()
	if hum then
		hum.CameraOffset = stance == "crouch" and Vector3.new(0, -1.3, 0) or Vector3.zero
	end
	applySpeed()
end

local function toggleCrouch()
	setStance(ClientState.stance == "crouch" and "stand" or "crouch")
end

local function sendPing()
	local cam = workspace.CurrentCamera
	local char = player.Character
	if not cam or not char then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, workspace:FindFirstChild("LocalScenery") }
	local result = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 90, params)
	local pos = result and result.Position or (cam.CFrame.Position + cam.CFrame.LookVector * 30)
	Net.fire(Net.T.SendPing, { pos = pos })
end

local function bindInputs()
	ContextActionService:BindAction("T59_Sprint", function(_, state)
		sprintHeld = state == Enum.UserInputState.Begin
		applySpeed()
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle("T59_Sprint", "Run")
	ContextActionService:SetPosition("T59_Sprint", UDim2.new(1, -160, 1, -130))

	ContextActionService:BindAction("T59_Crouch", function(_, state)
		if state == Enum.UserInputState.Begin then
			toggleCrouch()
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle("T59_Crouch", "Duck")
	ContextActionService:SetPosition("T59_Crouch", UDim2.new(1, -90, 1, -130))

	ContextActionService:BindAction("T59_Ping", function(_, state)
		if state == Enum.UserInputState.Begin then
			sendPing()
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
	ContextActionService:SetTitle("T59_Ping", "Point")
	ContextActionService:SetPosition("T59_Ping", UDim2.new(1, -160, 1, -200))

	-- jump slips you out of a hide spot
	UserInputService.JumpRequest:Connect(function()
		if ClientState.hidden then
			Net.fire(Net.T.ExitHide, {})
		end
	end)
end

----------------------------------------------------------------
-- Stamina
----------------------------------------------------------------
local function staminaLoop(dt)
	if ClientState.sprinting and not ClientState.isGhost() then
		local hum = ClientState.localHumanoid()
		local moving = hum and hum.MoveDirection.Magnitude > 0.1
		if moving then
			ClientState.stamina = math.max(ClientState.stamina - dt / P.SprintSeconds, 0)
			if ClientState.stamina <= 0.01 then
				sprintHeld = false
				SoundBank.play("Breath", nil, { volumeScale = 1.2 })
			end
		end
	else
		ClientState.stamina = math.min(ClientState.stamina + dt * P.StaminaRegenPerSecond, 1)
	end
	applySpeed()
end

----------------------------------------------------------------
-- Footsteps + landings
----------------------------------------------------------------
local stepAccum = 0
local function footstepLoop(dt)
	local char = player.Character
	local hum = ClientState.localHumanoid()
	local root = ClientState.localRoot()
	if not (char and hum and root) or ClientState.hidden then
		return
	end
	local state = hum:GetState()
	if state ~= Enum.HumanoidStateType.Running and state ~= Enum.HumanoidStateType.RunningNoPhysics then
		return
	end
	local vel = root.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	if speed < 2 then
		return
	end
	stepAccum += dt * speed
	local stride = 5.4
	if stepAccum >= stride then
		stepAccum = 0
		local material = hum.FloorMaterial
		local pitch = 0.85 + math.random() * 0.25
		local vol = math.clamp(speed / P.SprintSpeed, 0.25, 1) * 0.5
		if ClientState.stance == "crouch" then
			vol *= 0.35
		end
		if material == Enum.Material.Metal or material == Enum.Material.DiamondPlate then
			pitch *= 1.25
			vol *= 1.15
		elseif material == Enum.Material.Fabric or material == Enum.Material.Carpet then
			vol *= 0.5
		end
		local stepSound = Instance.new("Sound")
		stepSound.SoundId = SoundBank.FILES.Steps
		stepSound.PlaybackSpeed = pitch * 3.2
		stepSound.Volume = vol
		stepSound.TimePosition = 0.05
		stepSound.Parent = root
		stepSound:Play()
		task.delay(0.16, function()
			stepSound:Destroy()
		end)
	end
end

local function wireCharacter(char)
	local hum = char:WaitForChild("Humanoid")
	hum.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Landed then
			SoundBank.play("Land", ClientState.localRoot(), { volumeScale = 0.5 })
			local CameraFX = require(script.Parent:WaitForChild("CameraFX"))
			CameraFX.addTrauma(0.12)
		end
	end)
	ClientState.stamina = 1
	sprintHeld = false
	ClientState.stance = "stand"
end

----------------------------------------------------------------
-- Roof wind
----------------------------------------------------------------
local nextGustAt = 0
local function gustLoop(dt)
	local root = ClientState.localRoot()
	if not root then
		return
	end
	if ClientState.exposed and ClientState.speed > 12 and not ClientState.isGhost() then
		local now = os.clock()
		if now >= nextGustAt then
			nextGustAt = now + math.random(6, 14)
			local strength = 14 + ClientState.speed * 0.35
			gustVelocity = Vector3.new(-strength, 0, (math.random() - 0.5) * strength * 0.8)
			SoundBank.play("BeamWhoosh", nil, { volumeScale = 0.3, pitchScale = 0.7 })
			task.delay(0.9, function()
				gustVelocity = Vector3.zero
			end)
		end
		if gustVelocity.Magnitude > 0.1 then
			root.AssemblyLinearVelocity += gustVelocity * dt * 2.4
		end
	end
end

----------------------------------------------------------------
-- Start
----------------------------------------------------------------
function CharacterFX.start()
	bindInputs()
	if player.Character then
		wireCharacter(player.Character)
	end
	player.CharacterAdded:Connect(wireCharacter)

	RunService.Heartbeat:Connect(function(dt)
		staminaLoop(dt)
		footstepLoop(dt)
		gustLoop(dt)
	end)
end

return CharacterFX
