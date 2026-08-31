--[[
	EconomyService.luau
	Fare: found in luggage, spent at station machines, stolen by fines.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local ItemDefs = require(Shared.ItemDefs)
local SoundBank = require(Shared.SoundBank)

local EconomyService = {}
local ctx

local machines = {} -- machineId -> {part, stock = {itemName -> count | true}}

function EconomyService.init(c)
	ctx = c
end

function EconomyService.addFare(player, amount)
	if amount == 0 then
		return
	end
	player:SetAttribute("Fare", math.max((player:GetAttribute("Fare") or 0) + amount, 0))
	if amount > 0 then
		ctx.StatsService.noteFare(player, amount)
	end
end

function EconomyService.trySpend(player, amount)
	local fare = player:GetAttribute("Fare") or 0
	if fare < amount then
		return false
	end
	player:SetAttribute("Fare", fare - amount)
	return true
end

function EconomyService.fine(player, fraction)
	local fare = player:GetAttribute("Fare") or 0
	local taken = math.floor(fare * fraction)
	player:SetAttribute("Fare", fare - taken)
	return taken
end

----------------------------------------------------------------
-- Vending machines (registered by StationService)
----------------------------------------------------------------
function EconomyService.registerMachine(machineId, part, stock)
	machines[machineId] = { part = part, stock = stock }
end

function EconomyService.clearMachines()
	machines = {}
end

local function handleBuy(player, data)
	if type(data) ~= "table" or type(data.item) ~= "string" or type(data.machineId) ~= "string" then
		return
	end
	local machine = machines[data.machineId]
	if not machine or not machine.part.Parent then
		return
	end
	local char, _, root = ctx.util.aliveCharacter(player)
	if not char or (root.Position - machine.part.Position).Magnitude > 14 then
		return
	end
	local stockLeft = machine.stock[data.item]
	if not stockLeft or (type(stockLeft) == "number" and stockLeft <= 0) then
		Net.fireClient(player, Net.T.ShopResult, { ok = false, reason = "sold out" })
		SoundBank.play("UiDeny", machine.part)
		return
	end
	local price = Config.Economy.Prices[data.item]
	if not price then
		return
	end
	local def = ItemDefs.get(data.item)
	if def.unique and ctx.ItemService.playerHas(player, data.item) then
		Net.fireClient(player, Net.T.ShopResult, { ok = false, reason = "you carry one already" })
		return
	end
	if not EconomyService.trySpend(player, price) then
		Net.fireClient(player, Net.T.ShopResult, { ok = false, reason = ("%d fare short"):format(price - (player:GetAttribute("Fare") or 0)) })
		SoundBank.play("UiDeny", machine.part)
		return
	end
	if type(stockLeft) == "number" then
		machine.stock[data.item] = stockLeft - 1
	end
	ctx.ItemService.grant(player, data.item)
	SoundBank.play("Purchase", machine.part)
	Net.fireClient(player, Net.T.ShopResult, { ok = true, item = data.item })
	Net.fireClient(player, Net.T.Toast, { text = ("Bought: %s (-%d fare)"):format(def.display, price), tone = "loot" })
end

-- Direct entry for vending prompts (same validation as the remote path).
function EconomyService.requestBuy(player, item, machineId)
	handleBuy(player, { item = item, machineId = machineId })
end

function EconomyService.start()
	Net.on(Net.T.Buy, handleBuy)
end

return EconomyService
