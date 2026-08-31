--[[
	Util.luau
	Small helpers shared everywhere: cleanup maids, tween shorthand,
	character lookups, math, formatting.
]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Util = {}

----------------------------------------------------------------
-- Maid: collects connections/instances/functions, cleans in one call
----------------------------------------------------------------
local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ _tasks = {} }, Maid)
end

function Maid:give(job)
	if job ~= nil then
		table.insert(self._tasks, job)
	end
	return job
end

function Maid:clean()
	local tasks = self._tasks
	self._tasks = {}
	for i = #tasks, 1, -1 do
		local job = tasks[i]
		local jobType = typeof(job)
		if jobType == "RBXScriptConnection" then
			job:Disconnect()
		elseif jobType == "Instance" then
			job:Destroy()
		elseif jobType == "function" then
			task.spawn(job)
		elseif jobType == "table" and job.clean then
			job:clean()
		elseif jobType == "thread" then
			task.cancel(job)
		end
	end
end

Util.Maid = Maid

----------------------------------------------------------------
-- Signal: lightweight connect/fire, no Instance allocation
----------------------------------------------------------------
local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _fns = {} }, Signal)
end

function Signal:connect(fn)
	table.insert(self._fns, fn)
	local connected = true
	return {
		Disconnect = function()
			if connected then
				connected = false
				local i = table.find(self._fns, fn)
				if i then
					table.remove(self._fns, i)
				end
			end
		end,
	}
end

function Signal:fire(...)
	for _, fn in ipairs(table.clone(self._fns)) do
		task.spawn(fn, ...)
	end
end

Util.Signal = Signal

----------------------------------------------------------------
-- Tweens
----------------------------------------------------------------
function Util.tween(instance, seconds, props, style, direction)
	local info = TweenInfo.new(
		seconds,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out
	)
	local tw = TweenService:Create(instance, info, props)
	tw:Play()
	return tw
end

----------------------------------------------------------------
-- Characters
----------------------------------------------------------------
function Util.rootOf(character)
	return character and character:FindFirstChild("HumanoidRootPart")
end

function Util.humanoidOf(character)
	return character and character:FindFirstChildOfClass("Humanoid")
end

function Util.aliveCharacter(player)
	local char = player.Character
	if not char then
		return nil
	end
	local hum = Util.humanoidOf(char)
	local root = Util.rootOf(char)
	if hum and root and hum.Health > 0 then
		return char, hum, root
	end
	return nil
end

-- Players currently in the run proper (not ghosts). alsoDowned=true includes downed riders.
function Util.livingPlayers(alsoDowned)
	local out = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if not player:GetAttribute("Ghost") then
			local char, hum = Util.aliveCharacter(player)
			if char and hum then
				if alsoDowned or not player:GetAttribute("Downed") then
					table.insert(out, player)
				end
			end
		end
	end
	return out
end

function Util.playerFromCharacter(character)
	return character and Players:GetPlayerFromCharacter(character)
end

function Util.playerFromHit(hit)
	local character = hit and hit.Parent
	if character and not character:FindFirstChildOfClass("Humanoid") then
		character = character.Parent
	end
	return Util.playerFromCharacter(character)
end

----------------------------------------------------------------
-- Cars <-> world positions (mirrors TrainBuilder's layout math)
----------------------------------------------------------------
function Util.carIndexAtX(x, carPitch)
	return math.floor(x / carPitch) + 1
end

function Util.carOriginX(index, carPitch)
	return (index - 1) * carPitch
end

----------------------------------------------------------------
-- Misc
----------------------------------------------------------------
function Util.lerp(a, b, t)
	return a + (b - a) * t
end

function Util.round(n, step)
	step = step or 1
	return math.floor(n / step + 0.5) * step
end

function Util.chance(rng, p)
	return rng:NextNumber() < p
end

function Util.pick(rng, list)
	return list[rng:NextInteger(1, #list)]
end

function Util.weightedPick(rng, options)
	-- options: { {weight = n, value = v}, ... }
	local total = 0
	for _, opt in ipairs(options) do
		total += opt.weight
	end
	local roll = rng:NextNumber() * total
	for _, opt in ipairs(options) do
		roll -= opt.weight
		if roll <= 0 then
			return opt.value
		end
	end
	return options[#options].value
end

function Util.formatClock(seconds)
	seconds = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Ordinal car names for flavor text: "CAR 07"
function Util.carLabel(index)
	return string.format("CAR %02d", index)
end

return Util
