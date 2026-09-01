--[[
	Stowaway.luau
	Some of the luggage packed itself. Opening it costs blood and one
	belonging, which the thing drags a car forward and drops — chase it
	or let it keep the toll. Observant riders notice marked cases
	breathing (the client whispers near them).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Forge = require(Shared.Forge)
local Palette = require(Shared.Palette)
local SoundBank = require(Shared.SoundBank)
local Util = require(Shared.Util)

local Stowaway = {}
local ctx

local E = Config.Entities.Stowaway
local T = Config.Train

function Stowaway.init(c)
	ctx = c
end

local function stealSomething(player)
	-- prefer a tool from the backpack, then the hands, then loose fare
	local candidates = {}
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, tool in ipairs(backpack:GetChildren()) do
			if tool:IsA("Tool") then
				table.insert(candidates, tool)
			end
		end
	end
	local char = player.Character
	if #candidates == 0 and char then
		for _, tool in ipairs(char:GetChildren()) do
			if tool:IsA("Tool") then
				table.insert(candidates, tool)
			end
		end
	end
	if #candidates > 0 then
		local tool = candidates[ctx.rng:NextInteger(1, #candidates)]
		local name = tool:GetAttribute("ItemName")
		tool:Destroy()
		return name
	end
	if (player:GetAttribute("Item_Ticket") or 0) > 0 then
		player:SetAttribute("Item_Ticket", player:GetAttribute("Item_Ticket") - 1)
		return "Ticket"
	end
	ctx.EconomyService.addFare(player, -12)
	return nil
end

function Stowaway.trigger(node, player)
	local part = node.part
	part:SetAttribute("Uneasy", nil) -- sprung: it has nothing left to hide
	local origin = part.CFrame

	-- the case blooms into teeth
	local rig = Forge.model("Stowaway", ctx.folders.entities)
	local maw = Forge.part({
		parent = rig, name = "Maw",
		size = Vector3.new(part.Size.X, 0.4, part.Size.Z),
		cf = origin * CFrame.new(0, part.Size.Y / 2 + 0.1, 0),
		color = Color3.fromRGB(20, 8, 10), material = Enum.Material.SmoothPlastic,
		cancollide = false,
	})
	for k = 1, 6 do
		local along = (k - 3.5) / 3.5
		Forge.wedge({
			parent = rig, name = "Tooth",
			size = Vector3.new(0.3, 0.8, 0.4),
			cf = origin * CFrame.new(along * part.Size.X * 0.4, part.Size.Y / 2 + 0.6, -part.Size.Z * 0.3),
			color = Color3.fromRGB(226, 218, 196), material = Enum.Material.SmoothPlastic,
			cancollide = false,
		})
		Forge.wedge({
			parent = rig, name = "Tooth",
			size = Vector3.new(0.3, 0.8, 0.4),
			cf = origin * CFrame.new(along * part.Size.X * 0.4, part.Size.Y / 2 + 0.6, part.Size.Z * 0.3)
				* CFrame.Angles(0, math.rad(180), 0),
			color = Color3.fromRGB(226, 218, 196), material = Enum.Material.SmoothPlastic,
			cancollide = false,
		})
	end
	local tongue = Forge.part({
		parent = rig, name = "Tongue",
		size = Vector3.new(0.5, 0.3, 1.8),
		cf = origin * CFrame.new(0, part.Size.Y / 2 + 0.4, 0),
		color = Color3.fromRGB(140, 40, 50), material = Enum.Material.SmoothPlastic,
		cancollide = false,
	})
	local eye = Forge.ball({
		parent = rig, name = "Eye",
		size = Vector3.new(0.4, 0.4, 0.4),
		cf = origin * CFrame.new(0, part.Size.Y / 2 + 0.9, 0),
		color = Palette.EyeShine, material = Enum.Material.Neon,
		cancollide = false, castshadow = false,
	})

	SoundBank.play("StowawayBite", part, { max = 140 })
	ctx.PlayerService.damage(player, E.Damage, "stowaway")
	ctx.signals.noiseEvent:fire(player, Config.Noise.DoorSlam, part.Position)

	local stolenName = stealSomething(player)
	local msgTail = stolenName
		and (" It took your %s up the train."):format(require(Shared.ItemDefs).get(stolenName).display)
		or " It took what it could shake loose."
	Net.fireClient(player, Net.T.Subtitle, { text = "The luggage bites back." .. msgTail, seconds = 5 })

	-- lunge animation, then it skitters forward and is gone
	TweenService:Create(tongue, TweenInfo.new(0.25, Enum.EasingStyle.Back), {
		CFrame = origin * CFrame.new(0, part.Size.Y / 2 + 0.5, -1.6),
	}):Play()
	task.delay(0.8, function()
		local dropCar = math.min((node.carIndex or 1) + 1, T.Cars)
		ctx.TrainBuilder.buildCar(dropCar)
		if stolenName then
			local dropX = (dropCar - 1) * T.CarPitch + ctx.rng:NextNumber(8, T.CarLength - 8)
			ctx.ItemService.spawnPickup(stolenName, Vector3.new(dropX, T.FloorY + 1, ctx.rng:NextNumber(-2, 2)))
		end
		for _, p in ipairs(rig:GetChildren()) do
			TweenService:Create(p, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		end
		SoundBank.play("Rummage", eye, { pitchScale = 1.6 })
		task.wait(0.6)
		rig:Destroy()
	end)
end

return Stowaway
