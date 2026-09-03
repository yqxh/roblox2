--[[
	DoorSystem.luau
	The gangways between cars: sliding doors (free, jammed, locked),
	station-side doors, roof hatches, and the blind toggles.

	Boundary i sits between car i and car i+1, occupying the 4-stud gap.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Forge = require(Shared.Forge)
local Palette = require(Shared.Palette)
local Tags = require(Shared.Tags)
local SoundBank = require(Shared.SoundBank)
local Net = require(Shared.Net)

local DoorSystem = {}
local ctx
local boundaries = {} -- [i] = state

local T = Config.Train
local M = Palette.M
local FLOOR = T.FloorY
local CEIL = FLOOR + T.CarHeight

local OPEN_Z = -3.6
local AUTO_CLOSE = 8

function DoorSystem.init(c)
	ctx = c
end

local function isOpenArchetype(entry)
	return entry and (entry.archetype == "flatcar" or entry.archetype == "tender")
end

----------------------------------------------------------------
-- Door motion
----------------------------------------------------------------
local function slideDoor(b, open, seconds, silent)
	if not b.door or b.open == open then
		return
	end
	b.open = open
	local target = b.doorClosedCF * CFrame.new(0, 0, open and OPEN_Z or 0)
	local tween = TweenService:Create(b.door, TweenInfo.new(seconds or 0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = target })
	tween:Play()
	if not silent then
		SoundBank.play("DoorSlide", b.door)
	end
	if b.prompt then
		b.prompt.ActionText = open and "Slide shut" or "Slide open"
	end
	if open then
		-- make sure there is somewhere to walk into
		ctx.TrainBuilder.buildCar(math.min(b.index + 1, T.Cars))
		if b.autoClose then
			task.cancel(b.autoClose)
		end
		b.autoClose = task.delay(AUTO_CLOSE, function()
			b.autoClose = nil
			if b.open and b.state ~= "sealed" then
				slideDoor(b, false, 1.4, true)
			end
		end)
	end
end

local function markDoorFree(b)
	b.state = "free"
	if b.prompt then
		b.prompt.ActionText = "Slide open"
		b.prompt.ObjectText = "Door"
		b.prompt.HoldDuration = Config.Interact.Door
	end
end

function DoorSystem.forceOpen(i, bang)
	local b = boundaries[i]
	if not b or b.state == "sealed" then
		return
	end
	if b.state ~= "free" then
		markDoorFree(b) -- what the Furnace opens stays honest afterwards
	end
	slideDoor(b, true, bang and 0.15 or 0.5, bang)
	if bang and b.door then
		SoundBank.play("DoorSlam", b.door)
	end
end

function DoorSystem.sealRearOf(car)
	local b = boundaries[car - 1]
	if not b then
		return
	end
	b.state = "sealed"
	if b.autoClose then
		task.cancel(b.autoClose)
		b.autoClose = nil
	end
	if b.door then
		b.open = true -- force the slide
		slideDoor(b, false, 0.4, true)
	end
	if b.prompt then
		b.prompt.Enabled = false
	end
end

----------------------------------------------------------------
-- Character elevator for roof hatches
----------------------------------------------------------------
local climbing = {}
local function climbThrough(player, fromCF, toCF)
	if climbing[player] then
		return
	end
	local char, hum, root = ctx.util.aliveCharacter(player)
	if not char or player:GetAttribute("HiddenSpot") ~= nil and player:GetAttribute("HiddenSpot") ~= "" then
		return
	end
	climbing[player] = true
	root.Anchored = true
	root.CFrame = fromCF
	local steps = 14
	task.spawn(function()
		for k = 1, steps do
			if not root.Parent then
				break
			end
			root.CFrame = fromCF:Lerp(toCF, k / steps)
			task.wait(0.045)
		end
		if root.Parent then
			root.Anchored = false
		end
		climbing[player] = nil
		if hum then
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
	SoundBank.play("HatchOpen", root)
end

----------------------------------------------------------------
-- Boundary construction
----------------------------------------------------------------
function DoorSystem.buildBoundary(i, entryThis, entryNext)
	if boundaries[i] then
		return
	end
	local xc = i * T.CarPitch - 2 -- center of the gap
	local model = Forge.model(("Gangway_%02d"):format(i), ctx.folders.train)
	local b = {
		index = i,
		model = model,
		state = entryThis.doorState or "free",
		open = false,
		bashes = 0,
	}
	boundaries[i] = b

	local openStyle = isOpenArchetype(entryThis) or isOpenArchetype(entryNext)

	-- Floor plate
	Forge.part({
		parent = model, name = "Plate",
		size = Vector3.new(4.6, 0.8, 8),
		cf = CFrame.new(xc, FLOOR - 0.4, 0),
		color = Color3.fromRGB(48, 48, 52), material = M.DiamondPlate,
	})

	if openStyle then
		-- open-air crossing: railings only
		for _, side in ipairs({ -1, 1 }) do
			Forge.part({
				parent = model, name = "Rail",
				size = Vector3.new(4.6, 0.25, 0.25),
				cf = CFrame.new(xc, FLOOR + 1.6, side * 3.9),
				color = Color3.fromRGB(60, 60, 64), material = M.Metal,
			})
			Forge.part({
				parent = model, name = "RailPost",
				size = Vector3.new(0.25, 1.6, 0.25),
				cf = CFrame.new(xc, FLOOR + 0.8, side * 3.9),
				color = Color3.fromRGB(60, 60, 64), material = M.Metal,
			})
		end
	else
		-- accordion gangway: five-ring pleat, alternating profile so the
		-- bellows read as folded canvas instead of a tube
		for k = -2, 2 do
			local even = k % 2 == 0
			Forge.ring({
				parent = model, name = "Bellows",
				width = even and 8.8 or 8.2, height = even and 8.6 or 8.0,
				thick = 0.45, depth = 0.45,
				cf = CFrame.new(xc + k * 0.8, FLOOR + 4.4, 0) * CFrame.Angles(0, math.rad(90), 0),
				color = even and Color3.fromRGB(24, 24, 26) or Color3.fromRGB(36, 34, 37),
				material = M.Fabric,
			})
		end
		-- canvas hood bridging the two cars' eaves lines
		Forge.part({
			parent = model, name = "GangHood",
			size = Vector3.new(3.4, 0.4, 7.0),
			cf = CFrame.new(xc, 19.0, 0),
			color = Color3.fromRGB(24, 24, 26), material = M.Fabric,
			cancollide = false, canquery = false,
		})
		-- diaphragm striker plates at the bellows shoulders, riding the -X
		-- door frame: clear of the doorway, and of the door's +X open pocket
		for _, side in ipairs({ -1, 1 }) do
			Forge.part({
				parent = model, name = "Diaphragm",
				size = Vector3.new(0.25, 7.8, 1.1),
				cf = CFrame.new(xc - 1.7, 14.1, side * 4.05),
				color = Color3.fromRGB(30, 30, 33), material = M.Metal,
				cancollide = false, canquery = false, castshadow = false,
			})
		end
		-- side walls with station doors
		b.sideDoors = {}
		for _, side in ipairs({ -1, 1 }) do
			Forge.part({
				parent = model, name = "SideHeader",
				size = Vector3.new(4.6, 1.7, 0.5),
				cf = CFrame.new(xc, FLOOR + 7.5, side * 4),
				color = Color3.fromRGB(30, 34, 32), material = M.Wood,
			})
			local door = Forge.part({
				parent = model, name = "SideDoor",
				size = Vector3.new(2.8, 6.6, 0.4),
				cf = CFrame.new(xc, FLOOR + 3.3, side * 4),
				color = Palette.CarBodyAlt, material = M.Wood,
			})
			door.CollisionGroup = "Door"
			Forge.part({ -- little window in the door
				parent = model, name = "SideDoorGlass",
				size = Vector3.new(1.4, 1.6, 0.15),
				cf = door.CFrame * CFrame.new(0, 1.6, side * -0.15),
				color = Palette.GlassNight, material = M.Glass, transparency = 0.4, cancollide = false,
			})
			for _, fx in ipairs({ -1.95, 1.95 }) do
				Forge.part({
					parent = model, name = "SideFrame",
					size = Vector3.new(0.9, 6.6, 0.5),
					cf = CFrame.new(xc + fx, FLOOR + 3.3, side * 4),
					color = Color3.fromRGB(30, 34, 32), material = M.Wood,
				})
			end
			b.sideDoors[side] = { door = door, closedCF = door.CFrame, open = false }
		end
		-- ceiling + hatch
		Forge.part({
			parent = model, name = "GangCeil",
			size = Vector3.new(4.6, 0.4, 8),
			cf = CFrame.new(xc, CEIL - 0.6, 0),
			color = Color3.fromRGB(26, 26, 28), material = M.Metal,
		})
		local hatch = Forge.part({
			parent = model, name = "Hatch",
			size = Vector3.new(2.4, 0.25, 2.4),
			cf = CFrame.new(xc, CEIL - 0.35, 0),
			color = Color3.fromRGB(40, 40, 44), material = M.DiamondPlate,
		})
		local rungs = Forge.truss({
			parent = model, name = "Rungs",
			size = Vector3.new(2, T.CarHeight - 2, 2),
			cf = CFrame.new(xc, FLOOR + (T.CarHeight - 2) / 2, 2.9),
			color = Color3.fromRGB(56, 56, 60), material = M.Metal,
			cancollide = false,
		})
		rungs.Transparency = 0.25

		local upCF = CFrame.new(xc, CEIL + 2.6, 0)
		local downCF = CFrame.new(xc, FLOOR + 3, 0)
		local upPrompt = Forge.prompt(hatch, {
			action = "Climb to the roof",
			object = "Hatch",
			hold = Config.Interact.RoofClimb,
			distance = 8,
			id = ("hatchup:%d"):format(i),
			tag = Tags.RoofHatch,
		})
		upPrompt.Triggered:Connect(function(player)
			climbThrough(player, downCF, upCF)
		end)
		-- a marker part on the roof for the way down
		local roofMark = Forge.part({
			parent = model, name = "RoofMark",
			size = Vector3.new(2.4, 0.3, 2.4),
			cf = CFrame.new(xc, CEIL + 1.35, 0),
			color = Color3.fromRGB(50, 50, 54), material = M.DiamondPlate,
		})
		local downPrompt = Forge.prompt(roofMark, {
			action = "Climb down",
			object = "Hatch",
			hold = Config.Interact.RoofClimb,
			distance = 8,
			id = ("hatchdown:%d"):format(i),
			tag = Tags.RoofHatch,
		})
		downPrompt.Triggered:Connect(function(player)
			climbThrough(player, upCF, downCF)
		end)
	end

	-- The main sliding door (skip when both sides are open-air).
	-- Against an open car it sits flush on the enclosed car's end wall
	-- instead of floating mid-gap.
	if not (isOpenArchetype(entryThis) and isOpenArchetype(entryNext)) then
		local doorX = xc
		if isOpenArchetype(entryNext) then
			doorX = xc - 1.45
		elseif isOpenArchetype(entryThis) then
			doorX = xc + 1.45
		end
		local door = Forge.part({
			parent = model, name = "SlideDoor",
			size = Vector3.new(0.5, 7, 3.8),
			cf = CFrame.new(doorX, FLOOR + 3.5, 0),
			color = Palette.WallPanel, material = M.Wood,
		})
		door.CollisionGroup = "Door"
		Forge.part({
			parent = model, name = "DoorGlass",
			size = Vector3.new(0.2, 1.8, 1.6),
			cf = door.CFrame * CFrame.new(0, 1.8, 0),
			color = Palette.GlassNight, material = M.Glass, transparency = 0.35, cancollide = false,
		})
		b.door = door
		b.doorClosedCF = door.CFrame
		local prompt = Forge.prompt(door, {
			action = b.state == "locked" and "Unlock" or (b.state == "jammed" and "Shoulder it" or "Slide open"),
			object = b.state == "locked" and "Locked door" or (b.state == "jammed" and "Jammed door" or "Door"),
			hold = b.state == "jammed" and 1.2 or Config.Interact.Door,
			distance = 7,
			id = ("door:%d"):format(i),
			tag = Tags.DoorSlide,
		})
		b.prompt = prompt
		CollectionService:AddTag(door, Tags.DoorSlide)
		prompt.Triggered:Connect(function(player)
			DoorSystem.onDoorTriggered(b, player)
		end)
	end

	return b
end

function DoorSystem.onDoorTriggered(b, player)
	local char, _, root = ctx.util.aliveCharacter(player)
	if not char or player:GetAttribute("Ghost") or player:GetAttribute("Downed") then
		return
	end
	if b.state == "sealed" then
		return
	end
	if b.state == "free" then
		slideDoor(b, not b.open)
		return
	end
	if b.state == "locked" then
		if ctx.ItemService.consumeItem(player, "BrassKey") then
			b.state = "free"
			b.prompt.ActionText = "Slide open"
			b.prompt.ObjectText = "Door"
			b.prompt.HoldDuration = Config.Interact.Door
			SoundBank.play("LatchOpen", b.door)
			Net.fireClient(player, Net.T.Toast, { text = "The brass key turns once, then crumbles.", tone = "good" })
			slideDoor(b, true)
		elseif char:FindFirstChild("Prybar") then
			-- no key? the lock loses the argument, loudly (anti-softlock)
			b.bashes += 1
			SoundBank.play("PryCreak", b.door, { pitchScale = 0.7 })
			ctx.signals.noiseEvent:fire(player, Config.Noise.Bash, b.door.Position)
			if b.bashes >= 3 then
				b.state = "free"
				b.prompt.ActionText = "Slide open"
				b.prompt.ObjectText = "Door"
				b.prompt.HoldDuration = Config.Interact.Door
				slideDoor(b, true, 0.3)
				Net.fireClient(player, Net.T.Toast, { text = "The lock tears out of the wood. Everything heard that.", tone = "warn" })
			else
				Net.fireClient(player, Net.T.Toast, { text = ("The lock groans. (%d/3)"):format(b.bashes), tone = "warn" })
			end
		else
			SoundBank.play("UiDeny", b.door)
			Net.fireClient(player, Net.T.Toast, { text = "Locked. A brass key would be polite. A pry bar would be effective.", tone = "warn" })
		end
		return
	end
	if b.state == "jammed" then
		local hasPry = char:FindFirstChild("Prybar") ~= nil
		if hasPry then
			b.state = "free"
			SoundBank.play("PryCreak", b.door)
			ctx.signals.noiseEvent:fire(player, Config.Noise.Pry, b.door.Position)
			Net.fireClient(player, Net.T.Toast, { text = "The pry bar convinces it.", tone = "good" })
			b.prompt.ActionText = "Slide open"
			b.prompt.ObjectText = "Door"
			b.prompt.HoldDuration = Config.Interact.Door
			slideDoor(b, true)
		else
			b.bashes += 1
			SoundBank.play("DoorBash", b.door)
			ctx.signals.noiseEvent:fire(player, Config.Noise.Bash, b.door.Position)
			if b.bashes >= 3 then
				b.state = "free"
				b.prompt.ActionText = "Slide open"
				b.prompt.ObjectText = "Door"
				b.prompt.HoldDuration = Config.Interact.Door
				slideDoor(b, true, 0.3)
				Net.fireClient(player, Net.T.Toast, { text = "It gives way. Everything heard that.", tone = "warn" })
			else
				Net.fireClient(player, Net.T.Toast, { text = ("Braced shut. (%d/3)"):format(b.bashes), tone = "warn" })
			end
		end
	end
end

----------------------------------------------------------------
-- Station side doors
----------------------------------------------------------------
function DoorSystem.setSideDoors(fromCar, toCar, side, open)
	for i = fromCar, toCar do
		local b = boundaries[i]
		if b and b.sideDoors then
			local sd = b.sideDoors[side]
			if sd and sd.open ~= open then
				sd.open = open
				local target = sd.closedCF * CFrame.new(open and 2.7 or 0, 0, 0)
				TweenService:Create(sd.door, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { CFrame = target }):Play()
				SoundBank.play("DoorSlide", sd.door)
			end
		end
	end
end

----------------------------------------------------------------
-- Blinds (window models come from CarPlans; TrainBuilder routes here)
----------------------------------------------------------------
function DoorSystem.wireCar(_, meta)
	for _, winData in ipairs(meta.windows or {}) do
		local prompt = winData.glass:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				if player:GetAttribute("Ghost") then
					return
				end
				DoorSystem.toggleBlind(winData)
			end)
		end
	end
end

function DoorSystem.toggleBlind(winData)
	local model = winData.model
	local down = not model:GetAttribute("BlindDown")
	model:SetAttribute("BlindDown", down)
	local blind = winData.blind
	local side = winData.side
	local targetSize = down and Vector3.new(blind.Size.X, 3.4, 0.15) or Vector3.new(blind.Size.X, 0.6, 0.15)
	local targetCF = down
		and CFrame.new(winData.x, 14.9, side * (T.CarWidth / 2 - 0.55))
		or CFrame.new(winData.x, 16.25, side * (T.CarWidth / 2 - 0.55))
	TweenService:Create(blind, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Size = targetSize, CFrame = targetCF }):Play()
	SoundBank.play("BlindPull", blind)
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------
function DoorSystem.destroyBoundary(i)
	local b = boundaries[i]
	if b then
		if b.autoClose then
			task.cancel(b.autoClose)
		end
		boundaries[i] = nil
		if b.model then
			b.model:Destroy()
		end
	end
end

function DoorSystem.getBoundary(i)
	return boundaries[i]
end

function DoorSystem.teardown()
	for i in pairs(boundaries) do
		DoorSystem.destroyBoundary(i)
	end
	boundaries = {}
end

return DoorSystem
