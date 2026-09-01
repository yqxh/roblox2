--[[
	PlayerService.luau
	Riders: spawning, health, the downed/bleed-out/revive dance, ghosthood,
	stances, the server-side noise meter, car tracking, and falling off the
	train. Nothing here trusts the client beyond its own movement.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Forge = require(Shared.Forge)
local Tags = require(Shared.Tags)
local SoundBank = require(Shared.SoundBank)
local Util = require(Shared.Util)

local PlayerService = {}
local ctx

local P = Config.Player

local state = {} -- player -> {noise, bleedThread, revivePrompt, lastDamage, dwell, dwellCar}

function PlayerService.init(c)
	ctx = c
end

----------------------------------------------------------------
-- Attributes & spawning
----------------------------------------------------------------
local function baseAttributes(player)
	player:SetAttribute("Fare", Config.Run.StartFare)
	player:SetAttribute("Ghost", false)
	player:SetAttribute("Downed", false)
	player:SetAttribute("Stance", "stand")
	player:SetAttribute("HiddenSpot", "")
	player:SetAttribute("NoiseLevel", 0)
	player:SetAttribute("CarIndex", 0)
end

local function applyCollisionGroup(character, group)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
end

local function dressGhost(player, character)
	CollectionService:AddTag(character, Tags.GhostChar)
	applyCollisionGroup(character, "Ghost")
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = math.max(part.Transparency, 0.75)
			part.CastShadow = false
		elseif part:IsA("Decal") then
			part.Transparency = 0.75
		elseif part:IsA("Accessory") then
			local handle = part:FindFirstChild("Handle")
			if handle then
				handle.Transparency = 0.85
			end
		end
	end
	local root = Util.rootOf(character)
	if root then
		local wisp = Forge.part({
			parent = character, name = "GhostWisp",
			size = Vector3.new(0.6, 0.6, 0.6),
			cf = root.CFrame,
			color = Color3.fromRGB(120, 190, 255), material = Enum.Material.Neon,
			anchored = false, cancollide = false, castshadow = false,
		})
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = wisp
		weld.Parent = wisp
		Forge.light(wisp, { color = Color3.fromRGB(120, 190, 255), range = 9, brightness = 0.6, shadows = false })
	end
	local hum = Util.humanoidOf(character)
	if hum then
		hum.WalkSpeed = P.GhostSpeed
	end
end

local function onCharacterAdded(player, character)
	local hum = character:WaitForChild("Humanoid")
	hum.MaxHealth = P.MaxHealth
	hum.Health = P.MaxHealth
	hum.WalkSpeed = P.WalkSpeed
	hum.UseJumpPower = false
	hum.JumpHeight = P.JumpHeight
	hum.BreakJointsOnDeath = false
	hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)

	task.defer(function()
		if player:GetAttribute("Ghost") then
			dressGhost(player, character)
		else
			applyCollisionGroup(character, "Rider")
		end
	end)
	character.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") then
			desc.CollisionGroup = player:GetAttribute("Ghost") and "Ghost" or "Rider"
		end
	end)

	hum.Died:Connect(function()
		PlayerService.onDied(player)
	end)
end

function PlayerService.spawnAt(player, cframe, asGhost)
	player:SetAttribute("Ghost", asGhost == true)
	player:SetAttribute("Downed", false)
	player:SetAttribute("HiddenSpot", "")
	player:LoadCharacter()
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart")
	task.wait()
	root.CFrame = cframe
	return character
end

function PlayerService.spawnAllAtLobby()
	for _, player in ipairs(Players:GetPlayers()) do
		baseAttributes(player)
		ctx.ItemService.clearInventory(player)
		PlayerService.spawnAt(player, ctx.TrainBuilder.lobbySpawnCF())
	end
end

----------------------------------------------------------------
-- Damage / downed / death
----------------------------------------------------------------
local function clearDowned(player)
	local s = state[player]
	player:SetAttribute("Downed", false)
	if s then
		if s.bleedThread then
			task.cancel(s.bleedThread)
			s.bleedThread = nil
		end
		if s.revivePrompt then
			s.revivePrompt:Destroy()
			s.revivePrompt = nil
		end
	end
	local char, hum = Util.aliveCharacter(player)
	if char and hum then
		hum.PlatformStand = false
	end
end

function PlayerService.revive(player, health)
	if not player:GetAttribute("Downed") then
		return
	end
	clearDowned(player)
	local char, hum = Util.aliveCharacter(player)
	if char and hum then
		hum.Health = health or P.ReviveHealth
		SoundBank.play("Revive", Util.rootOf(char))
	end
	Net.fireClient(player, Net.T.Toast, { text = "Back on your feet. Stay with the others.", tone = "good" })
end

local function enterDowned(player, cause)
	local char, hum, root = Util.aliveCharacter(player)
	if not char then
		return
	end
	ctx.HideSystem.eject(player)
	player:SetAttribute("Downed", true)
	hum.Health = 1
	hum.PlatformStand = true
	SoundBank.play("Down", root)
	ctx.signals.playerDowned:fire(player)
	Net.fireAll(Net.T.Subtitle, {
		text = ("%s is down. Somebody lift them."):format(player.DisplayName),
		seconds = 4,
	})

	local s = state[player]
	-- revive prompt for the others
	local prompt = Forge.prompt(root, {
		action = "Lift them",
		object = player.DisplayName,
		hold = P.ReviveHoldSeconds,
		distance = 7,
		id = "revive:" .. player.UserId,
	})
	prompt.Triggered:Connect(function(other)
		if other ~= player and not other:GetAttribute("Ghost") and not other:GetAttribute("Downed") then
			PlayerService.revive(player)
		end
	end)
	s.revivePrompt = prompt

	s.bleedThread = task.delay(P.BleedOutSeconds, function()
		s.bleedThread = nil
		if player.Parent and player:GetAttribute("Downed") then
			local char2, hum2 = Util.aliveCharacter(player)
			if hum2 then
				hum2.Health = 0
			else
				PlayerService.onDied(player)
			end
		end
	end)
end

function PlayerService.damage(player, amount, cause)
	if player:GetAttribute("Ghost") then
		return
	end
	local char, hum, root = Util.aliveCharacter(player)
	if not char then
		return
	end
	local s = state[player]
	if s then
		s.lastDamage = os.clock()
	end
	ctx.lastGroupDamage = os.clock()
	Net.fireClient(player, Net.T.Damage, { amount = amount, cause = cause or "?" })
	if player:GetAttribute("Downed") then
		hum.Health = 0
		return
	end
	if hum.Health - amount <= 0 then
		enterDowned(player, cause)
	else
		hum.Health -= amount
		SoundBank.play("Hurt", root, { volumeScale = 0.8 })
	end
end

function PlayerService.heal(player, amount)
	local char, hum = Util.aliveCharacter(player)
	if char and hum and not player:GetAttribute("Downed") then
		hum.Health = math.min(hum.Health + amount, hum.MaxHealth)
		SoundBank.play("Heal", Util.rootOf(char))
	end
end

function PlayerService.onDied(player, reason)
	if player:GetAttribute("Ghost") then
		return
	end
	clearDowned(player)
	ctx.HideSystem.eject(player)
	local char = player.Character
	local deathPos = nil
	if char then
		local root = Util.rootOf(char)
		if root then
			deathPos = root.Position
		end
	end
	-- inventory scatters where they fell
	if deathPos then
		ctx.ItemService.dropAllItems(player, deathPos)
	end
	SoundBank.play("Death", deathPos or ctx.TrainBuilder.carPosition(1))
	ctx.signals.playerGhosted:fire(player, reason or "died")
	ctx.StatsService.noteDeath(player)

	-- rise as a ghost aboard the train
	local carIndex = math.clamp(player:GetAttribute("CarIndex") or 1, ctx.TrainBuilder.rearMostBuilt(), Config.Train.Cars)
	local spawnCF
	if deathPos and ctx.TrainBuilder.carIndexAt(deathPos) then
		spawnCF = CFrame.new(deathPos + Vector3.new(0, 1, 0))
	else
		spawnCF = ctx.TrainBuilder.interiorSpawn(math.max(carIndex, ctx.TrainBuilder.rearMostBuilt()))
	end
	PlayerService.spawnAt(player, spawnCF, true)
	Net.fireClient(player, Net.T.Toast, { text = "You ride on, thinner than before. The next station remembers the living.", tone = "ghost" })
	SoundBank.play("GhostRise", spawnCF.Position)
end

-- Station arrivals put ghosts back on their feet.
function PlayerService.reviveGhostsAtStation(platformCF)
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Ghost") then
			local fare = player:GetAttribute("Fare") or 0
			player:SetAttribute("Fare", math.floor(fare * (1 - P.GhostRevivalFarePenalty)))
			local character = PlayerService.spawnAt(player, platformCF * CFrame.new(math.random(-4, 4), 0, math.random(-2, 2)), false)
			local hum = Util.humanoidOf(character)
			if hum then
				hum.Health = P.StationReviveHealth
			end
			Net.fireClient(player, Net.T.Toast, { text = "The stationmaster looks through you, and you are solid again.", tone = "good" })
		end
	end
end

----------------------------------------------------------------
-- Stance
----------------------------------------------------------------
local function setStance(player, stance)
	if stance ~= "stand" and stance ~= "crouch" then
		return
	end
	if player:GetAttribute("Downed") or player:GetAttribute("Ghost") then
		stance = "stand"
	end
	player:SetAttribute("Stance", stance)
	local char, hum = Util.aliveCharacter(player)
	if char and hum then
		hum.WalkSpeed = stance == "crouch" and P.CrouchSpeed or P.WalkSpeed
	end
end

----------------------------------------------------------------
-- Noise
----------------------------------------------------------------
function PlayerService.addNoise(player, amount)
	local s = state[player]
	if not s or player:GetAttribute("Ghost") then
		return
	end
	s.noise = math.clamp((s.noise or 0) + amount, 0, 1)
end

function PlayerService.noiseOf(player)
	local s = state[player]
	return s and s.noise or 0
end

local function noiseStep(dt)
	for _, player in ipairs(Players:GetPlayers()) do
		local s = state[player]
		if not s then
			continue
		end
		local add = 0
		local char, hum, root = Util.aliveCharacter(player)
		if char and not player:GetAttribute("Ghost") and not player:GetAttribute("Downed") then
			local vel = root.AssemblyLinearVelocity
			local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
			local stance = player:GetAttribute("Stance")
			if speed > P.WalkSpeed + 2 then
				add = Config.Noise.SprintPerSecond
			elseif speed > 2 then
				add = stance == "crouch" and Config.Noise.CrouchPerSecond or Config.Noise.WalkPerSecond
			end
			if hum:GetState() == Enum.HumanoidStateType.Freefall then
				add += 0.02
			end
		end
		s.noise = math.clamp((s.noise or 0) + (add - Config.Noise.DecayPerSecond) * dt, 0, 1)
		local rounded = math.floor(s.noise * 20 + 0.5) / 20
		if rounded ~= s.lastNoiseAttr then
			s.lastNoiseAttr = rounded
			player:SetAttribute("NoiseLevel", rounded)
		end
	end
end

----------------------------------------------------------------
-- Car tracking & falling off
----------------------------------------------------------------
local function trackStep()
	for _, player in ipairs(Players:GetPlayers()) do
		local s = state[player]
		if not s then
			continue
		end
		local char, _, root = Util.aliveCharacter(player)
		if not char then
			continue
		end
		local pos = root.Position

		-- fell off the train?
		if pos.Y < Config.Train.FloorY - 12 then
			if player:GetAttribute("Ghost") then
				root.CFrame = ctx.TrainBuilder.interiorSpawn(math.max(player:GetAttribute("CarIndex") or 1, ctx.TrainBuilder.rearMostBuilt()))
			elseif ctx.GameLoop.isMoving() then
				Net.fireAll(Net.T.Subtitle, { text = ("The valley kept %s."):format(player.DisplayName), seconds = 4 })
				local hum = Util.humanoidOf(char)
				if hum then
					hum.Health = 0
				end
			else
				-- stopped at a station: dust off, climb back
				root.CFrame = CFrame.new(pos.X, Config.Train.FloorY + 3.5, math.sign(pos.Z == 0 and 1 or pos.Z) * (Config.Train.CarWidth / 2 + 4))
			end
			continue
		end

		local carIndex = ctx.TrainBuilder.carIndexAt(pos) or 0
		local prev = player:GetAttribute("CarIndex") or 0
		if carIndex ~= prev then
			player:SetAttribute("CarIndex", carIndex)
			if carIndex > 0 then
				s.dwell = 0
				local plan = ctx.plan and ctx.plan.cars[carIndex]
				Net.fireClient(player, Net.T.CarEntered, {
					car = carIndex,
					label = Util.carLabel(carIndex),
					archetype = plan and plan.archetype or "coach",
				})
				ctx.signals.carEntered:fire(player, carIndex, prev)
			end
		else
			s.dwell = (s.dwell or 0) + 0.4
		end
	end
end

function PlayerService.dwellOf(player)
	local s = state[player]
	return s and s.dwell or 0
end

function PlayerService.resetDwell(player)
	local s = state[player]
	if s then
		s.dwell = 0
	end
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------
local function onPlayerAdded(player)
	state[player] = { noise = 0, dwell = 0 }
	baseAttributes(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	-- if we beat the world here, wait for the first run to assemble
	local waited = 0
	while ctx.GameLoop.state() == "Boot" and waited < 15 do
		waited += task.wait(0.2)
	end

	local runState = ctx.GameLoop.state()
	if runState == "Lobby" or runState == "Boot" then
		-- startRun's spawnAllAtLobby may have beaten us here; don't double-spawn
		if not player.Character then
			PlayerService.spawnAt(player, ctx.TrainBuilder.lobbySpawnCF())
		end
	else
		-- late joiners haunt the train until the next stop
		local rear = ctx.TrainBuilder.rearMostBuilt()
		PlayerService.spawnAt(player, ctx.TrainBuilder.interiorSpawn(rear), true)
		Net.fireClient(player, Net.T.Toast, { text = "You board between stations, which is impossible. Ride along; the next stop makes you real.", tone = "ghost" })
	end
	ctx.StatsService.setupPlayer(player)
end

function PlayerService.start()
	ctx.GameLoop = ctx.GameLoop or ctx.GameLoopRef

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		clearDowned(player)
		ctx.HideSystem.eject(player)
		state[player] = nil
	end)

	Net.on(Net.T.SetStance, function(player, data)
		if type(data) == "table" then
			setStance(player, data.stance)
		end
	end)

	Net.on(Net.T.SendPing, function(player, data)
		if type(data) ~= "table" or typeof(data.pos) ~= "Vector3" then
			return
		end
		local char, _, root = Util.aliveCharacter(player)
		if not char then
			return
		end
		if (data.pos - root.Position).Magnitude > 80 then
			return
		end
		Net.fireAll(Net.T.Ping, {
			pos = data.pos,
			name = player.DisplayName,
			ghost = player:GetAttribute("Ghost") == true,
		})
	end)

	ctx.signals.noiseEvent:connect(function(player, amount)
		PlayerService.addNoise(player, amount)
	end)

	task.spawn(function()
		while true do
			local dt = task.wait(0.25)
			noiseStep(dt)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.4)
			trackStep()
		end
	end)
end

return PlayerService
