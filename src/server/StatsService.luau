--[[
	StatsService.luau
	Leaderstats + a small persistent record. Every DataStore touch is
	wrapped; Studio without API access just runs stateless.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local StatsService = {}
local ctx

local store = nil
local session = {} -- player -> {wins, bestCar, deaths, fare}

local function carOf(player)
	return player:GetAttribute("CarIndex") or 0
end

function StatsService.init(c)
	ctx = c
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("T59_Stats_v1")
	end)
	if ok then
		store = result
	end
end

function StatsService.setupPlayer(player)
	local data = { wins = 0, bestCar = 0, deaths = 0, fare = 0 }
	if store then
		pcall(function()
			local saved = store:GetAsync("u" .. player.UserId)
			if type(saved) == "table" then
				data.wins = tonumber(saved.wins) or 0
				data.bestCar = tonumber(saved.bestCar) or 0
				data.deaths = tonumber(saved.deaths) or 0
				data.fare = tonumber(saved.fare) or 0
			end
		end)
	end
	session[player] = data

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local wins = Instance.new("IntValue")
	wins.Name = "Escapes"
	wins.Value = data.wins
	wins.Parent = stats
	local best = Instance.new("IntValue")
	best.Name = "Best Car"
	best.Value = data.bestCar
	best.Parent = stats
	stats.Parent = player
end

local function persist(player)
	local data = session[player]
	if not (store and data) then
		return
	end
	pcall(function()
		store:SetAsync("u" .. player.UserId, data)
	end)
end

local function refreshBoard(player)
	local data = session[player]
	local stats = player:FindFirstChild("leaderstats")
	if data and stats then
		local wins = stats:FindFirstChild("Escapes")
		local best = stats:FindFirstChild("Best Car")
		if wins then
			wins.Value = data.wins
		end
		if best then
			best.Value = data.bestCar
		end
	end
end

function StatsService.noteDeath(player)
	local data = session[player]
	if data then
		data.deaths += 1
	end
end

function StatsService.noteFare(player, amount)
	local data = session[player]
	if data then
		data.fare += amount
	end
end

function StatsService.recordRunEnd(victory)
	for _, player in ipairs(Players:GetPlayers()) do
		local data = session[player]
		if data then
			if victory and not player:GetAttribute("Ghost") then
				data.wins += 1
			end
			data.bestCar = math.max(data.bestCar, carOf(player))
			refreshBoard(player)
			task.spawn(persist, player)
		end
	end
end

function StatsService.start()
	Players.PlayerRemoving:Connect(function(player)
		local data = session[player]
		if data then
			data.bestCar = math.max(data.bestCar, carOf(player))
			persist(player)
			session[player] = nil
		end
	end)
end

return StatsService
