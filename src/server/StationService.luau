--[[
	StationService.luau
	The two stops on the line. A platform assembles beside the stopped
	train: lamps, vending machines, a scatter of freight, and a stationmaster
	nobody has ever seen. Ghosts become riders again here. When the whistle
	blows and the doors close, the platform — and anyone still on it —
	stays behind in the dark.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Forge = require(Shared.Forge)
local Palette = require(Shared.Palette)
local Tags = require(Shared.Tags)
local SoundBank = require(Shared.SoundBank)

local StationService = {}
local ctx

local M = Palette.M
local T = Config.Train
local FLOOR = T.FloorY

local current = nil -- {model, number, name}

function StationService.init(c)
	ctx = c
end

function StationService.approach(stationNumber)
	local name = ctx.plan.stationNames[stationNumber] or "SOMEWHERE"
	Net.fireAll(Net.T.StationState, { phase = "approach", name = name })
	Net.fireAll(Net.T.Subtitle, { text = ("Approaching %s. Mind the gap between you and the dark."):format(name), seconds = 6 })
	SoundBank.play("BrakeHiss", ctx.TrainBuilder.carPosition(Config.Run.StationCars[stationNumber]))
end

----------------------------------------------------------------
-- Platform construction
----------------------------------------------------------------
local VEND_STOCK = {
	{ item = "Bandage", label = "BANDAGES" },
	{ item = "Flare", label = "FLARES" },
	{ item = "Battery", label = "BATTERIES" },
	{ item = "Oil", label = "LAMP OIL" },
	{ item = "Tonic", label = "DR. VOSS'\nTONIC" },
	{ item = "Ticket", label = "TICKETS" },
}

local function buildMachine(model, cf, entry, stationNumber, index)
	local body = Forge.part({
		parent = model, name = "Vend_" .. entry.item,
		size = Vector3.new(2.2, 5.4, 1.8),
		cf = cf,
		color = entry.item == "Ticket" and Palette.CarBodyAlt or Color3.fromRGB(30, 44, 40),
		material = M.Metal,
	})
	local face = Forge.part({
		parent = model, name = "VendFace",
		size = Vector3.new(1.8, 2.2, 0.15),
		cf = cf * CFrame.new(0, 1.1, -0.95),
		color = Color3.fromRGB(16, 18, 20), material = M.Glass, transparency = 0.15, cancollide = false,
	})
	Forge.surfaceText(body, Enum.NormalId.Front, ("%s\n%d fare"):format(entry.label, Config.Economy.Prices[entry.item]), {
		color = Palette.UIPaper, font = Palette.FontHeader, pps = 40,
	})
	local lamp = Forge.part({
		parent = model, name = "VendLamp",
		size = Vector3.new(1.6, 0.25, 0.4),
		cf = cf * CFrame.new(0, 2.9, -0.75),
		color = Palette.LampGlass, material = M.Neon, cancollide = false,
	})
	Forge.light(lamp, { color = Palette.LampGlow, range = 7, brightness = 1.0, shadows = false })
	local machineId = ("st%d_m%d"):format(stationNumber, index)
	ctx.EconomyService.registerMachine(machineId, body, { [entry.item] = true })
	local prompt = Forge.prompt(body, {
		action = "Buy",
		object = entry.label:gsub("\n", " "),
		hold = Config.Interact.Vend,
		distance = 8,
		id = "vend:" .. entry.item,
		tag = Tags.VendingMachine,
	})
	prompt.Triggered:Connect(function(player)
		if not player:GetAttribute("Ghost") then
			ctx.EconomyService.requestBuy(player, entry.item, machineId)
		end
	end)
	face.Name = "VendFace"
	return body, machineId
end

local function buildPlatform(stationNumber, name)
	local stationCar = Config.Run.StationCars[stationNumber]
	local cx = ctx.TrainBuilder.carOriginX(stationCar) + T.CarLength / 2
	local zNear = T.CarWidth / 2 + 0.5
	local model = Forge.model("Station_" .. name, ctx.folders.station)
	CollectionService:AddTag(model, Tags.StationModel)

	-- ground + slab
	Forge.part({
		parent = model, name = "Ground",
		size = Vector3.new(360, 1, 200),
		cf = CFrame.new(cx, 5.4, 50),
		color = Palette.GroundNight, material = M.Ground,
	})
	Forge.part({
		parent = model, name = "Slab",
		size = Vector3.new(150, 1.2, 15),
		cf = CFrame.new(cx, FLOOR - 0.6, zNear + 7.5),
		color = Palette.Gravel, material = M.Concrete,
	})
	Forge.part({
		parent = model, name = "Edge",
		size = Vector3.new(150, 0.4, 1.2),
		cf = CFrame.new(cx, FLOOR, zNear + 0.6),
		color = Color3.fromRGB(200, 190, 170), material = M.Concrete,
	})
	for s = 1, 4 do
		Forge.part({
			parent = model, name = "Step",
			size = Vector3.new(12, 1.2, 2),
			cf = CFrame.new(cx - 40, FLOOR - 0.6 - s * 1.2, zNear + 14 + s),
			color = Palette.Gravel, material = M.Concrete,
		})
	end

	-- canopy
	for px = -60, 60, 30 do
		Forge.part({
			parent = model, name = "Column",
			size = Vector3.new(0.8, 9.4, 0.8),
			cf = CFrame.new(cx + px, FLOOR + 4.7, zNear + 11),
			color = Color3.fromRGB(40, 44, 48), material = M.Metal,
		})
	end
	Forge.part({
		parent = model, name = "Canopy",
		size = Vector3.new(140, 0.5, 10),
		cf = CFrame.new(cx, FLOOR + 9.6, zNear + 10),
		color = Palette.CarRoof, material = M.Slate,
	})

	-- name board
	local board = Forge.part({
		parent = model, name = "NameBoard",
		size = Vector3.new(18, 3, 0.6),
		cf = CFrame.new(cx, FLOOR + 6.4, zNear + 13),
		color = Color3.fromRGB(22, 24, 26), material = M.Wood,
	})
	Forge.surfaceText(board, Enum.NormalId.Front, name, {
		color = Palette.CarLetters, font = Palette.FontHeader, pps = 40,
	})

	-- lamps
	for px = -66, 66, 22 do
		Forge.part({
			parent = model, name = "LampPost",
			size = Vector3.new(0.5, 6.5, 0.5),
			cf = CFrame.new(cx + px, FLOOR + 3.25, zNear + 5.5),
			color = Color3.fromRGB(30, 32, 34), material = M.Metal,
		})
		local head = Forge.part({
			parent = model, name = "LampHead",
			size = Vector3.new(1, 1.2, 1),
			cf = CFrame.new(cx + px, FLOOR + 7, zNear + 5.5),
			color = Palette.LampGlass, material = M.Neon, cancollide = false,
		})
		Forge.light(head, { color = Palette.LampGlow, range = 13, brightness = 1.5, flicker = true, shadows = true })
	end

	-- vending row: unrotated, so the Front (-Z) faces sell toward the train
	for k, entry in ipairs(VEND_STOCK) do
		buildMachine(model, CFrame.new(cx - 36 + k * 9, FLOOR + 2.7, zNear + 12.6), entry, stationNumber, k)
	end

	-- freight scatter with a little loot
	local rng = ctx.rng
	local crateSpots = { { -52, 8 }, { -20, 12 }, { 26, 9 }, { 52, 12 }, { 40, 6 } }
	local nodes = {}
	for _, s in ipairs(crateSpots) do
		if rng:NextNumber() < 0.8 then
			local part = Forge.part({
				parent = model, name = "PlatformCrate",
				size = Vector3.new(2.2, 2.2, 2.2),
				cf = CFrame.new(cx + s[1], FLOOR + 1.1, zNear + s[2]) * CFrame.Angles(0, rng:NextNumber(0, 3), 0),
				color = Palette.Crate, material = M.Planks,
			})
			table.insert(nodes, { kind = "crate", part = part, opts = {} })
		end
	end
	-- benches
	for px = -30, 30, 30 do
		Forge.part({
			parent = model, name = "Bench",
			size = Vector3.new(6, 0.5, 1.6),
			cf = CFrame.new(cx + px, FLOOR + 1.4, zNear + 9),
			color = Palette.SleeperWood, material = M.Wood,
		})
	end

	return model, nodes
end

----------------------------------------------------------------
-- The stop itself
----------------------------------------------------------------
function StationService.arrive(stationNumber)
	local name = ctx.plan.stationNames[stationNumber] or "SOMEWHERE"
	local stationCar = Config.Run.StationCars[stationNumber]
	local model, lootNodes = buildPlatform(stationNumber, name)
	current = { model = model, number = stationNumber, name = name }

	-- platform loot uses the normal container path (station keys live past 1000)
	ctx.LootSystem.populateCar(1000 + stationNumber, {
		lootNodes = lootNodes,
		model = model,
		effectiveCar = stationCar,
	})

	SoundBank.play("StationBell", ctx.TrainBuilder.carPosition(stationCar))
	Net.fireAll(Net.T.Announce, {
		title = name,
		sub = ("The 11:59 rests %d seconds. It will not wait longer."):format(Config.Run.StationStopSeconds),
		seconds = 6, tone = "station",
	})

	-- doors, lamps, glass, ghosts
	ctx.DoorSystem.setSideDoors(math.max(stationCar - 2, 1), stationCar + 1, 1, true)
	ctx.TrainBuilder.relightAll()
	ctx.TrainBuilder.repairWindows()
	local platformCF = CFrame.new(ctx.TrainBuilder.carOriginX(stationCar) + T.CarLength / 2, FLOOR + 3.5, T.CarWidth / 2 + 5)
	ctx.PlayerService.reviveGhostsAtStation(platformCF)

	local seconds = Config.Run.StationStopSeconds
	Net.fireAll(Net.T.StationState, { phase = "open", seconds = seconds, name = name })

	task.spawn(function()
		local warned = false
		for remaining = seconds, 1, -1 do
			task.wait(1)
			if not current or current.number ~= stationNumber then
				return
			end
			if not warned and remaining <= Config.Run.StationWarnSeconds then
				warned = true
				Net.fireAll(Net.T.StationState, { phase = "warn", seconds = remaining, name = name })
				Net.fireAll(Net.T.Subtitle, { text = "The whistle. Board now.", seconds = 4 })
				SoundBank.play("Whistle", ctx.TrainBuilder.carPosition(stationCar))
			end
		end
		StationService.depart(stationNumber)
	end)
end

function StationService.depart(stationNumber)
	if not current or current.number ~= stationNumber then
		return
	end
	local model = current.model
	local stationCar = Config.Run.StationCars[stationNumber]
	local name = current.name
	current = nil

	ctx.DoorSystem.setSideDoors(math.max(stationCar - 2, 1), stationCar + 1, 1, false)
	ctx.LootSystem.unregisterCar(1000 + stationNumber)
	Net.fireAll(Net.T.StationState, { phase = "depart", name = name })

	-- call out anybody still on the boards
	for _, player in ipairs(ctx.util.livingPlayers(true)) do
		if (player:GetAttribute("CarIndex") or 0) < 1 then
			Net.fireAll(Net.T.Subtitle, { text = ("%s stands on the platform as it slides into the dark."):format(player.DisplayName), seconds = 5 })
		end
	end

	ctx.GameLoop.resume()

	-- the platform recedes: slide it backwards, then fold it away
	task.spawn(function()
		local start = os.clock()
		local origin = model:GetPivot()
		while os.clock() - start < 7 do
			local t = os.clock() - start
			local slide = -(t * t) * 9
			model:PivotTo(origin * CFrame.new(slide, 0, 0))
			task.wait(0.05)
		end
		model:Destroy()
	end)
end

function StationService.cleanup()
	current = nil
	ctx.folders.station:ClearAllChildren()
	ctx.EconomyService.clearMachines()
end

return StationService
