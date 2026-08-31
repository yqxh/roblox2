--[[
	ItemService.luau
	Items are real Tools with procedurally built handles. Actives get a
	cloned ToolClient LocalScript that just reports intent; everything that
	matters (fuel, healing, flares, consumption) is validated here.
	Passives (Ticket, BrassKey) are per-player counters, not backpack litter.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Forge = require(Shared.Forge)
local Palette = require(Shared.Palette)
local Tags = require(Shared.Tags)
local ItemDefs = require(Shared.ItemDefs)
local SoundBank = require(Shared.SoundBank)
local Util = require(Shared.Util)

local ItemService = {}
local ctx

local M = Palette.M
local litTools = {}     -- tool -> {player, kind}
local groundFlares = {} -- part -> {expires}
local watchHolders = {} -- player -> true
local busy = {}         -- player -> "bandage" channel lock

function ItemService.init(c)
	ctx = c
end

----------------------------------------------------------------
-- Passive counters
----------------------------------------------------------------
local function passiveAttr(name)
	return "Item_" .. name
end

local function passiveCount(player, name)
	return player:GetAttribute(passiveAttr(name)) or 0
end

local function addPassive(player, name, delta)
	player:SetAttribute(passiveAttr(name), math.max(passiveCount(player, name) + delta, 0))
end

----------------------------------------------------------------
-- Tool geometry
----------------------------------------------------------------
local function decorate(tool, handle, name)
	if name == "Flashlight" then
		handle.Size = Vector3.new(0.5, 0.5, 1.6)
		handle.Color = Color3.fromRGB(70, 72, 78)
		handle.Material = M.Metal
		local head = Forge.part({
			parent = tool, name = "Head",
			size = Vector3.new(0.7, 0.7, 0.5),
			cf = handle.CFrame * CFrame.new(0, 0, -0.9),
			color = Color3.fromRGB(90, 92, 98), material = M.Metal,
			anchored = false, cancollide = false,
		})
		local lens = Forge.part({
			parent = tool, name = "Lens",
			size = Vector3.new(0.55, 0.55, 0.12),
			cf = head.CFrame * CFrame.new(0, 0, -0.28),
			color = Color3.fromRGB(255, 236, 180), material = M.Glass,
			anchored = false, cancollide = false,
		})
		local light = Instance.new("SpotLight")
		light.Angle = 42
		light.Range = 34
		light.Brightness = 2.4
		light.Color = Color3.fromRGB(255, 235, 190)
		light.Face = Enum.NormalId.Front
		light.Shadows = true
		light.Enabled = false
		light.Parent = lens
		for _, p in ipairs({ head, lens }) do
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = p
			weld.Parent = p
		end
		tool.Grip = CFrame.new(0, -0.1, 0.55)
	elseif name == "Lantern" then
		handle.Size = Vector3.new(0.7, 1.1, 0.7)
		handle.Color = Palette.Brass
		handle.Material = M.Metal
		local glass = Forge.part({
			parent = tool, name = "Glass",
			size = Vector3.new(0.55, 0.7, 0.55),
			cf = handle.CFrame,
			color = Palette.LampGlass, material = M.Glass, transparency = 0.25,
			anchored = false, cancollide = false,
		})
		local light = Instance.new("PointLight")
		light.Range = 26
		light.Brightness = 1.6
		light.Color = Palette.LampGlow
		light.Shadows = true
		light.Enabled = false
		light.Parent = glass
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = glass
		weld.Parent = glass
		tool.Grip = CFrame.new(0, -0.75, 0)
	elseif name == "Flare" then
		handle.Size = Vector3.new(0.35, 1.2, 0.35)
		handle.Color = Color3.fromRGB(190, 60, 48)
		handle.Material = M.Plastic
		local cap = Forge.part({
			parent = tool, name = "Cap",
			size = Vector3.new(0.37, 0.25, 0.37),
			cf = handle.CFrame * CFrame.new(0, 0.6, 0),
			color = Color3.fromRGB(230, 220, 200), material = M.Plastic,
			anchored = false, cancollide = false,
		})
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = cap
		weld.Parent = cap
		tool.Grip = CFrame.new(0, -0.35, 0)
	elseif name == "Bandage" then
		handle.Size = Vector3.new(0.8, 0.5, 0.8)
		handle.Color = Palette.UIPaper
		handle.Material = M.Fabric
		tool.Grip = CFrame.new(0, 0, 0)
	elseif name == "Tonic" then
		handle.Size = Vector3.new(0.45, 0.9, 0.45)
		handle.Color = Color3.fromRGB(60, 140, 90)
		handle.Material = M.Glass
		handle.Transparency = 0.2
		tool.Grip = CFrame.new(0, -0.25, 0)
	elseif name == "Prybar" then
		handle.Size = Vector3.new(0.3, 2.4, 0.3)
		handle.Color = Color3.fromRGB(140, 60, 50)
		handle.Material = M.Metal
		local hook = Forge.part({
			parent = tool, name = "Hook",
			size = Vector3.new(0.32, 0.5, 0.7),
			cf = handle.CFrame * CFrame.new(0, 1.3, 0.2),
			color = Color3.fromRGB(140, 60, 50), material = M.Metal,
			anchored = false, cancollide = false,
		})
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = hook
		weld.Parent = hook
		tool.Grip = CFrame.new(0, -0.9, 0) * CFrame.Angles(0, 0, math.rad(15))
	elseif name == "Pocketwatch" then
		handle.Size = Vector3.new(0.55, 0.15, 0.55)
		handle.Color = Palette.Brass
		handle.Material = M.Metal
		handle.Reflectance = 0.3
		tool.Grip = CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(-50), 0, 0)
	elseif name == "Battery" then
		handle.Size = Vector3.new(0.45, 0.8, 0.45)
		handle.Color = Color3.fromRGB(90, 110, 190)
		handle.Material = M.Metal
	elseif name == "Oil" then
		handle.Size = Vector3.new(0.6, 0.9, 0.6)
		handle.Color = Color3.fromRGB(160, 130, 60)
		handle.Material = M.CorrodedMetal
	end
end

local function buildTool(name)
	local def = ItemDefs.get(name)
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.ToolTip = def.display
	tool.RequiresHandle = true
	tool.CanBeDropped = false -- deliberate drops go through pickups
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool
	decorate(tool, handle, name)
	tool:SetAttribute("ItemName", name)
	if def.fuelMax then
		tool:SetAttribute("Fuel", def.fuelMax)
		tool:SetAttribute("FuelMax", def.fuelMax)
		tool:SetAttribute("On", false)
	end
	if name == "Flare" then
		tool:SetAttribute("Lit", false)
	end

	local template = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("ToolClient")
	local client = template:Clone()
	client.Parent = tool

	tool.Equipped:Connect(function()
		local char = tool.Parent
		local player = char and Players:GetPlayerFromCharacter(char)
		if player and name == "Pocketwatch" then
			watchHolders[player] = true
		end
	end)
	tool.Unequipped:Connect(function()
		for player in pairs(watchHolders) do
			local char = player.Character
			if not (char and char:FindFirstChild("Pocketwatch")) then
				watchHolders[player] = nil
			end
		end
	end)
	return tool
end

----------------------------------------------------------------
-- Granting / consuming / dropping
----------------------------------------------------------------
function ItemService.grant(player, name)
	local def = ItemDefs.get(name)
	if not def then
		return false
	end
	if def.kind == "passive" then
		addPassive(player, name, 1)
		return true
	end
	if def.unique and ItemService.playerHas(player, name) then
		return false
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return false
	end
	local tool = buildTool(name)
	tool.Parent = backpack
	return true
end

function ItemService.playerHas(player, name)
	if ItemDefs.get(name).kind == "passive" then
		return passiveCount(player, name) > 0
	end
	local char = player.Character
	if char and char:FindFirstChild(name) then
		return true
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	return backpack and backpack:FindFirstChild(name) ~= nil
end

function ItemService.anyoneHas(name)
	for _, player in ipairs(Players:GetPlayers()) do
		if ItemService.playerHas(player, name) then
			return true
		end
	end
	return false
end

function ItemService.consumeItem(player, name)
	local def = ItemDefs.get(name)
	if def.kind == "passive" then
		if passiveCount(player, name) > 0 then
			addPassive(player, name, -1)
			return true
		end
		return false
	end
	local char = player.Character
	local tool = (char and char:FindFirstChild(name))
	if not tool then
		local backpack = player:FindFirstChildOfClass("Backpack")
		tool = backpack and backpack:FindFirstChild(name)
	end
	if tool then
		litTools[tool] = nil
		tool:Destroy()
		return true
	end
	return false
end

function ItemService.clearInventory(player)
	watchHolders[player] = nil
	for _, name in ipairs(ItemDefs.Order) do
		if ItemDefs.get(name).kind == "passive" then
			player:SetAttribute(passiveAttr(name), 0)
		end
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		backpack:ClearAllChildren()
	end
	local char = player.Character
	if char then
		for _, tool in ipairs(char:GetChildren()) do
			if tool:IsA("Tool") then
				tool:Destroy()
			end
		end
	end
end

-- A pickup lying in the world; anyone can take it.
function ItemService.spawnPickup(name, position)
	local def = ItemDefs.get(name)
	if not def then
		return
	end
	local part = Forge.part({
		parent = ctx.folders.pickups, name = "Pickup_" .. name,
		size = Vector3.new(0.9, 0.9, 0.9),
		cf = CFrame.new(position) * CFrame.Angles(0, math.random() * 6.28, 0),
		color = def.color, material = M.Smooth,
		tag = Tags.Pickup,
	})
	part:SetAttribute("ItemName", name)
	local prompt = Forge.prompt(part, {
		action = "Take",
		object = def.display,
		hold = 0,
		distance = 6,
		id = "pickup",
	})
	prompt.Triggered:Connect(function(player)
		if player:GetAttribute("Ghost") or player:GetAttribute("Downed") then
			return
		end
		if not part.Parent then
			return
		end
		if ItemService.grant(player, name) then
			part:Destroy()
			SoundBank.play("UiConfirm", player.Character and Util.rootOf(player.Character))
			Net.fireClient(player, Net.T.Toast, { text = "Taken: " .. def.display, tone = "loot" })
		else
			Net.fireClient(player, Net.T.Toast, { text = "You already carry one of those.", tone = "warn" })
		end
	end)
	Debris:AddItem(part, 180)
	return part
end

function ItemService.dropAllItems(player, position)
	local function dropTool(tool)
		local name = tool:GetAttribute("ItemName")
		if name then
			litTools[tool] = nil
			tool:Destroy()
			ItemService.spawnPickup(name, position + Vector3.new(math.random(-2, 2), 0.5, math.random(-2, 2)))
		end
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, tool in ipairs(backpack:GetChildren()) do
			if tool:IsA("Tool") then
				dropTool(tool)
			end
		end
	end
	local char = player.Character
	if char then
		for _, tool in ipairs(char:GetChildren()) do
			if tool:IsA("Tool") then
				dropTool(tool)
			end
		end
	end
	for _, name in ipairs({ "Ticket", "BrassKey" }) do
		for _ = 1, passiveCount(player, name) do
			ItemService.spawnPickup(name, position + Vector3.new(math.random(-2, 2), 0.5, math.random(-2, 2)))
		end
		player:SetAttribute(passiveAttr(name), 0)
	end
	watchHolders[player] = nil
end

----------------------------------------------------------------
-- Light sources (the Gloom reads this like a menu)
----------------------------------------------------------------
function ItemService.lightSources()
	local sources = {}
	for tool, info in pairs(litTools) do
		if tool.Parent then
			local handle = tool:FindFirstChild("Handle")
			if handle then
				local score = info.kind == "Flare" and 4 or (info.kind == "Lantern" and 3 or 2)
				table.insert(sources, {
					pos = handle.Position,
					score = score,
					kind = info.kind,
					player = info.player,
					tool = tool,
				})
			end
		else
			litTools[tool] = nil
		end
	end
	for part, info in pairs(groundFlares) do
		if part.Parent and os.clock() < info.expires then
			table.insert(sources, { pos = part.Position, score = 5, kind = "GroundFlare", part = part })
		else
			groundFlares[part] = nil
		end
	end
	return sources
end

function ItemService.extinguish(source)
	if source.tool and source.tool.Parent then
		local tool = source.tool
		if source.kind == "Flare" then
			tool:Destroy()
		else
			tool:SetAttribute("On", false)
			ItemService.applyLightState(tool)
		end
		litTools[tool] = nil
	elseif source.part then
		source.part:Destroy()
		groundFlares[source.part] = nil
	end
end

function ItemService.applyLightState(tool)
	local name = tool:GetAttribute("ItemName")
	local on = tool:GetAttribute("On") == true
	if name == "Flashlight" then
		local lens = tool:FindFirstChild("Lens")
		local light = lens and lens:FindFirstChildOfClass("SpotLight")
		if light then
			light.Enabled = on
		end
		if lens then
			lens.Material = on and M.Neon or M.Glass
		end
	elseif name == "Lantern" then
		local glass = tool:FindFirstChild("Glass")
		local light = glass and glass:FindFirstChildOfClass("PointLight")
		if light then
			light.Enabled = on
		end
		if glass then
			glass.Material = on and M.Neon or M.Glass
			glass.Transparency = on and 0 or 0.25
		end
	end
end

local function igniteFlareEffects(host)
	local flame = Forge.attach(host, CFrame.new(0, 0.7, 0))
	Forge.particles(flame, {
		color = ColorSequence.new(Color3.fromRGB(255, 90, 60), Color3.fromRGB(255, 40, 20)),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.1) }),
		lifetime = NumberRange.new(0.3, 0.6),
		rate = 40,
		speed = NumberRange.new(1, 2.5),
		lightEmission = 1,
		lightInfluence = 0,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 70, 50)
	light.Range = 24
	light.Brightness = 2.2
	light.Shadows = true
	light.Parent = host
	return flame
end

----------------------------------------------------------------
-- Actions
----------------------------------------------------------------
local function findEquipped(player, name)
	local char = player.Character
	local tool = char and char:FindFirstChild(name)
	if tool and tool:IsA("Tool") then
		return tool
	end
	return nil
end

local actions = {}

function actions.toggle(player, tool)
	local name = tool:GetAttribute("ItemName")
	if name ~= "Flashlight" and name ~= "Lantern" then
		return
	end
	local fuel = tool:GetAttribute("Fuel") or 0
	local on = not (tool:GetAttribute("On") == true)
	if on and fuel <= 0 then
		Net.fireClient(player, Net.T.Toast, { text = name == "Lantern" and "Dry. It wants oil." or "Dead. It wants a battery.", tone = "warn" })
		return
	end
	tool:SetAttribute("On", on)
	ItemService.applyLightState(tool)
	SoundBank.play("FlashClick", tool:FindFirstChild("Handle"))
	if on then
		litTools[tool] = { player = player, kind = name }
	else
		litTools[tool] = nil
	end
end

function actions.strike(player, tool)
	if tool:GetAttribute("ItemName") ~= "Flare" or tool:GetAttribute("Lit") then
		return
	end
	tool:SetAttribute("Lit", true)
	local handle = tool:FindFirstChild("Handle")
	if handle then
		igniteFlareEffects(handle)
		SoundBank.play("FlareStrike", handle)
	end
	litTools[tool] = { player = player, kind = "Flare" }
	ctx.signals.noiseEvent:fire(player, Config.Noise.Flare, handle and handle.Position)
	local def = ItemDefs.get("Flare")
	task.delay(def.burnSeconds, function()
		if tool.Parent then
			litTools[tool] = nil
			tool:Destroy()
		end
	end)
end

function actions.throw(player, tool)
	if tool:GetAttribute("ItemName") ~= "Flare" or not tool:GetAttribute("Lit") then
		return
	end
	local char, _, root = Util.aliveCharacter(player)
	if not char then
		return
	end
	litTools[tool] = nil
	tool:Destroy()
	local part = Forge.part({
		parent = ctx.folders.pickups, name = "ThrownFlare",
		size = Vector3.new(0.35, 1.1, 0.35),
		cf = root.CFrame * CFrame.new(0.5, 1.2, -1.5),
		color = Color3.fromRGB(190, 60, 48), material = M.Plastic,
		anchored = false, cancollide = true,
	})
	part.AssemblyLinearVelocity = root.CFrame.LookVector * 38 + Vector3.new(0, 14, 0)
	part.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), 0, math.random(-8, 8))
	igniteFlareEffects(part)
	groundFlares[part] = { expires = os.clock() + ItemDefs.get("Flare").burnSeconds }
	ctx.signals.noiseEvent:fire(player, Config.Noise.Flare * 0.6, part.Position)
	Debris:AddItem(part, ItemDefs.get("Flare").burnSeconds + 2)
end

function actions.use(player, tool)
	local name = tool:GetAttribute("ItemName")
	local def = ItemDefs.get(name)
	local char, hum, root = Util.aliveCharacter(player)
	if not char then
		return
	end
	if name == "Bandage" then
		if busy[player] then
			return
		end
		if hum.Health >= hum.MaxHealth then
			Net.fireClient(player, Net.T.Toast, { text = "Nothing bleeding. Yet.", tone = "warn" })
			return
		end
		busy[player] = true
		Net.fireClient(player, Net.T.ItemState, { slot = "Bandage", channel = def.useSeconds })
		task.delay(def.useSeconds, function()
			busy[player] = nil
			local stillTool = findEquipped(player, "Bandage")
			local char2, hum2 = Util.aliveCharacter(player)
			if stillTool and char2 and hum2 and not player:GetAttribute("Downed") then
				stillTool:Destroy()
				ctx.PlayerService.heal(player, def.healAmount)
				Net.fireClient(player, Net.T.Toast, { text = "Wrapped tight.", tone = "good" })
			end
		end)
	elseif name == "Tonic" then
		tool:Destroy()
		hum.Health = hum.MaxHealth
		SoundBank.play("Heal", root)
		local boosted = (player:GetAttribute("Stance") == "crouch" and Config.Player.CrouchSpeed or Config.Player.WalkSpeed) + def.speedBoost
		hum.WalkSpeed = boosted
		Net.fireClient(player, Net.T.Toast, { text = "Warmth, then speed, then the taste of pennies.", tone = "good" })
		task.delay(def.boostSeconds, function()
			local char2, hum2 = Util.aliveCharacter(player)
			if char2 and hum2 then
				hum2.WalkSpeed = player:GetAttribute("Stance") == "crouch" and Config.Player.CrouchSpeed or Config.Player.WalkSpeed
			end
		end)
	elseif name == "Battery" or name == "Oil" then
		local targetName = def.refills
		local target = findEquipped(player, targetName)
		if not target then
			local backpack = player:FindFirstChildOfClass("Backpack")
			target = backpack and backpack:FindFirstChild(targetName)
		end
		if target then
			tool:Destroy()
			target:SetAttribute("Fuel", target:GetAttribute("FuelMax"))
			SoundBank.play("LatchOpen", root)
			Net.fireClient(player, Net.T.Toast, { text = targetName == "Lantern" and "The lantern drinks deep." or "Fresh cells.", tone = "good" })
		else
			Net.fireClient(player, Net.T.Toast, { text = "Nothing to refill.", tone = "warn" })
		end
	end
end

----------------------------------------------------------------
-- Fuel drain + watch noise
----------------------------------------------------------------
local function fuelStep()
	for tool, info in pairs(litTools) do
		if not tool.Parent then
			litTools[tool] = nil
			continue
		end
		local fuelMax = tool:GetAttribute("FuelMax")
		if fuelMax then
			local fuel = (tool:GetAttribute("Fuel") or 0) - 1
			tool:SetAttribute("Fuel", fuel)
			if fuel <= 0 then
				tool:SetAttribute("On", false)
				ItemService.applyLightState(tool)
				litTools[tool] = nil
				if info.player then
					Net.fireClient(info.player, Net.T.Toast, { text = "Your light gutters out.", tone = "warn" })
				end
			end
		end
	end
	for player in pairs(watchHolders) do
		if player.Parent then
			ctx.PlayerService.addNoise(player, Config.Noise.WatchTickPerSecond)
		else
			watchHolders[player] = nil
		end
	end
end

function ItemService.watchHolderList()
	local list = {}
	for player in pairs(watchHolders) do
		if player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

----------------------------------------------------------------
-- Wiring
----------------------------------------------------------------
function ItemService.start()
	Net.on(Net.T.ToolAction, function(player, data)
		if type(data) ~= "table" or type(data.tool) ~= "string" or type(data.action) ~= "string" then
			return
		end
		if player:GetAttribute("Ghost") or player:GetAttribute("Downed") then
			return
		end
		local tool = findEquipped(player, data.tool)
		if not tool then
			return
		end
		local fn = actions[data.action]
		if fn then
			fn(player, tool)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			fuelStep()
		end
	end)
end

return ItemService
