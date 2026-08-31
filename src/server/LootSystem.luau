--[[
	LootSystem.luau
	Containers, loot tables, and the guarantees that keep runs fair:
	tickets seed the cars before an inspection, brass keys spawn behind
	the doors they open, one pry bar turns up early, and some luggage
	is not luggage (the Stowaway's work).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Forge = require(Shared.Forge)
local SoundBank = require(Shared.SoundBank)
local ItemDefs = require(Shared.ItemDefs)

local LootSystem = {}
local ctx

local nodesByCar = {} -- carIndex -> {node...}
local prybarGuaranteed = false
local watchSeeded = false

-- kind -> {fare = {min, max}, itemChance, hold, loud, items = weighted list}
local TABLES = {
	bag = {
		fare = { 2, 6 }, itemChance = 0.3, hold = 0.6,
		items = { { 30, "Bandage" }, { 20, "Flare" }, { 20, "Battery" }, { 20, "Ticket" }, { 10, "Oil" } },
	},
	suitcase = {
		fare = { 3, 9 }, itemChance = 0.45, hold = 0.6, mimicable = true,
		items = { { 24, "Bandage" }, { 18, "Flare" }, { 18, "Ticket" }, { 14, "Battery" }, { 12, "Oil" }, { 8, "Prybar" }, { 4, "Tonic" }, { 2, "Pocketwatch" } },
	},
	drawer = {
		fare = { 2, 7 }, itemChance = 0.4, hold = 0.6,
		items = { { 25, "Ticket" }, { 22, "Bandage" }, { 18, "Battery" }, { 15, "Oil" }, { 12, "Flare" }, { 8, "BrassKey" } },
	},
	cabinet = {
		fare = { 3, 8 }, itemChance = 0.45, hold = 0.6,
		items = { { 26, "Bandage" }, { 20, "Oil" }, { 18, "Flare" }, { 16, "Battery" }, { 12, "Ticket" }, { 8, "Tonic" } },
	},
	sack = {
		fare = { 4, 10 }, itemChance = 0.35, hold = 0.8, loud = true,
		items = { { 30, "Ticket" }, { 25, "Bandage" }, { 20, "Flare" }, { 15, "Battery" }, { 10, "Oil" } },
	},
	crate = {
		fare = { 6, 14 }, itemChance = 0.6, hold = 1.4, loud = true, mimicable = true,
		items = { { 25, "Flare" }, { 20, "Battery" }, { 20, "Oil" }, { 15, "Bandage" }, { 15, "Prybar" }, { 5, "Tonic" } },
	},
	lockbox = {
		fare = { 20, 35 }, itemChance = 1, hold = 1.2, locked = true,
		items = { { 32, "Tonic" }, { 26, "Pocketwatch" }, { 22, "Prybar" }, { 20, "BrassKey" } },
	},
	chest = {
		fare = { 15, 30 }, itemChance = 0.8, hold = 1, mimicable = true,
		items = { { 30, "Tonic" }, { 20, "Pocketwatch" }, { 20, "Flare" }, { 15, "Bandage" }, { 15, "BrassKey" } },
	},
	nest = {
		fare = { 10, 20 }, itemChance = 0.7, hold = 1.2, loud = true,
		items = { { 25, "Tonic" }, { 25, "Ticket" }, { 25, "Bandage" }, { 25, "Flare" } },
	},
}

function LootSystem.init(c)
	ctx = c
end

----------------------------------------------------------------
-- Opening
----------------------------------------------------------------
local function markOpened(node)
	node.opened = true
	if node.prompt then
		node.prompt:Destroy()
		node.prompt = nil
	end
	local part = node.part
	if part and part.Parent then
		part.Color = part.Color:Lerp(Color3.new(0, 0, 0), 0.35)
		-- a propped-open lid
		Forge.part({
			parent = part.Parent, name = "OpenLid",
			size = Vector3.new(math.min(part.Size.X, 2.2), 0.2, math.min(part.Size.Z, 1.6)),
			cf = part.CFrame * CFrame.new(0, part.Size.Y / 2 + 0.35, -0.3) * CFrame.Angles(math.rad(-38), 0, 0),
			color = part.Color, material = part.Material, cancollide = false,
		})
	end
end

local function rollLoot(node, player)
	local tbl = TABLES[node.kind]
	local rng = ctx.rng
	local richMul = node.opts.rich and 1.7 or 1
	local deepMul = 1 + (node.carIndex / Config.Train.Cars) * 0.6

	local fare = math.floor(rng:NextNumber(tbl.fare[1], tbl.fare[2]) * richMul * deepMul + 0.5)
	local itemName = nil

	if node.guaranteedItem then
		itemName = node.guaranteedItem
	elseif rng:NextNumber() < tbl.itemChance * richMul then
		local options = {}
		for _, entry in ipairs(tbl.items) do
			local weight, name = entry[1], entry[2]
			local def = ItemDefs.get(name)
			-- uniques stop rolling once someone carries one
			if def.unique and ctx.ItemService.anyoneHas(name) then
				weight = 0
			end
			if name == "Prybar" and not prybarGuaranteed then
				weight += 6
			end
			if weight > 0 then
				table.insert(options, { weight = weight, value = name })
			end
		end
		if #options > 0 then
			itemName = ctx.util.weightedPick(rng, options)
		end
	end

	ctx.EconomyService.addFare(player, fare)
	local text = ("%d fare"):format(fare)
	if itemName then
		local granted = ctx.ItemService.grant(player, itemName)
		if granted then
			local def = ItemDefs.get(itemName)
			text = text .. " · " .. def.display
			if itemName == "Prybar" then
				prybarGuaranteed = true
			end
		else
			ctx.EconomyService.addFare(player, 10)
			text = text .. " · 10 fare (already carried)"
		end
	end
	Net.fireClient(player, Net.T.Toast, { text = "Found: " .. text, tone = "loot" })
end

local function onOpen(node, player)
	if node.opened then
		return
	end
	local char = ctx.util.aliveCharacter(player)
	if not char or player:GetAttribute("Ghost") or player:GetAttribute("Downed") then
		return
	end
	local tbl = TABLES[node.kind]

	-- the strongbox resists
	if tbl.locked then
		local hasPry = char:FindFirstChild("Prybar") ~= nil
		if not hasPry and not ctx.ItemService.consumeItem(player, "BrassKey") then
			SoundBank.play("UiDeny", node.part)
			Net.fireClient(player, Net.T.Toast, { text = "Sealed tight. A brass key or a pry bar would argue better.", tone = "warn" })
			return
		end
		if hasPry then
			ctx.signals.noiseEvent:fire(player, Config.Noise.Pry, node.part.Position)
		end
	end

	if tbl.loud then
		local quiet = char:FindFirstChild("Prybar") ~= nil and node.kind == "crate"
		ctx.signals.noiseEvent:fire(player, quiet and Config.Noise.Pry * 0.4 or Config.Noise.Pry, node.part.Position)
	end

	markOpened(node)

	if node.mimic then
		ctx.Entities.Stowaway.trigger(node, player)
		return
	end

	SoundBank.play(node.kind == "crate" and "PryCreak" or "Rummage", node.part)
	rollLoot(node, player)
end

----------------------------------------------------------------
-- Population
----------------------------------------------------------------
local function decorateGuarantees(carIndex, nodes)
	local rng = ctx.rng
	local plan = ctx.plan

	local function flagRandom(kindFilter, itemName)
		local candidates = {}
		for _, node in ipairs(nodes) do
			if not node.guaranteedItem and (not kindFilter or kindFilter[node.kind]) and not TABLES[node.kind].locked then
				table.insert(candidates, node)
			end
		end
		if #candidates > 0 then
			candidates[rng:NextInteger(1, #candidates)].guaranteedItem = itemName
			return true
		end
		return false
	end

	-- brass key for a locked door ahead
	for _, car in pairs(plan.cars) do
		if car.doorState == "locked" and car.keyCar == carIndex then
			flagRandom(nil, "BrassKey")
		end
	end

	-- tickets before an inspection
	for _, inspectorCar in ipairs(Config.Run.InspectorCars) do
		if carIndex == inspectorCar - 1 or carIndex == inspectorCar - 2 then
			flagRandom(nil, "Ticket")
			if carIndex == inspectorCar - 1 then
				flagRandom(nil, "Ticket")
			end
		end
	end

	-- one crow's gift early
	if not prybarGuaranteed and carIndex == 3 then
		if flagRandom(nil, "Prybar") then
			prybarGuaranteed = true
		end
	end

	-- the conductor's watch turns up somewhere mid-train if nobody found one
	if not watchSeeded and carIndex >= 11 and carIndex <= 13 and not ctx.ItemService.anyoneHas("Pocketwatch") then
		if flagRandom(nil, "Pocketwatch") then
			watchSeeded = true
		end
	end

	-- mimics
	local mimicChance = carIndex > 15 and Config.Entities.Stowaway.DeepChance or Config.Entities.Stowaway.BaseChance
	local forced = 0
	for _, node in ipairs(nodes) do
		local tbl = TABLES[node.kind]
		if tbl.mimicable and not node.guaranteedItem then
			if node.opts.mimicPool and forced < 2 then
				node.mimic = true
				forced += 1
			elseif carIndex >= 4 and rng:NextNumber() < mimicChance then
				node.mimic = true
			end
			if node.mimic then
				node.part:SetAttribute("Uneasy", true) -- the tell, read by observant clients
			end
		end
	end
end

function LootSystem.populateCar(carIndex, meta)
	local nodes = {}
	for _, data in ipairs(meta.lootNodes or {}) do
		local tbl = TABLES[data.kind]
		if not tbl then
			continue
		end
		local node = {
			kind = data.kind,
			part = data.part,
			opts = data.opts or {},
			carIndex = carIndex,
			opened = false,
		}
		node.prompt = Forge.prompt(data.part, {
			action = tbl.locked and "Break open" or "Search",
			object = "",
			hold = tbl.hold,
			distance = 6.5,
			id = ("loot:%d:%d"):format(carIndex, #nodes + 1),
		})
		node.prompt.Triggered:Connect(function(player)
			onOpen(node, player)
		end)
		table.insert(nodes, node)
	end
	nodesByCar[carIndex] = nodes
	decorateGuarantees(carIndex, nodes)

	-- the lounge piano and other regrettable attractions
	for _, prop in ipairs(meta.model:GetChildren()) do
		if prop:GetAttribute("PropKind") == "piano" then
			local prompt = prop:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				local lastPlayed = 0
				prompt.Triggered:Connect(function(player)
					if os.clock() - lastPlayed < 2.5 or player:GetAttribute("Ghost") then
						return
					end
					lastPlayed = os.clock()
					SoundBank.play("Piano", prop, { max = 200 })
					ctx.signals.noiseEvent:fire(player, Config.Noise.Piano, prop.Position)
					if ctx.rng:NextNumber() < Config.Economy.PianoTipChance then
						ctx.EconomyService.addFare(player, Config.Economy.PianoTip)
						Net.fireClient(player, Net.T.Toast, { text = "A cold coin lands on the keys. The dead appreciate music.", tone = "loot" })
					end
				end)
			end
		end
	end
end

function LootSystem.unregisterCar(carIndex)
	nodesByCar[carIndex] = nil
end

function LootSystem.resetRun()
	nodesByCar = {}
	prybarGuaranteed = false
	watchSeeded = false
end

return LootSystem
