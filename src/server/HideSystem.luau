--[[
	HideSystem.luau
	Tuck-away spots: under benches, in lockers, beneath tarps. Prompt-based
	(reliable on every device), one occupant per spot. Entities ask this
	module who is out in the open.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local SoundBank = require(Shared.SoundBank)
local Config = require(Shared.Config)

local HideSystem = {}
local ctx

local spots = {}        -- spotId -> {id, vol, prompt, occupant, carIndex}
local hiddenBy = {}     -- player -> spotId

function HideSystem.init(c)
	ctx = c
end

local function exitCFFor(vol)
	local pos = vol.Position
	local zdir = pos.Z >= 0 and -1 or 1
	if math.abs(pos.Z) < 1 then
		zdir = 1
	end
	local out = Vector3.new(pos.X, Config.Train.FloorY + 3, pos.Z + zdir * (vol.Size.Z / 2 + 1.2))
	return CFrame.new(out, Vector3.new(pos.X, out.Y, 0))
end

function HideSystem.exit(player, quiet)
	local spotId = hiddenBy[player]
	if not spotId then
		return
	end
	local spot = spots[spotId]
	hiddenBy[player] = nil
	player:SetAttribute("HiddenSpot", "")
	if spot then
		spot.occupant = nil
		if spot.prompt then
			spot.prompt.ActionText = spot.label or "Hide"
		end
	end
	local char, hum, root = ctx.util.aliveCharacter(player)
	if char and root then
		root.Anchored = false
		if spot then
			root.CFrame = exitCFFor(spot.vol)
		end
		if hum then
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
	Net.fireClient(player, Net.T.HideState, { hidden = false })
	if not quiet and spot then
		SoundBank.play("Rummage", spot.vol)
	end
end

local function enter(player, spot)
	local char, _, root = ctx.util.aliveCharacter(player)
	if not char or player:GetAttribute("Ghost") or player:GetAttribute("Downed") then
		return
	end
	if spot.occupant then
		Net.fireClient(player, Net.T.Toast, { text = "Somebody thought of it first.", tone = "warn" })
		return
	end
	if hiddenBy[player] then
		HideSystem.exit(player, true)
	end
	spot.occupant = player
	hiddenBy[player] = spot.id
	player:SetAttribute("HiddenSpot", spot.id)
	local vol = spot.vol
	if vol.Size.Y < 2.2 then
		-- a crawl space: lie flat, face up, feet to the wall
		root.CFrame = CFrame.new(vol.Position)
			* CFrame.Angles(0, math.rad(vol.Position.Z >= 0 and 0 or 180), 0)
			* CFrame.Angles(math.rad(-90), 0, 0)
	else
		root.CFrame = CFrame.new(vol.Position) * CFrame.Angles(0, math.rad(vol.Position.Z >= 0 and 0 or 180), 0)
	end
	root.Anchored = true
	if spot.prompt then
		spot.prompt.ActionText = "Slip out"
	end
	Net.fireClient(player, Net.T.HideState, { hidden = true, spotId = spot.id, low = vol.Size.Y < 2.2 })
	SoundBank.play("Rummage", vol)
end

function HideSystem.registerCar(carIndex, meta)
	for _, data in ipairs(meta.hideSpots or {}) do
		local prompt = data.vol:FindFirstChildOfClass("ProximityPrompt")
		local spot = {
			id = data.id,
			vol = data.vol,
			prompt = prompt,
			label = data.label,
			occupant = nil,
			carIndex = carIndex,
		}
		spots[data.id] = spot
		if prompt then
			prompt.Triggered:Connect(function(player)
				if spot.occupant == player then
					HideSystem.exit(player)
				else
					enter(player, spot)
				end
			end)
		end
	end
end

function HideSystem.unregisterCar(carIndex)
	for id, spot in pairs(spots) do
		if spot.carIndex == carIndex then
			if spot.occupant then
				HideSystem.exit(spot.occupant, true)
			end
			spots[id] = nil
		end
	end
end

function HideSystem.isHidden(player)
	return hiddenBy[player] ~= nil
end

function HideSystem.eject(player)
	if hiddenBy[player] then
		HideSystem.exit(player)
	end
end

function HideSystem.spotOf(player)
	return hiddenBy[player] and spots[hiddenBy[player]] or nil
end

function HideSystem.start()
	Net.on(Net.T.ExitHide, function(player)
		HideSystem.exit(player)
	end)
end

return HideSystem
