--[[
	Inspector.luau
	Three bells, then he boards ahead and walks the train rearward,
	lantern swinging. Be SEATED with a ticket and he punches it and moves
	on. Hide and pray his patience holds (it holds less each visit).
	Stand in the open with empty pockets and pay the other kind of fare.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Forge = require(Shared.Forge)
local Palette = require(Shared.Palette)
local SoundBank = require(Shared.SoundBank)
local Util = require(Shared.Util)

local Inspector = {}
local ctx

local E = Config.Entities.Inspector
local T = Config.Train

local active = false

function Inspector.init(c)
	ctx = c
end

function Inspector.isActive()
	return active
end

local function buildInspectorRig()
	local rig = ctx.EntityUtil.buildBiped({
		name = "Inspector",
		height = 7.6,
		coat = Palette.InspectorCoat,
		skin = Palette.InspectorSkin,
		glowEyes = false,
		headTilt = -7,
	})
	rig.model:SetAttribute("EntityKind", "Inspector")
	local u = rig.unit
	-- conductor's cap
	local cap = Forge.part({
		parent = rig.model, name = "Cap",
		size = Vector3.new(1.05 * u, 0.28 * u, 1.05 * u),
		color = Palette.InspectorCoat, material = Enum.Material.Fabric, cancollide = false,
	})
	local brim = Forge.part({
		parent = rig.model, name = "Brim",
		size = Vector3.new(1.15 * u, 0.08 * u, 0.5 * u),
		color = Color3.fromRGB(16, 14, 16), material = Enum.Material.SmoothPlastic, cancollide = false,
	})
	-- brass buttons
	local buttons = {}
	for k = 1, 3 do
		buttons[k] = Forge.part({
			parent = rig.model, name = "Button",
			size = Vector3.new(0.14 * u, 0.14 * u, 0.06 * u),
			color = Palette.Brass, material = Enum.Material.Neon, cancollide = false, castshadow = false,
		})
	end
	-- the lantern
	local lantern = Forge.part({
		parent = rig.model, name = "Lantern",
		size = Vector3.new(0.5 * u, 0.7 * u, 0.5 * u),
		color = Palette.Brass, material = Enum.Material.Metal, cancollide = false,
	})
	local lanternGlass = Forge.part({
		parent = rig.model, name = "LanternGlass",
		size = Vector3.new(0.36 * u, 0.4 * u, 0.36 * u),
		color = Palette.InspectorLantern, material = Enum.Material.Neon, cancollide = false, castshadow = false,
	})
	Forge.light(lanternGlass, { color = Palette.InspectorLantern, range = 16, brightness = 1.9, shadows = true })

	local baseSetCF = rig.setCF
	rig.setCF = function(pelvisCF, dt, moveSpeed)
		baseSetCF(pelvisCF, dt, moveSpeed)
		cap.CFrame = rig.head.CFrame * CFrame.new(0, 0.62 * u, 0)
		brim.CFrame = rig.head.CFrame * CFrame.new(0, 0.46 * u, -0.5 * u)
		for k, button in ipairs(buttons) do
			button.CFrame = rig.torso.CFrame * CFrame.new(0, (0.9 - k * 0.55) * u, -0.58 * u)
		end
		local sway = math.sin(os.clock() * 2.2) * 0.35
		lantern.CFrame = rig.limbs.ArmR.CFrame * CFrame.new(0, -1.35 * u, 0) * CFrame.Angles(sway, 0, 0) * CFrame.new(0, -0.35 * u, 0)
		lanternGlass.CFrame = lantern.CFrame
	end
	return rig
end

----------------------------------------------------------------
-- Judgement
----------------------------------------------------------------
local function isSeated(player)
	local char, hum = Util.aliveCharacter(player)
	if not char or not hum then
		return false
	end
	return hum.Sit and hum.SeatPart ~= nil
end

local function fine(player, visitIndex, why)
	local taken = ctx.EconomyService.fine(player, E.FineFraction)
	local tiers = E.DamageByVisit
	local damage = (tiers and tiers[math.min(visitIndex or #tiers, #tiers)]) or E.Damage
	ctx.PlayerService.damage(player, damage, "inspector")
	SoundBank.play("InspectorFine", ctx.TrainBuilder.carPosition(player:GetAttribute("CarIndex") or 1))
	local msg = why or "No ticket. The fine is taken out of you."
	if taken > 0 then
		msg = msg .. (" (-%d fare)"):format(taken)
	end
	Net.fireClient(player, Net.T.Subtitle, { text = msg, seconds = 5 })
end

local function judge(player, visitIndex, punched)
	if player:GetAttribute("Ghost") then
		return
	end
	if player:GetAttribute("Downed") then
		Net.fireClient(player, Net.T.Subtitle, { text = "He steps over you. 'Sleeping berth surcharge,' he mutters, and takes nothing.", seconds = 4 })
		return
	end
	local char, _, root = Util.aliveCharacter(player)
	if not char then
		return
	end
	if ctx.TrainBuilder.isOnRoof(root.Position) then
		return
	end

	local hiddenSpot = player:GetAttribute("HiddenSpot")
	if hiddenSpot ~= nil and hiddenSpot ~= "" then
		local strict = E.StrictChance[math.min(visitIndex, #E.StrictChance)] or 0
		if ctx.rng:NextNumber() < strict then
			ctx.HideSystem.eject(player)
			SoundBank.play("InspectorHmph", root)
			fine(player, visitIndex, "Dragged out by the collar. Hiding from the railway is a second offense.")
		end
		return
	end

	if isSeated(player) then
		if ctx.ItemService.consumeItem(player, "Ticket") then
			punched[player] = true
			SoundBank.play("InspectorPunch", root)
			Net.fireClient(player, Net.T.Subtitle, { text = "He punches your ticket. The holes spell something you decide not to read.", seconds = 4 })
		else
			fine(player, visitIndex, "Seated, but ticketless. The railway is not a charity.")
		end
		return
	end

	fine(player, visitIndex)
end

----------------------------------------------------------------
-- The walk
----------------------------------------------------------------
function Inspector.start(visitIndex)
	if active then
		return
	end
	active = true

	Net.fireAll(Net.T.InspectorState, { phase = "warn", seconds = E.WarnSeconds })
	Net.fireAll(Net.T.Announce, {
		title = "TICKET INSPECTION",
		sub = "Be seated. Tickets in hand. He walks from the front.",
		seconds = 6, tone = "warn",
	})
	SoundBank.play("InspectorBell", ctx.TrainBuilder.carPosition(math.min((select(2, ctx.EntityUtil.occupiedRange()) or 1) + 1, T.Cars)))
	task.wait(E.WarnSeconds)

	if ctx.GameLoop.state() ~= "Journey" and ctx.GameLoop.state() ~= "Station" then
		active = false
		return
	end

	local minCar, maxCar = ctx.EntityUtil.occupiedRange()
	minCar = minCar or 1
	maxCar = maxCar or 1
	local startCar = math.min(maxCar + 1, T.Cars)
	ctx.TrainBuilder.buildCar(startCar)
	local endCar = math.max(minCar - 1, ctx.TrainBuilder.rearMostBuilt())

	Net.fireAll(Net.T.InspectorState, { phase = "walk" })
	local rig = buildInspectorRig()
	local judged = {}
	local punched = {}
	local judging = false

	local startX = (startCar - 1) * T.CarPitch + T.CarLength - 4
	local endX = (endCar - 1) * T.CarPitch + 4
	local lastBoundary = nil

	local result = ctx.EntityUtil.walkAisle(rig, startX, endX, E.WalkSpeed, function(x)
		if not active or not rig.model.Parent then
			return "stop"
		end
		-- doors open themselves a car ahead of him
		local boundary = math.floor((x - 6) / T.CarPitch) + 1
		if boundary ~= lastBoundary and boundary >= 1 and boundary < T.Cars then
			lastBoundary = boundary
			ctx.DoorSystem.forceOpen(boundary, false)
			ctx.DoorSystem.forceOpen(boundary - 1, false)
		end

		if judging then
			return true
		end
		-- look for the next soul beside him
		local carHere = math.floor(x / T.CarPitch) + 1
		for _, player in ipairs(ctx.EntityUtil.playersInCar(carHere, true)) do
			if not judged[player] then
				local char, _, root = Util.aliveCharacter(player)
				if char and math.abs(root.Position.X - x) < 3.6 then
					judged[player] = true
					judging = true
					task.spawn(function()
						task.wait(E.PauseSeconds)
						judge(player, visitIndex, punched)
						task.wait(0.4)
						judging = false
					end)
					return true
				end
			end
		end
		return false
	end)

	-- fade him out
	if rig.model.Parent then
		for _, part in ipairs(rig.model:GetDescendants()) do
			if part:IsA("BasePart") then
				local tween = game:GetService("TweenService"):Create(part, TweenInfo.new(2), { Transparency = 1 })
				tween:Play()
			elseif part:IsA("Light") then
				part.Enabled = false
			end
		end
		task.delay(2.2, function()
			rig.destroy()
		end)
	end

	if result == "arrived" then
		Net.fireAll(Net.T.Subtitle, { text = "The Inspector steps through the rear door, into a car that is not there.", seconds = 5 })
	end
	Net.fireAll(Net.T.InspectorState, { phase = "done" })
	active = false
end

function Inspector.stop()
	active = false
end

return Inspector
