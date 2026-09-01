--[[
	ScareDirector.luau
	The night's small lies. Personal, client-local, never damaging, and
	deliberately unshared — half the fun of co-op horror is "did anyone
	else see that?", and the honest answer here is always no.

	It stands down whenever something real is happening (Furnace warnings,
	inspections, tunnels), so ambient dread never dilutes a genuine tell.
	It also gives mimicked luggage its promised tell: stand close and the
	case breathes.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local SoundBank = require(Shared.SoundBank)
local Util = require(Shared.Util)
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local LightingDirector = require(script.Parent:WaitForChild("LightingDirector"))
local CameraFX = require(script.Parent:WaitForChild("CameraFX"))

local ScareDirector = {}

local S = Config.Scares

local suppressedUntil = 0 -- real events push ambient dread aside
local rng = Random.new(os.clock() * 1e4)

local function suppress(seconds)
	suppressedUntil = math.max(suppressedUntil, os.clock() + seconds)
end

local function eligible()
	return ClientState.runState == "Journey"
		and ClientState.carIndex >= S.FirstScareCar
		and not ClientState.inTunnel
		and not ClientState.hidden
		and not ClientState.isGhost()
		and not ClientState.isDowned()
		and os.clock() >= suppressedUntil
end

local function myCarModel()
	local train = workspace:FindFirstChild("Train")
	return train and train:FindFirstChild(("Car_%02d"):format(ClientState.carIndex))
end

----------------------------------------------------------------
-- The scares
----------------------------------------------------------------
local Scares = {}

-- A passenger, seated, facing away. Approach, or stare, and they never were.
function Scares.phantom()
	local car = myCarModel()
	local root = ClientState.localRoot()
	if not (car and root) then
		return false
	end
	local seats = {}
	for _, desc in ipairs(car:GetDescendants()) do
		if desc:IsA("Seat") and desc.Position.X > root.Position.X + 14 and not desc.Occupant then
			table.insert(seats, desc)
		end
	end
	if #seats == 0 then
		return false
	end
	local seat = seats[rng:NextInteger(1, #seats)]

	local figure = Instance.new("Model")
	figure.Name = "Passenger"
	local function blackPart(size, cf)
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CastShadow = true
		part.Size = size
		part.CFrame = cf
		part.Color = Color3.fromRGB(12, 11, 13)
		part.Material = Enum.Material.Fabric
		part.Parent = figure
		return part
	end
	local base = seat.CFrame * CFrame.new(0, 1.6, 0)
	blackPart(Vector3.new(1.6, 2.2, 0.9), base) -- hunched back
	blackPart(Vector3.new(0.8, 0.9, 0.8), base * CFrame.new(0, 1.5, 0.1) * CFrame.Angles(0.22, 0, 0)) -- bowed head
	figure.Parent = workspace

	task.spawn(function()
		local gazeAccum = 0
		local start = os.clock()
		while os.clock() - start < 22 and figure.Parent do
			local dt = task.wait(0.1)
			local myRoot = ClientState.localRoot()
			local cam = workspace.CurrentCamera
			if not (myRoot and cam) then
				break
			end
			local dist = (seat.Position - myRoot.Position).Magnitude
			local toIt = (base.Position - cam.CFrame.Position)
			local gazing = toIt.Magnitude > 1 and cam.CFrame.LookVector:Dot(toIt.Unit) > 0.86
			if gazing then
				gazeAccum += dt
			end
			if dist < 11 or gazeAccum > 1.4 then
				-- three guttering blinks, then no one
				for blink = 1, 3 do
					for _, part in ipairs(figure:GetChildren()) do
						part.Transparency = blink % 2 == 1 and 0.85 or 0.1
					end
					task.wait(0.06)
				end
				break
			end
		end
		if figure.Parent then
			figure:Destroy()
			SoundBank.play("ParallelWhisper", ClientState.localRoot(), { volumeScale = 0.5 })
		end
	end)
	return true
end

-- The gaslight forgets itself for a moment.
function Scares.stutter()
	LightingDirector.stormFor(rng:NextNumber(0.9, 1.6))
	return true
end

-- Someone very close behind you says nothing in particular.
function Scares.whisper()
	local root = ClientState.localRoot()
	local cam = workspace.CurrentCamera
	if not (root and cam) then
		return false
	end
	local behind = root.Position - cam.CFrame.LookVector * 4 + Vector3.new(0, 1, 0)
	SoundBank.play("ParallelWhisper", behind, { volumeScale = 0.85, max = 30 })
	return true
end

-- Something without temperature moves through you.
function Scares.coldpass()
	LightingDirector.coldPulse()
	CameraFX.addTrauma(0.1)
	SoundBank.play("Breath", nil, { volumeScale = 1.4, pitchScale = 0.8 })
	return true
end

-- The door ahead opens a hand's width. Nothing comes through.
function Scares.doorcreak()
	local train = workspace:FindFirstChild("Train")
	if not train then
		return false
	end
	local gangway = train:FindFirstChild(("Gangway_%02d"):format(ClientState.carIndex))
	local door = gangway and gangway:FindFirstChild("SlideDoor")
	if not door then
		return false
	end
	local original = door.CFrame
	local creaked = original * CFrame.new(0, 0, -0.55)
	SoundBank.play("PryCreak", door, { volumeScale = 0.45, pitchScale = 0.7 })
	TweenService:Create(door, TweenInfo.new(1.4, Enum.EasingStyle.Sine), { CFrame = creaked }):Play()
	task.delay(3.5, function()
		-- only ease it back if nobody actually opened it in the meantime
		if door.Parent and (door.CFrame.Position - creaked.Position).Magnitude < 0.7 then
			TweenService:Create(door, TweenInfo.new(0.8), { CFrame = original }):Play()
		end
	end)
	return true
end

----------------------------------------------------------------
-- Scheduler
----------------------------------------------------------------
local function pickScare()
	local options = {}
	for name, weight in pairs(S.Weights) do
		table.insert(options, { weight = weight, value = name })
	end
	return Util.weightedPick(rng, options)
end

local function schedulerLoop()
	task.wait(rng:NextNumber(20, 40)) -- let the first cars breathe
	while true do
		task.wait(rng:NextNumber(S.MinGapSeconds, S.MaxGapSeconds))
		if eligible() then
			local name = pickScare()
			local fn = Scares[name]
			if fn then
				local ok, fired = pcall(fn)
				if not (ok and fired) then
					-- this one didn't land (no seats, no door); try again sooner
					task.wait(8)
				end
			end
		end
	end
end

----------------------------------------------------------------
-- The mimic's tell: uneasy luggage breathes when you stand close
----------------------------------------------------------------
local shivering = {}
local lastBreath = 0

local function mimicTellLoop()
	while true do
		task.wait(0.35)
		local root = ClientState.localRoot()
		if not root or ClientState.isGhost() then
			continue
		end
		local car = myCarModel()
		if not car then
			continue
		end
		for _, desc in ipairs(car:GetDescendants()) do
			if desc:IsA("BasePart") and desc:GetAttribute("Uneasy") then
				local dist = (desc.Position - root.Position).Magnitude
				if dist < S.MimicBreathRange then
					if os.clock() - lastBreath > 2.6 then
						lastBreath = os.clock()
						SoundBank.play("Breath", desc, { volumeScale = 0.9, pitchScale = 0.62, max = S.MimicBreathRange + 4 })
					end
					if not shivering[desc] then
						shivering[desc] = true
						task.spawn(function()
							local origin = desc.CFrame
							for _ = 1, 6 do
								if not desc.Parent then
									break
								end
								desc.CFrame = origin * CFrame.Angles(0, 0, (rng:NextNumber() - 0.5) * 0.025)
								task.wait(0.05)
							end
							if desc.Parent then
								desc.CFrame = origin
							end
							task.wait(1.2)
							shivering[desc] = nil
						end)
					end
				end
			end
		end
	end
end

----------------------------------------------------------------
-- Start
----------------------------------------------------------------
function ScareDirector.start()
	-- real events own the room
	Net.on(Net.T.FurnaceWarn, function(data)
		suppress((data.eta or 6) + 20)
	end)
	Net.on(Net.T.InspectorState, function(data)
		if data.phase == "warn" then
			suppress((data.seconds or 25) + 45)
		end
	end)
	Net.on(Net.T.ParallelSpawn, function(data)
		suppress((data.duration or 25) + 10)
	end)
	Net.on(Net.T.Damage, function()
		suppress(18)
	end)
	ClientState.signals.tunnelChanged:connect(function(active)
		if active then
			suppress(12)
		end
	end)

	task.spawn(schedulerLoop)
	task.spawn(mimicTellLoop)
end

return ScareDirector
