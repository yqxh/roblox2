--[[
	CarPlans.luau
	Procedural geometry for every car archetype. Pure construction: builds
	a Model plus a meta table describing everything gameplay cares about
	(hide spots, seats, windows, lamps, loot nodes, noisy props).

	Vertical datum (world Y):
	  rail top ~7 · floor 9..10 · seats 11.6 · sills 13.2 · windows to 16.6
	  ceiling 19 · roof walk ~20.3
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Forge = require(Shared.Forge)
local Palette = require(Shared.Palette)
local Tags = require(Shared.Tags)

local CarPlans = {}
local ctx

local T = Config.Train
local M = Palette.M
local FLOOR = T.FloorY          -- 10
local CEIL = FLOOR + T.CarHeight -- 19
local L = T.CarLength           -- 44
local W = T.CarWidth            -- 12
local HALFW = W / 2

function CarPlans.init(c)
	ctx = c
end

----------------------------------------------------------------
-- Small builders
----------------------------------------------------------------
local function addLamp(meta, cf, opts)
	opts = opts or {}
	local model = meta.model
	local stem = Forge.cyl({
		parent = model, name = "LampStem",
		size = Vector3.new(opts.stem or 1.2, 0.25, 0.25),
		cf = cf * CFrame.new(0, (opts.stem or 1.2) / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(46, 40, 34), material = M.Metal, cancollide = false,
	})
	local glow = Forge.ball({
		parent = model, name = "LampGlobe",
		size = Vector3.new(1.1, 1.1, 1.1) * (opts.scale or 1),
		cf = cf,
		color = Palette.LampGlass, material = M.Neon, cancollide = false,
	})
	local light = Forge.light(glow, {
		color = opts.color or Palette.LampGlow,
		range = opts.range or 15,
		brightness = opts.brightness or 1.05,
		shadows = opts.shadows ~= false,
		flicker = true,
	})
	CollectionService:AddTag(glow, Tags.LampLight)
	if opts.swing then
		CollectionService:AddTag(glow, Tags.SwingLamp)
		CollectionService:AddTag(stem, Tags.SwingLamp)
	end
	table.insert(meta.lamps, { light = light, glow = glow })
	return glow
end

local function addHide(meta, cf, size, label)
	local vol = Forge.zone({
		parent = meta.model, name = "HideSpot",
		size = size, cf = cf,
	})
	local id = ("H%d_%d"):format(meta.index, #meta.hideSpots + 1)
	vol:SetAttribute("SpotId", id)
	CollectionService:AddTag(vol, Tags.HideSpot)
	Forge.prompt(vol, {
		action = label or "Hide",
		object = "",
		hold = Config.Interact.Hide,
		distance = 6,
		id = "hide:" .. id,
	})
	table.insert(meta.hideSpots, { id = id, vol = vol, label = label })
	return vol
end

local function addLoot(meta, kind, part, opts)
	table.insert(meta.lootNodes, { kind = kind, part = part, opts = opts or {} })
	return part
end

local function addSeat(meta, cf, opts)
	opts = opts or {}
	local seat = Forge.seat({
		parent = meta.model, name = "Bench",
		size = Vector3.new(1.6, 0.4, 1.6),
		cf = cf,
		color = opts.color or Palette.SeatLeather,
		material = opts.material or M.Leather,
		anchored = true,
	})
	table.insert(meta.seats, seat)
	return seat
end

local function suitcase(meta, cf, rng, lootable, opts)
	local hues = {
		Color3.fromRGB(96, 62, 40), Color3.fromRGB(60, 50, 44),
		Color3.fromRGB(110, 84, 48), Color3.fromRGB(70, 42, 36),
	}
	local size = Vector3.new(rng:NextNumber(1.5, 2.3), rng:NextNumber(0.8, 1.1), 0.9)
	local case = Forge.part({
		parent = meta.model, name = "Suitcase",
		size = size,
		cf = cf * CFrame.Angles(0, rng:NextNumber(-0.12, 0.12), 0),
		color = hues[rng:NextInteger(1, #hues)], material = M.Leather,
	})
	Forge.part({ -- strap
		parent = meta.model, size = Vector3.new(0.2, size.Y + 0.06, size.Z + 0.06),
		cf = case.CFrame, color = Color3.fromRGB(40, 32, 28), material = M.Leather, cancollide = false,
	})
	if lootable then
		addLoot(meta, "suitcase", case, opts)
	end
	return case
end

local function crate(meta, cf, rng, lootable, opts)
	local s = rng:NextNumber(1.9, 2.5)
	local box = Forge.part({
		parent = meta.model, name = "Crate",
		size = Vector3.new(s, s, s),
		cf = cf * CFrame.Angles(0, rng:NextNumber(-0.1, 0.1), 0),
		color = Palette.Crate, material = M.Planks,
	})
	Forge.part({ -- lid batten
		parent = meta.model, size = Vector3.new(s + 0.15, 0.25, 0.6),
		cf = box.CFrame * CFrame.new(0, s / 2 + 0.12, 0),
		color = Palette.Crate, material = M.Planks, cancollide = false,
	})
	if lootable then
		addLoot(meta, "crate", box, opts)
	end
	return box
end

----------------------------------------------------------------
-- Shell
----------------------------------------------------------------
local function windowBay(meta, x, side, bayW)
	local model = Forge.model("Window", meta.model)
	local z = side * (HALFW - 0.3)
	local glass = Forge.part({
		parent = model, name = "Glass",
		size = Vector3.new(bayW, 3.4, 0.25),
		cf = CFrame.new(x, 14.9, z),
		color = Palette.GlassNight, material = M.Glass,
		transparency = 0.42, reflectance = 0.28,
	})
	-- Blind, rolled at the top; DoorSystem slides it down on request
	local blind = Forge.part({
		parent = model, name = "Blind",
		size = Vector3.new(bayW - 0.2, 0.6, 0.15),
		cf = CFrame.new(x, 16.25, z - side * 0.25),
		color = Palette.Curtain, material = M.Fabric, cancollide = false,
	})
	model:SetAttribute("BlindDown", false)
	model:SetAttribute("Side", side)
	model:SetAttribute("WinX", x)
	CollectionService:AddTag(model, Tags.Window)
	Forge.prompt(glass, {
		action = "Blind",
		object = "",
		hold = Config.Interact.Blind,
		distance = 5,
		id = ("blind:%d:%d"):format(meta.index, #meta.windows + 1),
		tag = Tags.Blind,
	})
	table.insert(meta.windows, { model = model, side = side, glass = glass, blind = blind, x = x })
	return model
end

-- opts: {windows = {side -> {bays}} | "all" | "none", paint, noRoof, lowWalls}
local function shell(meta, opts)
	opts = opts or {}
	local x0 = meta.x0
	local cx = x0 + L / 2
	local model = meta.model
	local paint = opts.paint or Palette.CarBody

	-- Floor (the rails and ballast scroll past on the client, selling motion)
	Forge.part({
		parent = model, name = "Floor",
		size = Vector3.new(L, 1, W),
		cf = CFrame.new(cx, FLOOR - 0.5, 0),
		color = Palette.FloorWood, material = M.Planks,
	})

	-- Underframe + bogies
	Forge.part({
		parent = model, name = "Skirt",
		size = Vector3.new(L, 2.1, W - 0.4),
		cf = CFrame.new(cx, 8.4, 0),
		color = Palette.CarUnderframe, material = M.Metal,
	})
	for _, bx in ipairs({ x0 + 9, x0 + L - 9 }) do
		Forge.part({
			parent = model, name = "Bogie",
			size = Vector3.new(6.5, 1.4, 6.5),
			cf = CFrame.new(bx, 8.1, 0),
			color = Color3.fromRGB(20, 20, 22), material = M.Metal,
		})
		for _, wx in ipairs({ bx - 2.1, bx + 2.1 }) do
			for _, wz in ipairs({ -2.9, 2.9 }) do
				Forge.cyl({
					parent = model, name = "Wheel",
					size = Vector3.new(0.6, 3.1, 3.1),
					cf = CFrame.new(wx, 8.3, wz) * CFrame.Angles(math.rad(90), 0, 0),
					color = Color3.fromRGB(34, 34, 36), material = M.Metal,
					cancollide = false,
				})
			end
		end
	end

	if opts.openTop then
		-- tender-style tub: low-ish walls, no ceiling
		local wallH = opts.wallH or 5
		for _, side in ipairs({ -1, 1 }) do
			Forge.part({
				parent = model, name = "TubWall",
				size = Vector3.new(L, wallH, 0.6),
				cf = CFrame.new(cx, FLOOR + wallH / 2, side * (HALFW - 0.3)),
				color = paint, material = M.Metal,
			})
		end
		return
	end
	if opts.flat then
		-- flatcar: stake posts and nothing else above the deck
		for x = x0 + 3, x0 + L - 3, 5 do
			for _, side in ipairs({ -1, 1 }) do
				Forge.part({
					parent = model, name = "Stake",
					size = Vector3.new(0.4, 2.6, 0.4),
					cf = CFrame.new(x, FLOOR + 1.3, side * (HALFW - 0.4)),
					color = Palette.SnagWood, material = M.Wood,
				})
			end
		end
		return
	end

	-- Side walls: sill band, window band with mullions, upper band
	local windowSpec = opts.windows or "all"
	for _, side in ipairs({ -1, 1 }) do
		local z = side * (HALFW - 0.3)
		Forge.part({
			parent = model, name = "Sill",
			size = Vector3.new(L, 3.2, 0.6),
			cf = CFrame.new(cx, 11.6, z),
			color = paint, material = M.Wood,
		})
		Forge.part({
			parent = model, name = "Upper",
			size = Vector3.new(L, 2.4, 0.6),
			cf = CFrame.new(cx, 17.8, z),
			color = paint, material = M.Wood,
		})
		-- interior wainscot tint
		Forge.part({
			parent = model, name = "Wainscot",
			size = Vector3.new(L - 1.2, 3.0, 0.12),
			cf = CFrame.new(cx, 11.55, z - side * 0.38),
			color = Palette.WallPanel, material = M.Wood, cancollide = false,
		})

		local bays = nil
		if windowSpec == "all" then
			bays = { 1, 2, 3, 4, 5, 6, 7, 8 }
		elseif windowSpec == "none" then
			bays = {}
		else
			bays = windowSpec[side] or {}
		end
		local baySet = {}
		for _, b in ipairs(bays) do
			baySet[b] = true
		end

		-- mullions every 5 studs from x0+2 to x0+42; 8 bays between
		for m = 0, 8 do
			Forge.part({
				parent = model, name = "Mullion",
				size = Vector3.new(0.7, 3.4, 0.6),
				cf = CFrame.new(x0 + 2 + m * 5, 14.9, z),
				color = paint, material = M.Wood,
			})
		end
		for b = 1, 8 do
			local bx = x0 + 2 + (b - 1) * 5 + 2.5
			if baySet[b] then
				windowBay(meta, bx, side, 4.3)
			else
				Forge.part({
					parent = model, name = "Panel",
					size = Vector3.new(4.3, 3.4, 0.6),
					cf = CFrame.new(bx, 14.9, z),
					color = paint, material = M.Wood,
				})
			end
		end
	end

	-- End walls with doorway
	for _, ex in ipairs({ x0 + 0.3, x0 + L - 0.3 }) do
		for _, zc in ipairs({ -3.9, 3.9 }) do
			Forge.part({
				parent = model, name = "EndWall",
				size = Vector3.new(0.6, T.CarHeight, 4.2),
				cf = CFrame.new(ex, FLOOR + T.CarHeight / 2, zc),
				color = paint, material = M.Wood,
			})
		end
		Forge.part({
			parent = model, name = "EndHeader",
			size = Vector3.new(0.6, 2, 3.6),
			cf = CFrame.new(ex, 18, 0),
			color = paint, material = M.Wood,
		})
	end

	-- Ceiling + roof walk + edge lips
	Forge.part({
		parent = model, name = "Ceiling",
		size = Vector3.new(L, 0.6, W),
		cf = CFrame.new(cx, CEIL + 0.3, 0),
		color = Palette.Ceiling, material = M.Plaster,
	})
	Forge.part({
		parent = model, name = "Roof",
		size = Vector3.new(L, 0.7, 9),
		cf = CFrame.new(cx, CEIL + 0.95, 0),
		color = Palette.CarRoof, material = M.Slate,
	})
	for _, side in ipairs({ -1, 1 }) do
		Forge.part({
			parent = model, name = "RoofLip",
			size = Vector3.new(L, 0.45, 1.6),
			cf = CFrame.new(cx, CEIL + 0.85, side * 5.1),
			color = Palette.CarRoof, material = M.Slate,
		})
	end

	-- Emergency strips (client turns them on in tunnels)
	for _, side in ipairs({ -1, 1 }) do
		local strip = Forge.part({
			parent = model, name = "EmergencyStrip",
			size = Vector3.new(L - 2, 0.15, 0.15),
			cf = CFrame.new(cx, FLOOR + 0.25, side * (HALFW - 0.75)),
			color = Palette.EmergencyRed, material = M.Glass,
			transparency = 0.5, cancollide = false, castshadow = false,
		})
		CollectionService:AddTag(strip, Tags.EmergencyStrip)
	end

	-- Gilt lettering + car number plaques
	for _, side in ipairs({ -1, 1 }) do
		local band = Forge.part({
			parent = model, name = "LetterBand",
			size = Vector3.new(16, 1.5, 0.1),
			cf = CFrame.new(cx, 17.8, side * (HALFW + 0.02)),
			color = paint, material = M.Wood, cancollide = false, canquery = false,
		})
		-- NormalId.Front is the -Z face; the outward face on the +Z side is Back
		Forge.surfaceText(band, side == 1 and Enum.NormalId.Back or Enum.NormalId.Front, "THE  11:59", {
			color = Palette.CarLetters, font = Palette.FontHeader, pps = 44,
		})
		local plaque = Forge.part({
			parent = model, name = "Plaque",
			size = Vector3.new(2.6, 1, 0.1),
			cf = CFrame.new(x0 + 3.4, 12.6, side * (HALFW + 0.02)),
			color = Color3.fromRGB(20, 22, 20), material = M.Metal, cancollide = false, canquery = false,
		})
		Forge.surfaceText(plaque, side == 1 and Enum.NormalId.Back or Enum.NormalId.Front, string.format("CAR %02d", meta.index), {
			color = Palette.CarLetters, font = Palette.FontHeader, pps = 60,
		})
	end
end

----------------------------------------------------------------
-- Interior kits (shared between archetypes)
----------------------------------------------------------------
local function benches(meta, rng, opts)
	opts = opts or {}
	local x0 = meta.x0
	local hideRows = {}
	local rows = {}
	for r = 1, 6 do
		table.insert(rows, x0 + 4.5 + r * 5.4)
	end
	-- pick rows that get an under-seat hide spot
	local order = { 1, 2, 3, 4, 5, 6 }
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	for k = 1, 3 do
		hideRows[order[k]] = true
	end

	for r, x in ipairs(rows) do
		local facing = r <= 3 and 1 or -1
		for _, side in ipairs({ -1, 1 }) do
			local zc = side * 3.45
			local leather = (r + (side == 1 and 0 or 1)) % 2 == 0 and Palette.SeatLeather or Palette.SeatLeatherAlt
			-- seat slab
			Forge.part({
				parent = meta.model, name = "BenchSeat",
				size = Vector3.new(1.9, 0.5, 3.9),
				cf = CFrame.new(x, 11.45, zc),
				color = leather, material = M.Leather,
			})
			-- backrest behind relative to facing
			Forge.part({
				parent = meta.model, name = "BenchBack",
				size = Vector3.new(0.45, 2.4, 3.9),
				cf = CFrame.new(x - facing * 0.95, 12.6, zc),
				color = leather, material = M.Leather,
			})
			-- legs
			for _, lz in ipairs({ zc - 1.6, zc + 1.6 }) do
				Forge.part({
					parent = meta.model, name = "BenchLeg",
					size = Vector3.new(0.3, 1.2, 0.3),
					cf = CFrame.new(x + facing * 0.6, 10.6, lz),
					color = Color3.fromRGB(40, 34, 30), material = M.Metal, cancollide = false,
				})
			end
			-- sittable spots
			for _, sz in ipairs({ zc - 1, zc + 1 }) do
				addSeat(meta, CFrame.new(x, 11.85, sz) * CFrame.Angles(0, facing == 1 and math.rad(-90) or math.rad(90), 0), { color = leather })
			end
			-- under-seat hide
			if hideRows[r] and side == (r % 2 == 0 and 1 or -1) then
				addHide(meta, CFrame.new(x, 10.6, zc), Vector3.new(1.8, 1.1, 3.7), "Slip under")
			end
			-- occasional under-seat bag
			if not opts.noBags and rng:NextNumber() < 0.18 then
				local bag = Forge.part({
					parent = meta.model, name = "Bag",
					size = Vector3.new(1.1, 0.8, 1.4),
					cf = CFrame.new(x + facing * 0.3, 10.55, zc + rng:NextNumber(-1, 1)),
					color = Color3.fromRGB(58, 52, 44), material = M.Fabric,
				})
				addLoot(meta, "bag", bag)
			end
		end
	end
end

local function luggageRacks(meta, rng)
	local x0 = meta.x0
	for _, side in ipairs({ -1, 1 }) do
		local z = side * 4.55
		Forge.part({
			parent = meta.model, name = "Rack",
			size = Vector3.new(L - 12, 0.25, 1.5),
			cf = CFrame.new(x0 + L / 2, 16.85, z),
			color = Palette.Brass, material = M.Metal, reflectance = 0.2,
		})
		local count = rng:NextInteger(2, 4)
		for _ = 1, count do
			local x = x0 + rng:NextNumber(8, L - 8)
			suitcase(meta, CFrame.new(x, 17.45, z), rng, true)
		end
	end
end

local function pendantLamps(meta, count, opts)
	local x0 = meta.x0
	count = count or 4
	local gap = L / (count + 1)
	for k = 1, count do
		addLamp(meta, CFrame.new(x0 + gap * k, 17.5, 0), opts or { swing = true })
	end
end

----------------------------------------------------------------
-- Archetypes
----------------------------------------------------------------
local Builders = {}

function Builders.coach(meta, rng)
	shell(meta, { paint = meta.paint })
	benches(meta, rng)
	luggageRacks(meta, rng)
	pendantLamps(meta, 4)
end

function Builders.caboose(meta, rng)
	shell(meta, { paint = Palette.CarBodyAlt, windows = { [1] = { 2, 4, 6 }, [-1] = { 3, 5, 7 } } })
	local x0 = meta.x0

	-- Iron stove with an ember heart
	local stove = Forge.cyl({
		parent = meta.model, name = "Stove",
		size = Vector3.new(3.2, 1.6, 1.6),
		cf = CFrame.new(x0 + 5, FLOOR + 1.6, -3.9) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(26, 26, 28), material = M.CorrodedMetal,
	})
	local ember = Forge.part({
		parent = meta.model, name = "Ember",
		size = Vector3.new(0.7, 0.7, 0.2),
		cf = CFrame.new(x0 + 5, FLOOR + 1.3, -3.05),
		color = Palette.FurnaceEmber, material = M.Neon, cancollide = false,
	})
	Forge.light(ember, { color = Palette.FurnaceCore, range = 11, brightness = 0.8, flicker = true, shadows = true })
	Forge.cyl({
		parent = meta.model, name = "StovePipe",
		size = Vector3.new(8.4, 0.5, 0.5),
		cf = CFrame.new(x0 + 5, FLOOR + 5.4, -3.9) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(30, 30, 32), material = M.Metal, cancollide = false,
	})
	stove.Name = "Stove"

	-- Table with the departure lever ("brake wheel")
	Forge.part({
		parent = meta.model, name = "Table",
		size = Vector3.new(3, 0.3, 2.2),
		cf = CFrame.new(x0 + 12, FLOOR + 2.2, 3.6),
		color = Palette.SleeperWood, material = M.Wood,
	})
	local wheelPost = Forge.part({
		parent = meta.model, name = "BrakePost",
		size = Vector3.new(0.5, 3.4, 0.5),
		cf = CFrame.new(x0 + L - 6, FLOOR + 1.7, -3.6),
		color = Color3.fromRGB(40, 34, 30), material = M.Metal,
	})
	local wheel = Forge.cyl({
		parent = meta.model, name = "BrakeWheel",
		size = Vector3.new(0.4, 2.4, 2.4),
		cf = CFrame.new(x0 + L - 6, FLOOR + 3.6, -3.6) * CFrame.Angles(0, 0, math.rad(90)),
		color = Palette.Brass, material = M.Metal, reflectance = 0.25,
	})
	CollectionService:AddTag(wheel, Tags.BoardLever)
	Forge.prompt(wheel, {
		action = "Release the brake",
		object = "Depart now",
		hold = 1.5,
		distance = 7,
		id = "boardlever",
		tag = Tags.BoardLever,
	})
	wheelPost.Name = "BrakePost"

	-- Bunks and a couple of learning-friendly loot pieces
	Forge.part({
		parent = meta.model, name = "Bunk",
		size = Vector3.new(6.5, 0.5, 2.6),
		cf = CFrame.new(x0 + 24, FLOOR + 1.5, 3.9),
		color = Palette.SeatLeatherAlt, material = M.Fabric,
	})
	addHide(meta, CFrame.new(x0 + 24, FLOOR + 0.7, 3.9), Vector3.new(6, 1.2, 2.4), "Slip under")
	suitcase(meta, CFrame.new(x0 + 31, FLOOR + 0.95, -3.8), rng, true)
	suitcase(meta, CFrame.new(x0 + 17, FLOOR + 0.95, 4.1), rng, true)

	-- Tutorial plaques
	local posters = {
		"HOLD TOGETHER.\nDOWNED RIDERS CAN BE LIFTED.\nGHOSTS RIDE UNTIL THE NEXT STOP.",
		"WHEN THE LAMPS DIE DOWN THE LINE,\nHIDE, OR CLIMB.\nTHE ROOF FEARS NOTHING BUT BRIDGES.",
		"KEEP A TICKET.\nBE SEATED FOR INSPECTION.\nTHE FINE IS NOT MONEY.",
	}
	for k, text in ipairs(posters) do
		local sign = Forge.part({
			parent = meta.model, name = "Poster",
			size = Vector3.new(4.6, 2.6, 0.15),
			cf = CFrame.new(x0 + 8 + k * 8, 15, 5.28),
			color = Palette.UIPaperDim, material = M.Plaster, cancollide = false,
		})
		-- the poster hangs on the +Z wall; its readable face is -Z (Front)
		Forge.surfaceText(sign, Enum.NormalId.Front, text, {
			color = Palette.UIInk, font = Palette.FontHeader, pps = 34,
		})
	end

	pendantLamps(meta, 3)
end

function Builders.sleeper(meta, rng)
	shell(meta, { paint = meta.paint, windows = { [1] = { 1, 2, 3, 4, 5, 6, 7, 8 }, [-1] = { 2, 4, 6, 8 } } })
	local x0 = meta.x0
	for c = 0, 3 do
		local cx = x0 + 4 + c * 10
		-- partition walls between compartments
		if c > 0 then
			Forge.part({
				parent = meta.model, name = "Partition",
				size = Vector3.new(0.4, T.CarHeight, 6.6),
				cf = CFrame.new(cx - 5, FLOOR + T.CarHeight / 2, -2.1),
				color = Palette.WallPanel, material = M.Wood,
			})
		end
		-- bunks on the -Z wall
		for _, bunkY in ipairs({ FLOOR + 1.4, FLOOR + 4.6 }) do
			Forge.part({
				parent = meta.model, name = "BunkFrame",
				size = Vector3.new(7, 0.4, 2.4),
				cf = CFrame.new(cx + 0.5, bunkY, -4),
				color = Palette.SleeperWood, material = M.Wood,
			})
			Forge.part({
				parent = meta.model, name = "Bedding",
				size = Vector3.new(6.6, 0.5, 2.1),
				cf = CFrame.new(cx + 0.5, bunkY + 0.4, -4),
				color = c % 2 == 0 and Color3.fromRGB(170, 160, 148) or Palette.SeatLeatherAlt,
				material = M.Fabric,
			})
		end
		-- locker: a standing hide spot
		local locker = Forge.part({
			parent = meta.model, name = "Locker",
			size = Vector3.new(1.6, 7, 1.8),
			cf = CFrame.new(cx + 4, FLOOR + 3.5, -4.3),
			color = Palette.WallPanel, material = M.Wood,
		})
		Forge.part({
			parent = meta.model, name = "LockerDoor",
			size = Vector3.new(1.5, 6.8, 0.15),
			cf = locker.CFrame * CFrame.new(0, 0, 1.0),
			color = Palette.SleeperWood, material = M.Wood, cancollide = false,
			transparency = 0.35,
		})
		addHide(meta, locker.CFrame * CFrame.new(0, -0.4, 0), Vector3.new(1.4, 6, 1.6), "Hide in locker")
		-- drawer under the low bunk
		local drawer = Forge.part({
			parent = meta.model, name = "Drawer",
			size = Vector3.new(2.6, 0.9, 2.2),
			cf = CFrame.new(cx - 1.5, FLOOR + 0.55, -4),
			color = Palette.SleeperWood, material = M.Wood,
		})
		addLoot(meta, "drawer", drawer)
		-- sconce
		addLamp(meta, CFrame.new(cx, 16.4, -3.4), { range = 11, brightness = 0.8, scale = 0.8 })
	end
	-- corridor lamps
	addLamp(meta, CFrame.new(x0 + 12, 17.5, 3.6), { swing = true })
	addLamp(meta, CFrame.new(x0 + 30, 17.5, 3.6), { swing = true })
end

function Builders.diner(meta, rng)
	shell(meta, { paint = meta.paint })
	local x0 = meta.x0
	-- table bays along both sides, bar at the front end
	for _, side in ipairs({ -1, 1 }) do
		for b = 0, 3 do
			local bx = x0 + 7 + b * 8
			local zc = side * 3.5
			Forge.part({
				parent = meta.model, name = "TableLeg",
				size = Vector3.new(0.5, 2.4, 0.5),
				cf = CFrame.new(bx, FLOOR + 1.2, zc),
				color = Color3.fromRGB(40, 34, 30), material = M.Metal,
			})
			Forge.part({
				parent = meta.model, name = "Table",
				size = Vector3.new(2.8, 0.25, 2.6),
				cf = CFrame.new(bx, FLOOR + 2.5, zc),
				color = Palette.TableLinen, material = M.Fabric,
			})
			addLamp(meta, CFrame.new(bx, FLOOR + 3.3, zc), { range = 8, brightness = 0.7, scale = 0.55, shadows = false })
			for _, dx in ipairs({ -1.9, 1.9 }) do
				Forge.part({
					parent = meta.model, name = "DinerBench",
					size = Vector3.new(1.2, 0.5, 3),
					cf = CFrame.new(bx + dx, 11.45, zc),
					color = Palette.SeatLeather, material = M.Leather,
				})
				Forge.part({
					parent = meta.model, name = "DinerBack",
					size = Vector3.new(0.4, 2.4, 3),
					cf = CFrame.new(bx + dx + (dx > 0 and 0.75 or -0.75), 12.6, zc),
					color = Palette.SeatLeather, material = M.Leather,
				})
				addSeat(meta, CFrame.new(bx + dx, 11.85, zc) * CFrame.Angles(0, dx > 0 and math.rad(90) or math.rad(-90), 0))
			end
			if b == 1 and side == -1 then
				addHide(meta, CFrame.new(bx, 10.8, zc), Vector3.new(2.6, 1.5, 2.4), "Duck under")
			end
		end
	end
	-- bar counter on the -Z side; the aisle stays open along +Z
	local barX = x0 + L - 5.5
	Forge.part({
		parent = meta.model, name = "Bar",
		size = Vector3.new(1.6, 3.6, 5),
		cf = CFrame.new(barX, FLOOR + 1.8, -2.9),
		color = Palette.SleeperWood, material = M.Wood,
	})
	Forge.part({
		parent = meta.model, name = "BarTop",
		size = Vector3.new(2, 0.25, 5.6),
		cf = CFrame.new(barX, FLOOR + 3.7, -2.9),
		color = Palette.Brass, material = M.Metal, reflectance = 0.3,
	})
	for _, zc in ipairs({ -4.0, -1.6 }) do
		local cab = Forge.part({
			parent = meta.model, name = "Cabinet",
			size = Vector3.new(1.2, 2.6, 2.4),
			cf = CFrame.new(x0 + L - 1.6, FLOOR + 1.3, zc),
			color = Palette.WallPanel, material = M.Wood,
		})
		addLoot(meta, "cabinet", cab)
	end
	-- menu board
	local menu = Forge.part({
		parent = meta.model, name = "Menu",
		size = Vector3.new(2.8, 2, 0.15),
		cf = CFrame.new(barX - 2.5, 15.4, 4.9),
		color = Color3.fromRGB(20, 22, 24), material = M.Wood, cancollide = false,
	})
	Forge.surfaceText(menu, Enum.NormalId.Front, "DINING CAR\nsoup — gone\nbread — gone\ncoffee — cold\nstay seated", {
		color = Palette.UIPaper, font = Palette.FontHeader, pps = 40,
	})
	if rng:NextNumber() > 0.5 then
		suitcase(meta, CFrame.new(x0 + 4, FLOOR + 0.95, 3.9), rng, true)
	end
end

function Builders.lounge(meta, rng)
	shell(meta, { paint = meta.paint })
	local x0 = meta.x0
	-- facing sofas
	for _, side in ipairs({ -1, 1 }) do
		local zc = side * 3.6
		Forge.part({
			parent = meta.model, name = "Sofa",
			size = Vector3.new(7, 1.1, 2),
			cf = CFrame.new(x0 + 12, FLOOR + 0.95, zc),
			color = Palette.Curtain, material = M.Fabric,
		})
		Forge.part({
			parent = meta.model, name = "SofaBack",
			size = Vector3.new(7, 2.2, 0.5),
			cf = CFrame.new(x0 + 12, FLOOR + 2, zc + side * 0.8),
			color = Palette.Curtain, material = M.Fabric,
		})
		for _, sx in ipairs({ x0 + 10, x0 + 14 }) do
			-- identity CFrame seats face -Z; the +Z sofa already looks at the center
			addSeat(meta, CFrame.new(sx, FLOOR + 1.85, zc) * CFrame.Angles(0, side == 1 and 0 or math.rad(180), 0), { color = Palette.Curtain, material = M.Fabric })
		end
	end
	addHide(meta, CFrame.new(x0 + 12, FLOOR + 0.7, -4.7), Vector3.new(6.5, 1.2, 1.2), "Squeeze behind")

	-- card table, hand still dealt
	Forge.part({
		parent = meta.model, name = "CardTable",
		size = Vector3.new(2.6, 0.25, 2.6),
		cf = CFrame.new(x0 + 20, FLOOR + 2.3, 0),
		color = Color3.fromRGB(30, 62, 44), material = M.Fabric,
	})
	Forge.part({
		parent = meta.model, name = "CardLeg",
		size = Vector3.new(0.4, 2.2, 0.4),
		cf = CFrame.new(x0 + 20, FLOOR + 1.1, 0),
		color = Palette.SleeperWood, material = M.Wood,
	})
	for k = 1, 5 do
		Forge.part({
			parent = meta.model, name = "Card",
			size = Vector3.new(0.5, 0.02, 0.7),
			cf = CFrame.new(x0 + 20 + (k - 3) * 0.35, FLOOR + 2.45, (k % 2 == 0) and 0.3 or -0.2)
				* CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0),
			color = Palette.UIPaper, material = M.Smooth, cancollide = false,
		})
	end

	-- the piano: loud, tempting
	local piano = Forge.part({
		parent = meta.model, name = "Piano",
		size = Vector3.new(2, 3.4, 4.6),
		cf = CFrame.new(x0 + 33, FLOOR + 1.7, -3.4),
		color = Color3.fromRGB(16, 14, 14), material = M.Wood,
	})
	Forge.part({
		parent = meta.model, name = "PianoKeys",
		size = Vector3.new(0.9, 0.25, 3.9),
		cf = CFrame.new(x0 + 31.9, FLOOR + 2.55, -3.4),
		color = Color3.fromRGB(230, 226, 214), material = M.Smooth, cancollide = false,
	})
	Forge.part({
		parent = meta.model, name = "PianoStool",
		size = Vector3.new(1.2, 1.5, 1.2),
		cf = CFrame.new(x0 + 30.6, FLOOR + 0.75, -3.4),
		color = Palette.SleeperWood, material = M.Wood,
	})
	CollectionService:AddTag(piano, Tags.NoisyProp)
	piano:SetAttribute("PropKind", "piano")
	Forge.prompt(piano, {
		action = "Play",
		object = "Upright piano",
		hold = 0,
		distance = 6,
		id = "piano:" .. meta.index,
		tag = Tags.NoisyProp,
	})

	-- bookshelf as loot, stove for warmth
	local shelf = Forge.part({
		parent = meta.model, name = "Bookshelf",
		size = Vector3.new(1.2, 5.5, 4),
		cf = CFrame.new(x0 + 39, FLOOR + 2.75, 3.9),
		color = Palette.WallPanel, material = M.Wood,
	})
	addLoot(meta, "cabinet", shelf)
	pendantLamps(meta, 3)
end

function Builders.freight(meta, rng)
	shell(meta, { paint = Palette.CarBodyAlt, windows = "none" })
	local x0 = meta.x0
	-- crate field: a few open, the rest scenery
	local spots = {}
	for gx = 0, 4 do
		for gz = -1, 1 do
			table.insert(spots, { x0 + 7 + gx * 7 + rng:NextNumber(-1, 1), gz * 3.4 + rng:NextNumber(-0.6, 0.6) })
		end
	end
	local lootLeft = 3
	local lootablePlaced = 0
	for _, s in ipairs(spots) do
		if rng:NextNumber() < 0.5 then
			local lootable = lootLeft > 0 and rng:NextNumber() < 0.45
			if lootable then
				lootLeft -= 1
				lootablePlaced += 1
			end
			local box = crate(meta, CFrame.new(s[1], FLOOR + 1.2, s[2]), rng, lootable)
			if rng:NextNumber() < 0.3 then
				crate(meta, box.CFrame * CFrame.new(0, box.Size.Y, 0), rng, false)
			end
		end
	end
	if lootablePlaced == 0 then
		-- guarantee at least one openable crate: key/ticket seeding relies on it
		crate(meta, CFrame.new(x0 + 20, FLOOR + 1.2, 2.6), rng, true)
	end
	-- tarp piles to hide beneath
	for k = 1, 2 do
		local tx = x0 + (k == 1 and 12 or 30)
		Forge.part({
			parent = meta.model, name = "Tarp",
			size = Vector3.new(4.5, 2, 3.6),
			cf = CFrame.new(tx, FLOOR + 1, k == 1 and 3.4 or -3.4) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), 0),
			color = Palette.Tarp, material = M.Fabric,
		})
		addHide(meta, CFrame.new(tx, FLOOR + 0.9, k == 1 and 3.4 or -3.4), Vector3.new(4.2, 1.6, 3.4), "Under the tarp")
	end
	-- chains from the ceiling
	for _ = 1, 4 do
		local cxx = x0 + rng:NextNumber(6, L - 6)
		local cz = rng:NextNumber(-3, 3)
		Forge.cyl({
			parent = meta.model, name = "Chain",
			size = Vector3.new(rng:NextNumber(2, 4.5), 0.12, 0.12),
			cf = CFrame.new(cxx, CEIL - 1.6, cz) * CFrame.Angles(0, 0, math.rad(90)),
			color = Color3.fromRGB(50, 50, 54), material = M.CorrodedMetal, cancollide = false,
		})
	end
	-- one swinging lamp; freight cars are dim
	addLamp(meta, CFrame.new(x0 + L / 2, 17.3, 0), { swing = true, range = 13, brightness = 0.85 })
end

function Builders.mail(meta, rng)
	shell(meta, { paint = meta.paint, windows = { [1] = { 1, 3, 5 }, [-1] = { 4, 8 } } })
	local x0 = meta.x0
	-- pigeonhole shelving
	for _, side in ipairs({ -1, 1 }) do
		Forge.part({
			parent = meta.model, name = "Shelving",
			size = Vector3.new(14, 5.5, 1.2),
			cf = CFrame.new(x0 + 26, FLOOR + 2.75, side * 4.4),
			color = Palette.WallPanel, material = M.Wood,
		})
		for row = 1, 3 do
			for col = 1, 6 do
				Forge.part({
					parent = meta.model, name = "Cubby",
					size = Vector3.new(1.9, 1.4, 0.15),
					cf = CFrame.new(x0 + 20.5 + col * 2.05, FLOOR + 0.9 + row * 1.5, side * 3.75),
					color = Color3.fromRGB(30, 26, 22), material = M.Wood, cancollide = false,
				})
			end
		end
	end
	-- mail sacks
	for k = 1, 4 do
		local sack = Forge.part({
			parent = meta.model, name = "MailSack",
			size = Vector3.new(1.6, 2.1, 1.6),
			cf = CFrame.new(x0 + 6 + k * 3.2, FLOOR + 1.05, (k % 2 == 0) and 3.4 or -3.2)
				* CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), rng:NextNumber(-0.12, 0.12)),
			color = Palette.MailSack, material = M.Fabric,
		})
		addLoot(meta, "sack", sack)
	end
	-- sorting table
	Forge.part({
		parent = meta.model, name = "SortTable",
		size = Vector3.new(6, 0.4, 2.4),
		cf = CFrame.new(x0 + 12, FLOOR + 2.3, 0),
		color = Palette.SleeperWood, material = M.Wood,
	})
	addHide(meta, CFrame.new(x0 + 12, FLOOR + 1, 0), Vector3.new(5.6, 1.7, 2.2), "Duck under")
	-- registered mail cage in the front -Z corner; the aisle stays clear
	local function cageBar(cf)
		Forge.cyl({
			parent = meta.model, name = "CageBar",
			size = Vector3.new(T.CarHeight - 0.5, 0.18, 0.18),
			cf = cf * CFrame.Angles(0, 0, math.rad(90)),
			color = Color3.fromRGB(60, 60, 64), material = M.Metal,
		})
	end
	for x = x0 + 36, x0 + 42, 1.15 do
		if math.abs(x - (x0 + 39.5)) > 0.7 then -- bent bars: the way in
			cageBar(CFrame.new(x, FLOOR + T.CarHeight / 2, -0.8))
		end
	end
	for zc = -4.4, -1.4, 1.15 do
		cageBar(CFrame.new(x0 + 36, FLOOR + T.CarHeight / 2, zc))
	end
	local strongbox = Forge.part({
		parent = meta.model, name = "Strongbox",
		size = Vector3.new(2.4, 1.8, 1.6),
		cf = CFrame.new(x0 + 40, FLOOR + 0.9, -3.2),
		color = Color3.fromRGB(38, 42, 48), material = M.DiamondPlate,
	})
	addLoot(meta, "lockbox", strongbox, { rich = true })
	pendantLamps(meta, 3)
end

function Builders.flatcar(meta, rng)
	shell(meta, { flat = true })
	local x0 = meta.x0
	-- the lashed-down machine
	local machine = Forge.part({
		parent = meta.model, name = "Machine",
		size = Vector3.new(6.5, 4.2, 5.5),
		cf = CFrame.new(x0 + 22, FLOOR + 2.1, 0),
		color = Palette.Tarp, material = M.Fabric,
	})
	Forge.part({
		parent = meta.model, name = "MachineFoot",
		size = Vector3.new(7.5, 0.5, 6.5),
		cf = CFrame.new(x0 + 22, FLOOR + 0.25, 0),
		color = Color3.fromRGB(30, 30, 32), material = M.Metal,
	})
	for _, off in ipairs({ -2.6, 2.6 }) do
		Forge.cyl({
			parent = meta.model, name = "Lashing",
			size = Vector3.new(7.4, 0.15, 0.15),
			cf = CFrame.new(x0 + 22 + off, FLOOR + 2.1, 0) * CFrame.Angles(math.rad(90), 0, 0),
			color = Color3.fromRGB(50, 50, 54), material = M.CorrodedMetal, cancollide = false,
		})
	end
	machine.Name = "Machine"
	-- crates fore and aft; hide in their wind shadow
	local c1 = crate(meta, CFrame.new(x0 + 8, FLOOR + 1.2, -2), rng, true)
	crate(meta, c1.CFrame * CFrame.new(0.4, c1.Size.Y, 0.6), rng, false)
	crate(meta, CFrame.new(x0 + 36, FLOOR + 1.2, 2.2), rng, true)
	addHide(meta, CFrame.new(x0 + 8, FLOOR + 1, 1.6), Vector3.new(3, 1.8, 2.6), "Crouch behind")
	addHide(meta, CFrame.new(x0 + 36, FLOOR + 1, -1.4), Vector3.new(3, 1.8, 2.6), "Crouch behind")
	-- red marker lamps
	for _, mx in ipairs({ x0 + 2, x0 + L - 2 }) do
		local marker = Forge.part({
			parent = meta.model, name = "Marker",
			size = Vector3.new(0.5, 0.7, 0.5),
			cf = CFrame.new(mx, FLOOR + 2.9, 5.2),
			color = Palette.EmergencyRed, material = M.Neon, cancollide = false,
		})
		Forge.light(marker, { color = Palette.EmergencyRed, range = 7, brightness = 0.5, shadows = false })
	end
	meta.enclosed = false
end

function Builders.redcar(meta, rng)
	shell(meta, { paint = Palette.RedCarBody })
	local x0 = meta.x0
	meta.redcar = true
	-- every blind starts drawn in the red car
	for _, win in ipairs(meta.windows) do
		win.model:SetAttribute("BlindDown", true)
		win.blind.Size = Vector3.new(win.blind.Size.X, 3.4, 0.15)
		win.blind.CFrame = CFrame.new(win.x, 14.9, win.side * (HALFW - 0.55))
	end
	-- carpet
	Forge.part({
		parent = meta.model, name = "Carpet",
		size = Vector3.new(L - 6, 0.1, 6),
		cf = CFrame.new(x0 + L / 2, FLOOR + 0.05, 0),
		color = Color3.fromRGB(46, 10, 12), material = M.Carpet, cancollide = false,
	})
	-- velvet chairs facing nothing
	for k = 1, 4 do
		local chairX = x0 + 6 + k * 6.5
		local zc = (k % 2 == 0) and 3.2 or -3.2
		Forge.part({
			parent = meta.model, name = "Chair",
			size = Vector3.new(1.8, 1, 1.8),
			cf = CFrame.new(chairX, FLOOR + 0.9, zc),
			color = Color3.fromRGB(52, 14, 16), material = M.Fabric,
		})
		Forge.part({
			parent = meta.model, name = "ChairBack",
			size = Vector3.new(0.4, 2.6, 1.8),
			cf = CFrame.new(chairX + 0.7, FLOOR + 1.9, zc),
			color = Color3.fromRGB(52, 14, 16), material = M.Fabric,
		})
	end
	-- portraits whose faces did not survive
	for k = 1, 3 do
		local frame = Forge.part({
			parent = meta.model, name = "Portrait",
			size = Vector3.new(2.2, 3, 0.2),
			cf = CFrame.new(x0 + 8 + k * 8, 15.2, 5.25),
			color = Palette.Brass, material = M.Wood, cancollide = false,
		})
		Forge.surfaceText(frame, Enum.NormalId.Front, "O", {
			color = Color3.fromRGB(200, 196, 188), font = Enum.Font.Fondamento, pps = 30,
		})
	end
	-- candelabra light, low and red
	for _, lx in ipairs({ x0 + 10, x0 + 22, x0 + 34 }) do
		local candle = Forge.part({
			parent = meta.model, name = "Candle",
			size = Vector3.new(0.35, 1.2, 0.35),
			cf = CFrame.new(lx, FLOOR + 3.1, (lx % 2 == 0) and 3.8 or -3.8),
			color = Color3.fromRGB(220, 208, 180), material = M.Smooth,
		})
		local flame = Forge.part({
			parent = meta.model, name = "Flame",
			size = Vector3.new(0.22, 0.35, 0.22),
			cf = candle.CFrame * CFrame.new(0, 0.8, 0),
			color = Color3.fromRGB(255, 120, 60), material = M.Neon, cancollide = false,
		})
		Forge.light(flame, { color = Color3.fromRGB(255, 96, 60), range = 9, brightness = 0.7, flicker = true, shadows = true })
		Forge.part({
			parent = meta.model, name = "CandleStand",
			size = Vector3.new(0.8, 2.6, 0.8),
			cf = candle.CFrame * CFrame.new(0, -1.9, 0),
			color = Color3.fromRGB(30, 26, 24), material = M.Metal,
		})
	end
	-- the chests: rich, and not all of them chests
	for k = 1, 5 do
		local chest = Forge.part({
			parent = meta.model, name = "Chest",
			size = Vector3.new(2.6, 1.6, 1.7),
			cf = CFrame.new(x0 + 4 + k * 6.6, FLOOR + 0.8, (k % 2 == 0) and -4.2 or 4.2),
			color = Color3.fromRGB(40, 22, 18), material = M.Wood,
		})
		Forge.part({
			parent = meta.model, name = "ChestBand",
			size = Vector3.new(0.3, 1.7, 1.8),
			cf = chest.CFrame,
			color = Palette.Brass, material = M.Metal, cancollide = false,
		})
		addLoot(meta, "chest", chest, { rich = true, mimicPool = true })
	end
	addHide(meta, CFrame.new(x0 + 19.5, FLOOR + 0.8, -4.6), Vector3.new(3, 1.5, 1.4), "Crouch behind")
end

function Builders.sleeperboss(meta, rng)
	shell(meta, { paint = Palette.CarBodyAlt, windows = { [1] = { 1, 8 }, [-1] = {} } })
	local x0 = meta.x0
	-- wrecked bunks
	for c = 0, 2 do
		local cx = x0 + 6 + c * 9
		Forge.part({
			parent = meta.model, name = "WreckedBunk",
			size = Vector3.new(7, 0.4, 2.4),
			cf = CFrame.new(cx, FLOOR + 1.2, -4) * CFrame.Angles(rng:NextNumber(-0.05, 0.05), 0, rng:NextNumber(0.1, 0.3)),
			color = Palette.SleeperWood, material = M.Wood,
		})
	end
	-- the nest
	local nest = Forge.model("Nest", meta.model)
	local nx = x0 + 28
	for k = 1, 7 do
		Forge.ball({
			parent = nest,
			size = Vector3.new(rng:NextNumber(2.5, 4.5), rng:NextNumber(1.6, 2.6), rng:NextNumber(2.5, 4.5)),
			cf = CFrame.new(nx + rng:NextNumber(-4, 4), FLOOR + rng:NextNumber(0.5, 1.4), rng:NextNumber(-2.5, 2.5)),
			color = Palette.SleeperHide, material = M.Fabric,
		})
	end
	-- eyes, closed until the noise rises (entity controls material)
	meta.sleeperEyes = {}
	for k = 1, 6 do
		local eye = Forge.ball({
			parent = nest, name = "Eye",
			size = Vector3.new(0.55, 0.55, 0.55),
			cf = CFrame.new(nx + rng:NextNumber(-3, 3), FLOOR + rng:NextNumber(1.8, 2.8), rng:NextNumber(-2, 2)),
			color = Color3.fromRGB(50, 46, 40), material = M.Glass, cancollide = false,
		})
		table.insert(meta.sleeperEyes, eye)
	end
	meta.sleeperNest = nest
	-- greed bait around the nest
	for k = 1, 3 do
		local tribute = Forge.part({
			parent = meta.model, name = "Tribute",
			size = Vector3.new(1.6, 1, 1.3),
			cf = CFrame.new(nx + rng:NextNumber(-6, 6), FLOOR + 0.55, rng:NextNumber(-3.5, 3.5)),
			color = Color3.fromRGB(80, 66, 46), material = M.Leather,
		})
		addLoot(meta, "nest", tribute, { rich = true })
	end
	-- two guttering lamps only
	addLamp(meta, CFrame.new(x0 + 8, 17.5, 0), { swing = true, brightness = 0.5, range = 10 })
	addLamp(meta, CFrame.new(x0 + 38, 17.5, 0), { swing = true, brightness = 0.5, range = 10 })
	addHide(meta, CFrame.new(x0 + 6, FLOOR + 0.8, 4.4), Vector3.new(3.4, 1.5, 1.6), "Crouch behind")
end

function Builders.tender(meta, rng)
	shell(meta, { openTop = true, wallH = 5, paint = Color3.fromRGB(24, 26, 28) })
	local x0 = meta.x0
	-- coal heaps
	for k = 1, 5 do
		Forge.ball({
			parent = meta.model, name = "Coal",
			size = Vector3.new(rng:NextNumber(4, 7), rng:NextNumber(2, 3.4), rng:NextNumber(4, 7)),
			cf = CFrame.new(x0 + 8 + k * 5.5 + rng:NextNumber(-1, 1), FLOOR + rng:NextNumber(0.8, 1.6), rng:NextNumber(-2, 2)),
			color = Color3.fromRGB(14, 14, 16), material = M.Basalt,
		})
	end
	-- side walkway
	Forge.part({
		parent = meta.model, name = "Walkway",
		size = Vector3.new(L - 4, 0.4, 2),
		cf = CFrame.new(x0 + L / 2, FLOOR + 0.2, 4.4),
		color = Palette.SleeperWood, material = M.Planks,
	})
	-- cab backhead at the front: the firebox glare
	Forge.part({
		parent = meta.model, name = "Backhead",
		size = Vector3.new(1.2, 9, 11),
		cf = CFrame.new(x0 + L - 0.8, FLOOR + 4.5, 0),
		color = Color3.fromRGB(30, 32, 34), material = M.Metal,
	})
	local fireDoor = Forge.part({
		parent = meta.model, name = "FireboxDoor",
		size = Vector3.new(0.3, 2.2, 2.6),
		cf = CFrame.new(x0 + L - 1.3, FLOOR + 2.4, 0),
		color = Palette.FurnaceCore, material = M.Neon,
	})
	Forge.light(fireDoor, { color = Palette.FurnaceCore, range = 22, brightness = 1.6, flicker = true, shadows = true })
	for k = 1, 3 do
		Forge.cyl({
			parent = meta.model, name = "Gauge",
			size = Vector3.new(0.2, 0.9, 0.9),
			cf = CFrame.new(x0 + L - 1.3, FLOOR + 5.4, -2.4 + k * 1.4) * CFrame.Angles(0, math.rad(90), 0),
			color = Color3.fromRGB(220, 214, 196), material = M.Smooth, cancollide = false,
		})
	end
	-- the coupling release, at the rear of the tender
	local housing = Forge.part({
		parent = meta.model, name = "CouplingHousing",
		size = Vector3.new(1.6, 3.6, 2.4),
		cf = CFrame.new(x0 + 1.4, FLOOR + 1.8, -3.6),
		color = Color3.fromRGB(44, 40, 36), material = M.CorrodedMetal,
	})
	local lever = Forge.part({
		parent = meta.model, name = "CouplingLever",
		size = Vector3.new(0.4, 2.2, 0.4),
		cf = housing.CFrame * CFrame.new(0, 1.6, 0.9) * CFrame.Angles(math.rad(-24), 0, 0),
		color = Palette.EmergencyRed, material = M.Metal,
	})
	CollectionService:AddTag(housing, Tags.CouplingRig)
	housing:SetAttribute("CoupleProgress", 0)
	Forge.prompt(housing, {
		action = "Crank the release",
		object = "Coupling pin",
		hold = Config.Interact.Couple,
		distance = 7,
		id = "coupling",
		tag = Tags.CouplingRig,
	})
	meta.coupling = housing
	meta.couplingLever = lever
	meta.enclosed = false
	-- patrol waypoints for the Engineer
	meta.patrol = {
		CFrame.new(x0 + L - 4, FLOOR + 2, 0),
		CFrame.new(x0 + L - 10, FLOOR + 2, 3.6),
		CFrame.new(x0 + 20, FLOOR + 2.6, 0),
		CFrame.new(x0 + 8, FLOOR + 2, -3),
		CFrame.new(x0 + 14, FLOOR + 2.4, 3.8),
	}
end

----------------------------------------------------------------
-- Entry
----------------------------------------------------------------
function CarPlans.buildCar(entry, parent)
	local model = Forge.model(("Car_%02d"):format(entry.index), parent)
	local meta = {
		model = model,
		index = entry.index,
		archetype = entry.archetype,
		x0 = (entry.index - 1) * T.CarPitch,
		paint = entry.paint == "oxblood" and Palette.CarBodyAlt or Palette.CarBody,
		hideSpots = {},
		seats = {},
		windows = {},
		lamps = {},
		lootNodes = {},
		lampsLit = true,
		enclosed = true,
	}
	model:SetAttribute("CarIndex", entry.index)
	model:SetAttribute("Archetype", entry.archetype)
	CollectionService:AddTag(model, Tags.CarModel)

	local rng = Random.new(entry.variant)
	local builder = Builders[entry.archetype] or Builders.coach
	builder(meta, rng)

	-- lashed roof cargo on some enclosed cars: the roof route pays rent
	if meta.enclosed and entry.archetype ~= "caboose" and rng:NextNumber() < 0.35 then
		local rx = meta.x0 + rng:NextNumber(9, L - 9)
		local rz = rng:NextNumber(-2.2, 2.2)
		local case = Forge.part({
			parent = model, name = "RoofCase",
			size = Vector3.new(rng:NextNumber(1.8, 2.4), 1.1, 1.2),
			cf = CFrame.new(rx, CEIL + 1.85, rz) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0),
			color = Color3.fromRGB(72, 54, 40), material = M.Leather,
		})
		for _, off in ipairs({ -0.6, 0.6 }) do
			Forge.part({
				parent = model, name = "Lashing",
				size = Vector3.new(0.16, 1.25, 1.35),
				cf = case.CFrame * CFrame.new(off, 0, 0),
				color = Color3.fromRGB(40, 36, 30), material = M.Fabric, cancollide = false,
			})
		end
		addLoot(meta, "roofcase", case)
	end

	model:SetAttribute("Enclosed", meta.enclosed)
	return meta
end

return CarPlans
