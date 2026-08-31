--[[
	Parallel.luau
	Something keeps pace with the train, out in the fields, at window
	height. Glance and it stays a smear of white. Stare, and the whispers
	start; keep staring and it comes through the glass for your face.
	Pull the blinds. On a flatcar there are no blinds; there is looking away.

	Rendering is client-side (each client draws the figure from the same
	seed); the server only arbitrates gaze-time and the window break.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local SoundBank = require(Shared.SoundBank)
local Util = require(Shared.Util)

local Parallel = {}
local ctx

local E = Config.Entities.Parallel

local manifest = nil -- {car, side, endsAt, gaze = {player -> seconds}, whispered = {}}

local function allBlindsDown(meta, side)
	for _, win in ipairs(meta.windows or {}) do
		if win.side == side and not win.broken and win.model:GetAttribute("BlindDown") ~= true then
			return false
		end
	end
	return true
end

local function breakWindow(player)
	local m = manifest
	if not m then
		return
	end
	manifest = nil

	local meta = ctx.TrainBuilder.carMeta(m.car)
	local char, _, root = Util.aliveCharacter(player)
	if meta and m.side ~= 0 then
		-- the pane nearest the gazer gives way
		local nearest, bestDist = nil, math.huge
		for _, win in ipairs(meta.windows or {}) do
			if win.side == m.side and not win.broken then
				local dist = char and math.abs(win.x - root.Position.X) or math.abs(win.x)
				if dist < bestDist then
					nearest, bestDist = win, dist
				end
			end
		end
		if nearest then
			nearest.broken = true
			nearest.model:SetAttribute("Broken", true)
			nearest.glass.Transparency = 1
			nearest.glass.CanCollide = false
			SoundBank.play("WindowShatter", nearest.glass, { max = 200 })
			ctx.signals.noiseEvent:fire(player, Config.Noise.DoorSlam, nearest.glass.Position)
		end
	else
		SoundBank.play("ParallelSlam", char and root.Position or ctx.TrainBuilder.carPosition(m.car), { max = 200 })
	end

	Net.fireAll(Net.T.ParallelBreak, { car = m.car, side = m.side })
	ctx.PlayerService.damage(player, E.Damage, "parallel")
	Net.fireClient(player, Net.T.Subtitle, { text = "You looked too long, and it looked back all the way.", seconds = 5 })
end

function Parallel.init(c)
	ctx = c
	Net.on(Net.T.GazeReport, function(player, data)
		local m = manifest
		if not m or type(data) ~= "table" then
			return
		end
		if data.car ~= m.car or data.side ~= m.side then
			return
		end
		if player:GetAttribute("Ghost") or (player:GetAttribute("CarIndex") or 0) ~= m.car then
			return
		end
		local seconds = tonumber(data.seconds)
		if not seconds or seconds <= 0 or seconds > 0.5 then
			return
		end
		if m.side ~= 0 then
			local meta = ctx.TrainBuilder.carMeta(m.car)
			if not meta or allBlindsDown(meta, m.side) then
				return
			end
		end
		m.gaze[player] = (m.gaze[player] or 0) + seconds
		if m.gaze[player] >= E.GazeWhisperSeconds and not m.whispered[player] then
			m.whispered[player] = true
			Net.fireClient(player, Net.T.Stinger, { name = "ParallelWhisper" })
		end
		if m.gaze[player] >= E.GazeBreakSeconds then
			breakWindow(player)
		end
	end)
end

function Parallel.isActive()
	return manifest ~= nil
end

function Parallel.start(car, forced)
	if manifest then
		return
	end
	local meta = ctx.TrainBuilder.carMeta(car)
	if not meta then
		return
	end

	-- pick a side that has glass; flatcars use the deck (side 0)
	local side
	if meta.archetype == "flatcar" then
		side = 0
	else
		local sides = {}
		for _, win in ipairs(meta.windows or {}) do
			if not win.broken then
				sides[win.side] = true
			end
		end
		local pool = {}
		for s in pairs(sides) do
			table.insert(pool, s)
		end
		if #pool == 0 then
			return
		end
		side = pool[ctx.rng:NextInteger(1, #pool)]
	end

	local duration = forced and E.MaxDuration or ctx.rng:NextNumber(E.MinDuration, E.MaxDuration)
	manifest = {
		car = car,
		side = side,
		endsAt = os.clock() + duration,
		gaze = {},
		whispered = {},
	}
	Net.fireAll(Net.T.ParallelSpawn, {
		car = car,
		side = side,
		duration = duration,
		seed = ctx.rng:NextInteger(1, 1e9),
	})

	task.delay(duration, function()
		if manifest and manifest.car == car and os.clock() >= manifest.endsAt then
			manifest = nil
		end
	end)
end

function Parallel.stop()
	manifest = nil
end

return Parallel
