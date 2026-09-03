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
		color = Color3.fromRGB(46, 40, 34), material = M.Metal, cancollide = false, canquery = false,
	})
	local glow = Forge.ball({
		parent = model, name = "LampGlobe",
		size = Vector3.new(1.1, 1.1, 1.1) * (opts.scale or 1),
		cf = cf,
		color = Palette.LampGlass, material = M.Neon, cancollide = false, castshadow = false,
	})
	local light = Forge.light(glow, {
		color = opts.color or Palette.LampGlow,
		range = opts.range or 10,
		brightness = opts.brightness or 2.0,
		shadows = opts.shadows ~= false,
		flicker = true,
	})
	if opts.dress then
		-- ceiling rose, drop rod, shade: dressed pendants read as fixtures,
		-- not floating orbs
		local px, pz = cf.X, cf.Z
		Forge.cyl({
			parent = model, name = "LampRose",
			size = Vector3.new(0.12, 1.2, 1.2),
			cf = CFrame.new(px, 18.95, pz) * CFrame.Angles(0, 0, math.rad(90)),
			color = Palette.BrassDark, material = M.Metal,
			cancollide = false, canquery = false, castshadow = false,
		})
		Forge.cyl({
			parent = model, name = "LampRod",
			size = Vector3.new(0.9, 0.08, 0.08),
			cf = CFrame.new(px, 18.45, pz) * CFrame.Angles(0, 0, math.rad(90)),
			color = Color3.fromRGB(46, 40, 34), material = M.Metal,
			cancollide = false, canquery = false, castshadow = false,
		})
		Forge.cyl({
			parent = model, name = "LampShade",
			size = Vector3.new(0.16, 1.5, 1.5),
			cf = CFrame.new(px, 18.12, pz) * CFrame.Angles(0, 0, math.rad(90)),
			color = Palette.Brass, material = M.Metal, reflectance = 0.25,
			cancollide = false, canquery = false, castshadow = false,
		})
	end
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
		-- open enough that the night reads through; castshadow=false lets
		-- gaslight spill through every pane onto the scrolling embankment
		transparency = 0.62, reflectance = 0.06, castshadow = false,
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

-- opts: {windows = {side -> {bays}} | "all" | "none", paint, openTop, wallH, flat}
local function shell(meta, opts)
	opts = opts or {}
	local x0 = meta.x0
	local cx = x0 + L / 2
	local model = meta.model
	local paint = opts.paint or Palette.CarBody
	local oxblood = paint == Palette.CarBodyAlt or paint == Palette.RedCarBody
	local trim = oxblood and Palette.CarTrimAlt or Palette.CarTrim
	local letterboard = oxblood and Palette.CarLetterboardAlt or Palette.CarLetterboard
	meta.trim = trim

	local function deco(spec)
		spec.parent = model
		spec.cancollide = false
		spec.canquery = false
		if spec.castshadow == nil then
			spec.castshadow = false
		end
		if spec.shape == "wedge" then
			spec.shape = nil
			return Forge.wedge(spec)
		elseif spec.shape == "cyl" then
			spec.shape = nil
			return Forge.cyl(spec)
		elseif spec.shape == "ball" then
			spec.shape = nil
			return Forge.ball(spec)
		end
		return Forge.part(spec)
	end

	-- Floor (the rails and ballast scroll past on the client, selling motion)
	Forge.part({
		parent = model, name = "Floor",
		size = Vector3.new(L, 1, W),
		cf = CFrame.new(cx, FLOOR - 0.5, 0),
		color = Palette.FloorWood, material = M.Planks,
	})

	----------------------------------------------------------------
	-- Undercarriage (every archetype, open cars included)
	----------------------------------------------------------------
	Forge.part({
		parent = model, name = "Skirt",
		size = Vector3.new(L, 2.1, W - 0.4),
		cf = CFrame.new(cx, 8.4, 0),
		color = Palette.CarUnderframe, material = M.Metal,
	})

	-- arch-bar bogies with side frames, springs, journals, axles
	for _, bx in ipairs({ x0 + 9, x0 + L - 9 }) do
		deco({ name = "Bolster", size = Vector3.new(5.4, 1.0, 5.0), cf = CFrame.new(bx, 8.55, 0), color = Color3.fromRGB(20, 20, 22), material = M.Metal })
		for _, side in ipairs({ -1, 1 }) do
			deco({ name = "SideFrame", size = Vector3.new(6.8, 1.3, 0.5), cf = CFrame.new(bx, 8.15, side * 3.25), color = Palette.BogieIron, material = M.Metal })
			deco({ name = "LeafSpring", size = Vector3.new(1.6, 0.5, 0.62), cf = CFrame.new(bx, 8.95, side * 3.25), color = Color3.fromRGB(36, 36, 40), material = M.Metal })
			for _, wx in ipairs({ bx - 2.1, bx + 2.1 }) do
				deco({ name = "Journal", size = Vector3.new(0.6, 0.7, 0.35), cf = CFrame.new(wx, 8.3, side * 3.5), color = Color3.fromRGB(30, 30, 33), material = M.Metal })
			end
		end
		for _, wx in ipairs({ bx - 2.1, bx + 2.1 }) do
			for _, wz in ipairs({ -2.9, 2.9 }) do
				deco({
					shape = "cyl", name = "Wheel",
					size = Vector3.new(0.6, 3.1, 3.1),
					-- axis across the track so the disc face shows from the embankment
					cf = CFrame.new(wx, 8.3, wz) * CFrame.Angles(0, math.rad(90), 0),
					color = Color3.fromRGB(28, 28, 31), material = M.Metal,
				})
			end
			deco({
				shape = "cyl", name = "Axle",
				size = Vector3.new(5.8, 0.35, 0.35),
				cf = CFrame.new(wx, 8.3, 0) * CFrame.Angles(0, math.rad(90), 0),
				color = Color3.fromRGB(40, 40, 44), material = M.Metal,
			})
		end
	end

	-- underframe rigging: truss rods, queen posts, equipment boxes, air tank
	for _, side in ipairs({ -1, 1 }) do
		deco({ shape = "cyl", name = "TrussRod", size = Vector3.new(20, 0.18, 0.18), cf = CFrame.new(cx, 7.5, side * 3.4), color = Color3.fromRGB(46, 44, 46), material = M.Metal, reflectance = 0.08 })
		for _, qx in ipairs({ cx - 5, cx + 5 }) do
			deco({ shape = "cyl", name = "QueenPost", size = Vector3.new(1.0, 0.22, 0.22), cf = CFrame.new(qx, 8.4, side * 3.4) * CFrame.Angles(0, 0, math.rad(90)), color = Color3.fromRGB(40, 40, 42), material = M.Metal })
		end
	end
	deco({ name = "EquipBox", size = Vector3.new(3.2, 1.2, 0.9), cf = CFrame.new(cx - 10, 7.6, -5.0), color = Color3.fromRGB(24, 24, 26), material = M.Metal })
	deco({ name = "EquipBox", size = Vector3.new(3.2, 1.2, 0.9), cf = CFrame.new(cx + 10, 7.6, 5.0), color = Color3.fromRGB(24, 24, 26), material = M.Metal })
	deco({ shape = "cyl", name = "AirTank", size = Vector3.new(4.5, 1.1, 1.1), cf = CFrame.new(cx, 7.5, -1.6), color = Color3.fromRGB(34, 33, 35), material = M.CorrodedMetal })

	-- buffer beams + coupler (front of every car; rear of car 1 for the lobby view)
	for _, endSpec in ipairs({ { x0 + 0.3, -1 }, { x0 + L - 0.3, 1 } }) do
		local ex, dir = endSpec[1], endSpec[2]
		deco({ name = "BufferBeam", size = Vector3.new(0.5, 1.1, 11.2), cf = CFrame.new(ex + dir * 0.15, 8.9, 0), color = Palette.CouplerIron, material = M.DiamondPlate })
		local _ = dir
	end
	deco({ shape = "cyl", name = "Coupler", size = Vector3.new(1.4, 0.5, 0.5), cf = CFrame.new(x0 + L + 0.7, 8.3, 0), color = Palette.CouplerIron, material = M.Metal })
	deco({ name = "Knuckle", size = Vector3.new(0.7, 0.9, 0.7), cf = CFrame.new(x0 + L + 1.4, 8.3, 0), color = Color3.fromRGB(38, 36, 38), material = M.Metal })
	if meta.index == 1 then
		deco({ shape = "cyl", name = "Coupler", size = Vector3.new(1.4, 0.5, 0.5), cf = CFrame.new(x0 - 0.7, 8.3, 0), color = Palette.CouplerIron, material = M.Metal })
		deco({ name = "Knuckle", size = Vector3.new(0.7, 0.9, 0.7), cf = CFrame.new(x0 - 1.4, 8.3, 0), color = Color3.fromRGB(38, 36, 38), material = M.Metal })
	end

	if opts.openTop then
		-- tender-style tub: ribbed walls, no ceiling
		local wallH = opts.wallH or 5
		for _, side in ipairs({ -1, 1 }) do
			Forge.part({
				parent = model, name = "TubWall",
				size = Vector3.new(L, wallH, 0.6),
				cf = CFrame.new(cx, FLOOR + wallH / 2, side * (HALFW - 0.3)),
				color = paint, material = M.Metal,
			})
			for rx = x0 + 4, x0 + 40, 6 do
				deco({ name = "TubRib", size = Vector3.new(0.35, wallH, 0.6), cf = CFrame.new(rx, FLOOR + wallH / 2, side * 6.05), color = Color3.fromRGB(18, 20, 22), material = M.Metal })
			end
			deco({ name = "TubCap", size = Vector3.new(L, 0.35, 0.9), cf = CFrame.new(cx, FLOOR + wallH + 0.15, side * 5.7), color = Color3.fromRGB(30, 32, 34), material = M.Metal, cancollide = true })
		end
		return
	end
	if opts.flat then
		-- flatcar: stake posts + side sill channels and nothing else above deck
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
		for _, side in ipairs({ -1, 1 }) do
			deco({ name = "SillChannel", size = Vector3.new(L, 0.7, 0.4), cf = CFrame.new(cx, 9.55, side * 5.9), color = Palette.CarUnderframe, material = M.Metal })
		end
		return
	end

	----------------------------------------------------------------
	-- Side walls: sill band, framed window band, letterboard
	----------------------------------------------------------------
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
			color = letterboard, material = M.Wood,
		})
		-- interior wainscot tint
		Forge.part({
			parent = model, name = "Wainscot",
			size = Vector3.new(L - 1.2, 3.0, 0.12),
			cf = CFrame.new(cx, 11.55, z - side * 0.38),
			color = Palette.WallPanel, material = M.Wood, cancollide = false,
		})

		local bays
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

		-- mullions become deep jambs: proud of the wall so glass reads inset
		for m = 0, 8 do
			Forge.part({
				parent = model, name = "Mullion",
				size = Vector3.new(0.7, 3.6, 0.9),
				cf = CFrame.new(x0 + 2 + m * 5, 14.9, side * 5.85),
				color = trim, material = M.Wood,
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

		-- continuous lintel + sill courses catch the glass top and bottom
		deco({ name = "HeaderCourse", size = Vector3.new(L, 0.35, 0.5), cf = CFrame.new(cx, 16.85, side * 5.95), color = trim, material = M.Wood, castshadow = true })
		deco({ name = "SillCourse", size = Vector3.new(L, 0.45, 0.6), cf = CFrame.new(cx, 13.0, side * 5.95), color = trim, material = M.Wood, castshadow = true })
		-- gilt striping: beltline + letterboard
		deco({ name = "GiltStripe", size = Vector3.new(L, 0.12, 0.08), cf = CFrame.new(cx, 13.28, side * 6.28), color = Palette.CarLetters, material = M.Smooth, reflectance = 0.15 })
		deco({ name = "GiltStripe", size = Vector3.new(L, 0.12, 0.08), cf = CFrame.new(cx, 16.92, side * 6.23), color = Palette.CarLetters, material = M.Smooth, reflectance = 0.15 })
		-- lower-body battens under the mullions
		for m = 0, 8 do
			deco({
				name = "Batten", size = Vector3.new(0.35, 3.0, 0.4),
				cf = CFrame.new(x0 + 2 + m * 5, 11.5, side * 6.05),
				color = oxblood and Color3.fromRGB(44, 25, 26) or Palette.CarBodyShadow, material = M.Wood,
			})
		end
		-- corner posts anchor the silhouette
		deco({ name = "CornerPost", size = Vector3.new(0.7, 9.0, 0.7), cf = CFrame.new(x0 + 0.35, 14.5, side * 5.95), color = trim, material = M.Wood, castshadow = true })
		deco({ name = "CornerPost", size = Vector3.new(0.7, 9.0, 0.7), cf = CFrame.new(x0 + L - 0.35, 14.5, side * 5.95), color = trim, material = M.Wood, castshadow = true })
	end

	----------------------------------------------------------------
	-- End walls, recessed door surrounds, grab irons, steps, markers
	----------------------------------------------------------------
	for _, endSpec in ipairs({ { x0 + 0.3, -1 }, { x0 + L - 0.3, 1 } }) do
		local ex, dir = endSpec[1], endSpec[2]
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
		-- recessed door surround
		for _, zc in ipairs({ -2.05, 2.05 }) do
			deco({ name = "DoorJamb", size = Vector3.new(0.4, 7.2, 0.5), cf = CFrame.new(ex + dir * 0.2, 13.6, zc), color = trim, material = M.Wood, castshadow = true })
		end
		deco({ name = "DoorLintel", size = Vector3.new(0.4, 0.6, 4.6), cf = CFrame.new(ex + dir * 0.2, 17.3, 0), color = trim, material = M.Wood, castshadow = true })
		-- grab irons
		for _, zc in ipairs({ -2.55, 2.55 }) do
			deco({ shape = "cyl", name = "GrabIron", size = Vector3.new(2.6, 0.15, 0.15), cf = CFrame.new(ex + dir * 0.12, 12.6, zc) * CFrame.Angles(0, 0, math.rad(90)), color = Color3.fromRGB(52, 50, 48), material = M.Metal, reflectance = 0.1 })
		end
		-- corner step wells
		local sx = dir == -1 and x0 + 0.75 or x0 + L - 0.75
		for _, side in ipairs({ -1, 1 }) do
			for _, ty in ipairs({ 8.2, 9.2 }) do
				deco({ name = "StepTread", size = Vector3.new(1.7, 0.22, 0.7), cf = CFrame.new(sx, ty, side * 5.95), color = Color3.fromRGB(44, 44, 48), material = M.DiamondPlate })
			end
			deco({ name = "StepStringer", size = Vector3.new(1.9, 1.7, 0.12), cf = CFrame.new(sx, 8.75, side * 6.3), color = Palette.CarUnderframe, material = M.Metal })
		end
	end
	-- rear marker lamps: only the caboose's stay lit — the tail never goes dark
	for _, side in ipairs({ -1, 1 }) do
		deco({ name = "MarkerBody", size = Vector3.new(0.45, 0.7, 0.45), cf = CFrame.new(x0 - 0.25, 18.5, side * 5.5), color = Color3.fromRGB(26, 26, 28), material = M.Metal })
		local lens = deco({
			shape = "ball", name = "MarkerLens", size = Vector3.new(0.32, 0.32, 0.32),
			cf = CFrame.new(x0 - 0.5, 18.5, side * 5.5),
			color = meta.index == 1 and Palette.EmergencyRed or Palette.MarkerLensDead,
			material = meta.index == 1 and M.Neon or M.Glass,
		})
		if meta.index == 1 then
			Forge.light(lens, { color = Palette.EmergencyRed, range = 8, brightness = 0.5, shadows = false })
		end
	end

	----------------------------------------------------------------
	-- Ceiling + arched clerestory roof (walkable: monitor, shoulders, slopes)
	----------------------------------------------------------------
	Forge.part({
		parent = model, name = "Ceiling",
		size = Vector3.new(L, 0.6, W),
		cf = CFrame.new(cx, CEIL + 0.3, 0),
		color = Palette.Ceiling, material = M.Plaster,
	})
	Forge.part({ -- monitor deck / roof walk
		parent = model, name = "Roof",
		size = Vector3.new(L, 0.9, 2.6),
		cf = CFrame.new(cx, 19.85, 0),
		color = Palette.CarWalkboard, material = M.Planks,
	})
	for _, side in ipairs({ -1, 1 }) do
		Forge.part({
			parent = model, name = "RoofShoulder",
			size = Vector3.new(L, 0.6, 1.8),
			cf = CFrame.new(cx, 19.7, side * 2.15),
			color = Palette.CarRoofCanvas, material = M.Slate,
		})
		Forge.wedge({
			parent = model, name = "RoofSlope",
			size = Vector3.new(L, 0.6, 1.9),
			cf = CFrame.new(cx, 19.7, side * 4.0) * CFrame.Angles(0, side == 1 and math.rad(180) or 0, 0),
			color = Palette.CarRoofCanvas, material = M.Slate,
		})
		deco({ name = "Eaves", size = Vector3.new(L, 0.7, 1.55), cf = CFrame.new(cx, 19.25, side * 5.55), color = trim, material = M.Slate, castshadow = true })
		deco({ name = "DripRail", size = Vector3.new(L, 0.15, 0.2), cf = CFrame.new(cx, 18.82, side * 6.2), color = Palette.CarLetters, material = M.Smooth, reflectance = 0.15 })
		-- clerestory glazing: a warm amber strip along the roofline at night
		deco({ name = "Clerestory", size = Vector3.new(40, 0.28, 0.1), cf = CFrame.new(cx, 20.14, side * 1.34), color = Color3.fromRGB(124, 86, 40), material = M.Glass, transparency = 0.3, reflectance = 0.1 })
	end

	-- roof furniture: torpedo vents + a stove flue
	local ventZ = { 2.0, -2.0, 2.0, -2.0 }
	for vi, vx in ipairs({ x0 + 6, x0 + 14, x0 + 30, x0 + 38 }) do
		deco({ shape = "cyl", name = "VentStem", size = Vector3.new(0.5, 0.55, 0.55), cf = CFrame.new(vx, 20.25, ventZ[vi]) * CFrame.Angles(0, 0, math.rad(90)), color = Color3.fromRGB(40, 40, 44), material = M.Metal })
		deco({ shape = "ball", name = "VentCap", size = Vector3.new(0.8, 0.5, 0.8), cf = CFrame.new(vx, 20.62, ventZ[vi]), color = Color3.fromRGB(34, 34, 38), material = M.Metal })
	end
	deco({ name = "FluePad", size = Vector3.new(0.7, 0.25, 0.7), cf = CFrame.new(x0 + 5, 19.8, -3.6), color = Color3.fromRGB(30, 30, 32), material = M.Metal })
	local flue = deco({ shape = "cyl", name = "Flue", size = Vector3.new(2.0, 0.5, 0.5), cf = CFrame.new(x0 + 5, 20.9, -3.6) * CFrame.Angles(0, 0, math.rad(90)), color = Color3.fromRGB(30, 30, 32), material = M.CorrodedMetal })
	deco({ shape = "cyl", name = "FlueCap", size = Vector3.new(0.15, 0.85, 0.85), cf = CFrame.new(x0 + 5, 21.97, -3.6) * CFrame.Angles(0, 0, math.rad(90)), color = Color3.fromRGB(26, 26, 28), material = M.Metal })
	if meta.archetype == "caboose" then
		local att = Forge.attach(flue, CFrame.new(1.1, 0, 0))
		Forge.particles(att, {
			color = ColorSequence.new(Color3.fromRGB(60, 58, 56)),
			size = NumberSequence.new(0.6, 2.4),
			transparency = NumberSequence.new(0.55, 1),
			lifetime = NumberRange.new(1.2, 2.2),
			rate = 3,
			speed = NumberRange.new(2, 4),
			accel = Vector3.new(-8, 2, 0),
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
			color = letterboard, material = M.Wood, cancollide = false, canquery = false, castshadow = false,
		})
		-- NormalId.Front is the -Z face; the outward face on the +Z side is Back
		Forge.surfaceText(band, side == 1 and Enum.NormalId.Back or Enum.NormalId.Front, "THE  11:59", {
			color = Palette.CarLetters, font = Palette.FontHeader, pps = 44,
			lightInfluence = 0.55, brightness = 1.1,
		})
		local plaque = Forge.part({
			parent = model, name = "Plaque",
			-- below the sill course and clear of the battens so it never occludes
			size = Vector3.new(2.6, 1, 0.1),
			cf = CFrame.new(x0 + 4.5, 12.25, side * (HALFW + 0.02)),
			color = Color3.fromRGB(20, 22, 20), material = M.Metal, cancollide = false, canquery = false, castshadow = false,
		})
		Forge.surfaceText(plaque, side == 1 and Enum.NormalId.Back or Enum.NormalId.Front, string.format("CAR %02d", meta.index), {
			color = Palette.CarLetters, font = Palette.FontHeader, pps = 60,
			lightInfluence = 1,
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
			-- headrest roll along the backrest top
			Forge.cyl({
				parent = meta.model, name = "Headrest",
				size = Vector3.new(3.5, 0.42, 0.42),
				cf = CFrame.new(x - facing * 0.95, 13.85, zc) * CFrame.Angles(0, math.rad(90), 0),
				color = leather, material = M.Leather,
				cancollide = false, canquery = false, castshadow = false,
			})
			-- aisle armrest: wood post, brass cap (never traps the hide entry)
			Forge.part({
				parent = meta.model, name = "ArmrestPost",
				size = Vector3.new(0.25, 1.0, 0.25),
				cf = CFrame.new(x, 12.15, side * 1.62),
				color = Palette.WoodTrim, material = M.Wood,
				cancollide = false, canquery = false, castshadow = false,
			})
			Forge.cyl({
				parent = meta.model, name = "ArmrestCap",
				size = Vector3.new(1.6, 0.18, 0.18),
				cf = CFrame.new(x, 12.7, side * 1.62),
				color = Palette.BrassDark, material = M.Metal,
				cancollide = false, canquery = false, castshadow = false,
			})
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
			color = Palette.Brass, material = M.Metal, reflectance = 0.3,
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
	opts = opts or { swing = true }
	if opts.dress == nil then
		opts.dress = true
	end
	local gap = L / (count + 1)
	for k = 1, count do
		addLamp(meta, CFrame.new(x0 + gap * k, 17.5, 0), opts)
	end
end

----------------------------------------------------------------
-- Dressing kits: non-gameplay set decoration. Everything here is
-- walk-through (no collide, no query) and draws from meta.drng so the
-- gameplay rng stream (hides, crates, loot) stays byte-identical.
----------------------------------------------------------------
local function dress(meta, spec)
	spec.parent = spec.parent or meta.model
	if spec.cancollide == nil then
		spec.cancollide = false
	end
	if spec.canquery == nil then
		spec.canquery = false
	end
	if spec.castshadow == nil then
		spec.castshadow = false
	end
	local shape = spec.shape
	spec.shape = nil
	if shape == "cyl" then
		return Forge.cyl(spec)
	elseif shape == "ball" then
		return Forge.ball(spec)
	elseif shape == "wedge" then
		return Forge.wedge(spec)
	end
	return Forge.part(spec)
end

-- K1: carpet runner down the aisle with brass trim strips.
-- zc shifts it off-center for cars whose walking line isn't z=0 (sleeper).
local function kitRunner(meta, mainColor, trimColor, zc)
	zc = zc or 0
	local cx = meta.x0 + L / 2
	dress(meta, {
		name = "Runner", size = Vector3.new(40, 0.08, 3.0),
		cf = CFrame.new(cx, 10.05, zc),
		color = mainColor or Palette.CarpetRunner, material = M.Carpet,
	})
	for _, side in ipairs({ -1, 1 }) do
		dress(meta, {
			name = "RunnerTrim", size = Vector3.new(40, 0.06, 0.22),
			cf = CFrame.new(cx, 10.06, zc + side * 1.58),
			color = trimColor or Palette.BrassDark, material = M.Metal, reflectance = 0.15,
		})
	end
end

-- K2: ceiling ribs, cove fillets, picture rails
local function kitCeiling(meta, opts)
	opts = opts or {}
	local x0 = meta.x0
	local cx = x0 + L / 2
	local step = opts.ribEvery or 5
	for m = 0, 8, step == 10 and 2 or 1 do
		dress(meta, {
			name = "CeilRib", size = Vector3.new(0.35, 0.18, 9.0),
			cf = CFrame.new(x0 + 2 + m * 5, 18.91, 0),
			color = opts.ribColor or Palette.CeilingRib,
			material = opts.ribMaterial or M.Wood,
		})
	end
	if opts.coves ~= false then
		-- sloped face down into the room, vertical face flush to the wall
		dress(meta, {
			name = "CeilCove", shape = "wedge", size = Vector3.new(42.4, 0.8, 0.8),
			cf = CFrame.new(cx, 18.6, 5.0) * CFrame.Angles(0, 0, math.pi),
			color = Palette.Ceiling, material = M.Plaster,
		})
		dress(meta, {
			name = "CeilCove", shape = "wedge", size = Vector3.new(42.4, 0.8, 0.8),
			cf = CFrame.new(cx, 18.6, -5.0) * CFrame.Angles(math.pi, 0, 0),
			color = Palette.Ceiling, material = M.Plaster,
		})
	end
	if opts.rails ~= false then
		for _, side in ipairs({ -1, 1 }) do
			dress(meta, {
				name = "PictureRail", size = Vector3.new(42.8, 0.18, 0.1),
				cf = CFrame.new(cx, 16.72, side * 5.32),
				color = Palette.Brass, material = M.Metal, reflectance = 0.2,
			})
		end
	end
end

-- K3: wainscot cap rail, skirting, stiles
local function kitWainscot(meta, sides, stileColor)
	local x0 = meta.x0
	local cx = x0 + L / 2
	local col = stileColor or Palette.WoodTrim
	for _, side in ipairs(sides or { -1, 1 }) do
		dress(meta, {
			name = "WainscotCap", size = Vector3.new(42.8, 0.25, 0.1),
			cf = CFrame.new(cx, 13.1, side * 5.22),
			color = col, material = M.Wood,
		})
		dress(meta, {
			name = "Skirting", size = Vector3.new(42.8, 0.45, 0.08),
			cf = CFrame.new(cx, 10.25, side * 5.24),
			color = col, material = M.Wood,
		})
		for m = 0, 8 do
			dress(meta, {
				name = "WainscotStile", size = Vector3.new(0.5, 3.0, 0.1),
				cf = CFrame.new(x0 + 2 + m * 5, 11.55, side * 5.22),
				color = col, material = M.Wood,
			})
		end
	end
end

-- K4: curtains, iterating each archetype's registered windows.
-- Panel outer face 5.26, rod outer 5.35 — clear of the blind slab (5.375).
local function kitCurtains(meta, style, sideFilter)
	local drng = meta.drng
	for _, win in ipairs(meta.windows) do
		local side = win.side
		if not sideFilter or side == sideFilter then
			if style == "cafe" then
				dress(meta, {
					name = "CurtainRod", shape = "cyl", size = Vector3.new(4.4, 0.08, 0.08),
					cf = CFrame.new(win.x, 14.85, side * 5.18),
					color = Palette.BrassDark, material = M.Metal,
				})
				dress(meta, {
					name = "CafeCurtain", size = Vector3.new(3.9, 1.6, 0.14),
					cf = CFrame.new(win.x, 13.95, side * 5.12),
					color = Palette.CurtainCream, material = M.Fabric,
				})
			elseif style == "torn" then
				for _ = 1, 2 do
					local off = drng:NextNumber(0.6, 1.6) * (drng:NextNumber() < 0.5 and -1 or 1)
					dress(meta, {
						name = "TornCurtain", size = Vector3.new(0.4, 2.2, 0.1),
						cf = CFrame.new(win.x + off, 15.4, side * 5.18)
							* CFrame.Angles(0, 0, drng:NextNumber(-0.25, 0.25)),
						color = Color3.fromRGB(44, 20, 22), material = M.Fabric,
					})
				end
			else
				dress(meta, {
					name = "CurtainRod", shape = "cyl", size = Vector3.new(4.6, 0.1, 0.1),
					cf = CFrame.new(win.x, 16.85, side * 5.30),
					color = Palette.BrassDark, material = M.Metal,
				})
				for _, dx in ipairs({ -1.85, 1.85 }) do
					dress(meta, {
						name = "CurtainPanel", size = Vector3.new(0.65, 3.7, 0.16),
						cf = CFrame.new(win.x + dx, 14.95, side * 5.18),
						color = Palette.Curtain, material = M.Fabric,
					})
				end
			end
		end
	end
end

-- K5: wall sconce (registers via addLamp — flickers, dies with lamp-outs)
local function kitSconce(meta, x, side, yGlobe)
	yGlobe = yGlobe or 16.35
	dress(meta, {
		name = "SconcePlate", size = Vector3.new(0.4, 0.9, 0.08),
		cf = CFrame.new(x, yGlobe - 0.4, side * 5.28),
		color = Palette.WoodTrim, material = M.Wood,
	})
	addLamp(meta, CFrame.new(x, yGlobe, side * 4.95), {
		scale = 0.7, stem = 0.6, range = 7, brightness = 0.5, shadows = false,
	})
end

-- K7: brass retaining rails along the luggage racks (coach)
local function kitRackRail(meta)
	local x0 = meta.x0
	local cx = x0 + L / 2
	for _, side in ipairs({ -1, 1 }) do
		dress(meta, {
			name = "RackRail", shape = "cyl", size = Vector3.new(32, 0.1, 0.1),
			cf = CFrame.new(cx, 17.15, side * 3.85),
			color = Palette.Brass, material = M.Metal, reflectance = 0.2,
		})
		for _, x in ipairs({ x0 + 8, x0 + 15, x0 + 22, x0 + 29, x0 + 36 }) do
			dress(meta, {
				name = "RackBracket", shape = "cyl", size = Vector3.new(1.7, 0.1, 0.1),
				cf = CFrame.new(x, 16.4, side * 4.6)
					* CFrame.Angles(math.rad(-side * 30), 0, 0)
					* CFrame.Angles(0, math.rad(90), 0),
				color = Palette.BrassDark, material = M.Metal,
			})
		end
	end
end

-- K9: period advertisement cards above the windows
local function kitAdCards(meta, texts, side)
	for i, text in ipairs(texts) do
		local x = meta.x0 + 13 + (i - 1) * 9
		local card = dress(meta, {
			name = "AdCard", size = Vector3.new(1.9, 0.9, 0.06),
			cf = CFrame.new(x, 17.4, side * 5.34),
			color = Palette.UIPaperDim, material = M.Plaster,
		})
		Forge.surfaceText(card, side == 1 and Enum.NormalId.Front or Enum.NormalId.Back, text, {
			color = Palette.UIInk, font = Palette.FontHeader, pps = 30, lightInfluence = 1,
		})
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
	-- 3 pendants over 6 bench rows: alternating pools, dark bands between
	pendantLamps(meta, 3)

	local x0 = meta.x0
	local drng = meta.drng
	kitRunner(meta)
	kitCeiling(meta)
	kitWainscot(meta)
	kitCurtains(meta, "full")
	kitRackRail(meta)
	for _, sx in ipairs({ x0 + 12, x0 + 32 }) do
		kitSconce(meta, sx, -1, 15.9)
		kitSconce(meta, sx, 1, 15.9)
	end
	kitAdCards(meta, { "SMOKE ELSEWHERE", "THE LINE PROVIDES", "SLEEP THROUGH THE STOPS" }, 1)
	kitAdCards(meta, { "MIND THE GAP AT SPEED", "TERMINUS BY DAWN", "REPORT ALL WHISTLING" }, -1)

	-- end-wall coat hooks; a couple still hold coats
	local hookSpots = {
		{ x0 + 0.65, -2.7 }, { x0 + 0.65, 2.7 },
		{ x0 + L - 0.65, -2.7 }, { x0 + L - 0.65, 2.7 },
	}
	local coatA = drng:NextInteger(1, 4)
	local coatB = (coatA + drng:NextInteger(1, 3) - 1) % 4 + 1
	for i, spot in ipairs(hookSpots) do
		dress(meta, {
			name = "CoatHook", size = Vector3.new(0.12, 0.35, 0.2),
			cf = CFrame.new(spot[1], 15.6, spot[2]),
			color = Palette.BrassDark, material = M.Metal,
		})
		if i == coatA or i == coatB then
			dress(meta, {
				name = "Coat", size = Vector3.new(0.9, 2.2, 0.3),
				cf = CFrame.new(spot[1], 14.35, spot[2]),
				color = i % 2 == 0 and Color3.fromRGB(36, 34, 40) or Color3.fromRGB(52, 40, 30),
				material = M.Fabric,
			})
		end
	end
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
	Forge.light(ember, { color = Palette.FurnaceCore, range = 13, brightness = 1.6, flicker = true, shadows = true })
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
		color = Palette.Brass, material = M.Metal, reflectance = 0.3,
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
			-- x picked so the cafe curtains at bays 2/4/6 clear the frames
			size = Vector3.new(4.6, 2.6, 0.15),
			cf = CFrame.new(x0 + 4.5 + k * 10, 15, 5.28),
			color = Palette.UIPaperDim, material = M.Plaster, cancollide = false,
		})
		-- the poster hangs on the +Z wall; its readable face is -Z (Front)
		Forge.surfaceText(sign, Enum.NormalId.Front, text, {
			color = Palette.UIInk, font = Palette.FontHeader, pps = 34, lightInfluence = 1,
		})
	end

	pendantLamps(meta, 3)

	-- lived-in warmth: the one car on the train somebody calls home
	kitCeiling(meta)
	kitWainscot(meta)
	kitCurtains(meta, "cafe")
	dress(meta, {
		name = "BraidedRug", shape = "cyl", size = Vector3.new(0.09, 4.6, 4.6),
		cf = CFrame.new(x0 + 7, 10.06, -2.6) * CFrame.Angles(0, 0, math.rad(90)),
		color = Palette.RugWarm, material = M.Carpet,
	})
	dress(meta, {
		name = "StoveFender", size = Vector3.new(2.6, 0.06, 2.2),
		cf = CFrame.new(x0 + 5, 10.04, -3.7),
		color = Color3.fromRGB(52, 50, 50), material = M.DiamondPlate,
	})
	Forge.ring({
		parent = meta.model, name = "Woodbox",
		width = 1.7, height = 1.1, thick = 0.15, depth = 1.7,
		cf = CFrame.new(x0 + 2.8, 10.6, -4.2),
		color = Palette.WoodTrim, material = M.Planks,
	})
	for _, log in ipairs({ { 10.45, -4.55 }, { 10.45, -4.2 }, { 10.45, -3.85 }, { 10.85, -4.2 } }) do
		dress(meta, {
			name = "Firewood", shape = "cyl", size = Vector3.new(1.4, 0.42, 0.42),
			cf = CFrame.new(x0 + 2.8, log[1], log[2]),
			color = Color3.fromRGB(78, 58, 38), material = M.Wood,
		})
	end
	dress(meta, {
		name = "Kettle", shape = "ball", size = Vector3.new(0.75, 0.6, 0.75),
		cf = CFrame.new(x0 + 4.2, 12.75, -3.9),
		color = Color3.fromRGB(40, 40, 44), material = M.Metal,
	})
	dress(meta, {
		name = "KettleSpout", shape = "cyl", size = Vector3.new(0.5, 0.12, 0.12),
		cf = CFrame.new(x0 + 3.75, 12.85, -3.9) * CFrame.Angles(0, 0, math.rad(35)),
		color = Color3.fromRGB(40, 40, 44), material = M.Metal,
	})
	dress(meta, {
		name = "Mantel", size = Vector3.new(2.6, 0.12, 0.7),
		cf = CFrame.new(x0 + 8.5, 14.0, -5.0),
		color = Palette.WoodTrim, material = M.Wood,
	})
	for _, mz in ipairs({ -4.85, -5.15 }) do
		dress(meta, {
			name = "TinMug", shape = "cyl", size = Vector3.new(0.3, 0.3, 0.3),
			cf = CFrame.new(x0 + 9.2, 14.21, mz) * CFrame.Angles(0, 0, math.rad(90)),
			color = Color3.fromRGB(150, 150, 154), material = M.Metal,
		})
	end
	addLamp(meta, CFrame.new(x0 + 8.5, 14.75, -4.9), {
		scale = 0.5, stem = 0.4, range = 8, brightness = 0.5, shadows = false,
	})
	-- stove-side chair, facing the fire
	dress(meta, {
		name = "ChairSeat", size = Vector3.new(1.5, 0.25, 1.5),
		cf = CFrame.new(x0 + 7.5, 11.3, -4.0),
		color = Palette.SleeperWood, material = M.Wood,
	})
	dress(meta, {
		name = "ChairBack", size = Vector3.new(0.25, 1.6, 1.5),
		cf = CFrame.new(x0 + 8.25, 12.2, -4.0),
		color = Palette.SleeperWood, material = M.Wood,
	})
	for _, cz in ipairs({ -3.4, -4.6 }) do
		dress(meta, {
			name = "ChairLeg", size = Vector3.new(0.2, 1.2, 0.2),
			cf = CFrame.new(x0 + 6.85, 10.7, cz),
			color = Palette.SleeperWood, material = M.Wood,
		})
	end
	-- desk clutter on the lever table
	dress(meta, {
		name = "Logbook", size = Vector3.new(0.7, 0.08, 0.5),
		cf = CFrame.new(x0 + 11.5, 12.4, 3.5) * CFrame.Angles(0, 0.2, 0),
		color = Palette.UIPaper, material = M.Smooth,
	})
	dress(meta, {
		name = "InkPot", shape = "cyl", size = Vector3.new(0.2, 0.25, 0.25),
		cf = CFrame.new(x0 + 12.1, 12.46, 3.1) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(20, 20, 24), material = M.Glass,
	})
	dress(meta, {
		name = "TinCup", shape = "cyl", size = Vector3.new(0.3, 0.35, 0.35),
		cf = CFrame.new(x0 + 12.8, 12.51, 4.0) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(150, 150, 154), material = M.Metal,
	})
	-- coats by the rear door
	for i, hz in ipairs({ -2.6, -3.3 }) do
		dress(meta, {
			name = "CoatHook", size = Vector3.new(0.12, 0.35, 0.2),
			cf = CFrame.new(x0 + 0.65, 15.8, hz),
			color = Palette.BrassDark, material = M.Metal,
		})
		dress(meta, {
			name = "Coat", size = Vector3.new(0.9, 2.3, 0.35),
			cf = CFrame.new(x0 + 0.72, 14.5, hz),
			color = i == 1 and Color3.fromRGB(36, 34, 40) or Color3.fromRGB(52, 40, 30),
			material = M.Fabric,
		})
	end
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
		-- sconce: private amber cell per compartment
		addLamp(meta, CFrame.new(cx, 16.4, -3.4), {
			range = 7.5, brightness = 1.3, scale = 0.8, shadows = false,
			color = Color3.fromRGB(255, 158, 66),
		})
	end
	-- corridor lamps: the corridor stays darker than the compartments
	addLamp(meta, CFrame.new(x0 + 12, 17.5, 3.6), { swing = true, brightness = 1.8, range = 10 })
	addLamp(meta, CFrame.new(x0 + 30, 17.5, 3.6), { swing = true, brightness = 1.8, range = 10 })

	-- runner follows the corridor, not the car centerline
	kitRunner(meta, nil, nil, 3.2)
	kitCeiling(meta)
	-- curtain only the corridor side; compartment bays clip the lockers
	kitCurtains(meta, "full", 1)
	kitWainscot(meta, { 1 })
	dress(meta, {
		name = "Handrail", shape = "cyl", size = Vector3.new(34, 0.14, 0.14),
		cf = CFrame.new(x0 + 22, 13.0, 5.24),
		color = Palette.Brass, material = M.Metal, reflectance = 0.2,
	})
	for _, px in ipairs({ x0 + 9, x0 + 19, x0 + 29 }) do
		dress(meta, {
			name = "DoorHeader", size = Vector3.new(0.5, 0.9, 10.8),
			cf = CFrame.new(px, 18.3, 0),
			color = Palette.WallPanel, material = M.Wood,
		})
		dress(meta, {
			name = "Pilaster", size = Vector3.new(0.45, 7.4, 0.45),
			cf = CFrame.new(px, 13.7, 1.35),
			color = Palette.WoodTrim, material = M.Wood, castshadow = true,
		})
	end
	for c = 0, 3 do
		local cxc = x0 + 4 + c * 10
		local plaque = dress(meta, {
			name = "BerthPlaque", size = Vector3.new(0.5, 0.6, 0.06),
			cf = CFrame.new(cxc + 2, 16.3, 1.28),
			color = Palette.Brass, material = M.Metal,
		})
		Forge.surfaceText(plaque, Enum.NormalId.Back, tostring(c + 1), {
			color = Color3.fromRGB(30, 24, 20), font = Palette.FontTitle, pps = 40, lightInfluence = 1,
		})
		-- half-drawn lower berth curtain, tied roll above
		dress(meta, {
			name = "BerthCurtain", size = Vector3.new(2.6, 2.6, 0.14),
			cf = CFrame.new(cxc - 0.7, 12.9, -2.75),
			color = Palette.Curtain, material = M.Fabric,
		})
		dress(meta, {
			name = "BerthRoll", shape = "cyl", size = Vector3.new(2.4, 0.3, 0.3),
			cf = CFrame.new(cxc + 0.5, 15.3, -2.75),
			color = Palette.Curtain, material = M.Fabric,
		})
		-- bunk ladder
		for _, lx in ipairs({ cxc + 2.4, cxc + 2.9 }) do
			dress(meta, {
				name = "LadderRail", shape = "cyl", size = Vector3.new(3.4, 0.12, 0.12),
				cf = CFrame.new(lx, 12.9, -2.8) * CFrame.Angles(0, 0, math.rad(90)),
				color = Palette.BrassDark, material = M.Metal,
			})
		end
		for _, ry in ipairs({ 12.0, 13.4 }) do
			dress(meta, {
				name = "LadderRung", shape = "cyl", size = Vector3.new(0.62, 0.1, 0.1),
				cf = CFrame.new(cxc + 2.65, ry, -2.8),
				color = Palette.BrassDark, material = M.Metal,
			})
		end
	end
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
			-- intimate table pools; the center aisle stays a dim runway
			addLamp(meta, CFrame.new(bx, FLOOR + 3.3, zc), {
				range = 6, brightness = 1.1, scale = 0.55, shadows = false,
				color = Color3.fromRGB(255, 172, 84),
			})
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
		color = Palette.Brass, material = M.Metal, reflectance = 0.35,
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
		color = Palette.UIPaper, font = Palette.FontHeader, pps = 40, lightInfluence = 1,
	})
	if rng:NextNumber() > 0.5 then
		suitcase(meta, CFrame.new(x0 + 4, FLOOR + 0.95, 3.9), rng, true)
	end

	-- dressing: last service was never cleared
	kitRunner(meta)
	kitCeiling(meta)
	kitWainscot(meta)
	kitCurtains(meta, "full")
	for _, sx in ipairs({ x0 + 12, x0 + 32 }) do
		kitSconce(meta, sx, -1, 16.35)
		kitSconce(meta, sx, 1, 16.35)
	end
	for _, px in ipairs({ x0 + 11, x0 + 22, x0 + 33 }) do
		addLamp(meta, CFrame.new(px, 17.5, 0), { dress = true, swing = true })
	end
	-- table settings
	local tableIndex = 0
	for _, side in ipairs({ -1, 1 }) do
		for b = 0, 3 do
			tableIndex += 1
			local bx = x0 + 7 + b * 8
			local zc = side * 3.5
			for _, po in ipairs({ { -0.8, 0.5 }, { 0.8, -0.5 } }) do
				dress(meta, {
					name = "Plate", shape = "cyl", size = Vector3.new(0.08, 0.75, 0.75),
					cf = CFrame.new(bx + po[1], 12.7, zc + po[2]) * CFrame.Angles(0, 0, math.rad(90)),
					color = Palette.Bone, material = M.Smooth,
				})
			end
			dress(meta, {
				name = "Bottle", shape = "cyl", size = Vector3.new(0.85, 0.28, 0.28),
				cf = CFrame.new(bx + 0.4, 13.1, zc - 0.6) * CFrame.Angles(0, 0, math.rad(90)),
				color = tableIndex % 2 == 0 and Palette.BottleGreen or Palette.BottleAmber,
				material = M.Glass, transparency = 0.2,
			})
		end
	end
	-- back-bar: mirror, shelves, ten bottles nobody will pour again
	dress(meta, {
		name = "BarMirror", size = Vector3.new(0.1, 3.2, 3.6),
		cf = CFrame.new(x0 + 43.35, 15.2, -3.7),
		color = Color3.fromRGB(16, 18, 22), material = M.Glass, reflectance = 0.55,
	})
	local bottleHues = { Palette.BottleGreen, Palette.BottleAmber, Color3.fromRGB(60, 22, 20) }
	local drng = meta.drng
	for si, sy in ipairs({ 14.2, 15.6 }) do
		dress(meta, {
			name = "BarShelf", size = Vector3.new(0.9, 0.15, 3.4),
			cf = CFrame.new(x0 + 43.0, sy, -3.7),
			color = Palette.WoodTrim, material = M.Wood,
		})
		for bi = 0, 4 do
			local bh = drng:NextNumber(0.8, 1.3)
			dress(meta, {
				name = "BarBottle", shape = "cyl", size = Vector3.new(bh, 0.26, 0.26),
				cf = CFrame.new(x0 + 43.0, sy + 0.075 + bh / 2, -5.2 + bi * 0.75)
					* CFrame.Angles(0, 0, math.rad(90)),
				color = bottleHues[(si + bi) % 3 + 1],
				material = M.Glass, transparency = 0.15,
			})
		end
	end
	for _, stz in ipairs({ -1.7, -4.1 }) do
		dress(meta, {
			name = "StoolPost", shape = "cyl", size = Vector3.new(1.9, 0.35, 0.35),
			cf = CFrame.new(x0 + 36.7, 10.95, stz) * CFrame.Angles(0, 0, math.rad(90)),
			color = Color3.fromRGB(30, 26, 24), material = M.Metal,
		})
		dress(meta, {
			name = "StoolSeat", shape = "cyl", size = Vector3.new(0.25, 1.3, 1.3),
			cf = CFrame.new(x0 + 36.7, 11.95, stz) * CFrame.Angles(0, 0, math.rad(90)),
			color = Palette.SeatLeather, material = M.Leather,
		})
	end
	dress(meta, {
		name = "FootRail", shape = "cyl", size = Vector3.new(5.4, 0.14, 0.14),
		cf = CFrame.new(x0 + 37.0, 10.5, -2.9) * CFrame.Angles(0, math.rad(90), 0),
		color = Palette.Brass, material = M.Metal, reflectance = 0.3,
	})
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

	-- dressing: a parlor mid-evening, guests missing
	local drng = meta.drng
	kitCeiling(meta)
	kitWainscot(meta)
	kitCurtains(meta, "full")
	for _, sx in ipairs({ x0 + 12, x0 + 32 }) do
		kitSconce(meta, sx, -1)
		kitSconce(meta, sx, 1)
	end
	-- rug under the sofas instead of a runner
	dress(meta, {
		name = "Rug", size = Vector3.new(9, 0.08, 7.4),
		cf = CFrame.new(x0 + 12, 10.09, 0),
		color = Color3.fromRGB(52, 38, 30), material = M.Carpet,
	})
	for _, side in ipairs({ -1, 1 }) do
		dress(meta, {
			name = "RugBorder", size = Vector3.new(9, 0.06, 0.5),
			cf = CFrame.new(x0 + 12, 10.14, side * 3.2),
			color = Palette.CarpetRunner, material = M.Fabric,
		})
	end
	dress(meta, {
		name = "RugMedallion", shape = "cyl", size = Vector3.new(0.05, 2.6, 2.6),
		cf = CFrame.new(x0 + 12, 10.16, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color = Palette.CarpetRunner, material = M.Carpet,
	})
	-- framed prints on the end walls
	for _, art in ipairs({
		{ x0 + 0.62, x0 + 0.68, Enum.NormalId.Right },
		{ x0 + L - 0.62, x0 + L - 0.68, Enum.NormalId.Left },
	}) do
		for _, side in ipairs({ -1, 1 }) do
			dress(meta, {
				name = "ArtFrame", size = Vector3.new(0.1, 2.6, 1.9),
				cf = CFrame.new(art[1], 15.0, side * 3.9),
				color = Palette.BrassDark, material = M.Wood,
			})
			local mat = dress(meta, {
				name = "ArtMat", size = Vector3.new(0.06, 2.2, 1.5),
				cf = CFrame.new(art[2], 15.0, side * 3.9),
				color = Color3.fromRGB(30, 34, 30), material = M.Plaster,
			})
			Forge.surfaceText(mat, art[3], "the gorge — 1898", {
				color = Color3.fromRGB(150, 146, 134), font = Palette.FontTitle,
				pps = 24, lightInfluence = 1,
			})
		end
	end
	-- abandoned drink cart
	for _, px in ipairs({ x0 + 25, x0 + 27 }) do
		dress(meta, {
			name = "CartPanel", size = Vector3.new(0.12, 1.4, 1.3),
			cf = CFrame.new(px, 11.0, 3.9),
			color = Palette.WoodTrim, material = M.Wood,
		})
	end
	for _, sy in ipairs({ 10.45, 11.6 }) do
		dress(meta, {
			name = "CartShelf", size = Vector3.new(2.2, 0.12, 1.3),
			cf = CFrame.new(x0 + 26, sy, 3.9),
			color = Palette.WoodTrim, material = M.Wood,
		})
	end
	dress(meta, {
		name = "CartHandle", shape = "cyl", size = Vector3.new(1.3, 0.1, 0.1),
		cf = CFrame.new(x0 + 27.1, 12.0, 3.9) * CFrame.Angles(0, math.rad(90), 0),
		color = Palette.BrassDark, material = M.Metal,
	})
	for k = 0, 1 do
		dress(meta, {
			name = "CartBottle", shape = "cyl", size = Vector3.new(0.85, 0.28, 0.28),
			cf = CFrame.new(x0 + 25.6 + k * 0.7, 12.09, 3.7 + k * 0.4)
				* CFrame.Angles(0, 0, math.rad(90)),
			color = k == 0 and Palette.BottleGreen or Palette.BottleAmber,
			material = M.Glass, transparency = 0.2,
		})
		dress(meta, {
			name = "CartGlass", shape = "cyl", size = Vector3.new(0.35, 0.22, 0.22),
			cf = CFrame.new(x0 + 26.4 + k * 0.5, 11.84, 4.2 - k * 0.5)
				* CFrame.Angles(0, 0, math.rad(90)),
			color = Color3.fromRGB(200, 208, 216), material = M.Glass, transparency = 0.4,
		})
	end
	-- book spines proud of the shelf front
	local spineHues = {
		Color3.fromRGB(58, 30, 26), Color3.fromRGB(30, 42, 54), Color3.fromRGB(90, 74, 40),
		Color3.fromRGB(38, 50, 38), Color3.fromRGB(70, 38, 24), Color3.fromRGB(24, 26, 30),
	}
	local spineIdx = 0
	for _, ry in ipairs({ 12.1, 14.0 }) do
		for k = 0, 2 do
			spineIdx += 1
			dress(meta, {
				name = "BookSpine", size = Vector3.new(0.15, drng:NextNumber(0.9, 1.3), 0.28),
				cf = CFrame.new(x0 + 38.35, ry, 2.7 + k * 1.2),
				color = spineHues[spineIdx], material = M.Smooth,
			})
		end
	end
	-- the piano was mid-song
	dress(meta, {
		name = "SheetMusic", size = Vector3.new(0.03, 0.7, 0.55),
		cf = CFrame.new(x0 + 31.85, 13.35, -3.4) * CFrame.Angles(0, 0, math.rad(-12)),
		color = Palette.UIPaper, material = M.Smooth,
	})
	for _, cz in ipairs({ -2.4, -4.4 }) do
		dress(meta, {
			name = "CandleStick", size = Vector3.new(0.25, 0.8, 0.25),
			cf = CFrame.new(x0 + 33, 13.8, cz),
			color = Color3.fromRGB(220, 208, 180), material = M.Smooth,
		})
		dress(meta, {
			name = "CandleFlame", size = Vector3.new(0.14, 0.28, 0.14),
			cf = CFrame.new(x0 + 33, 14.34, cz),
			color = Color3.fromRGB(255, 120, 60), material = M.Neon,
		})
	end
	dress(meta, {
		name = "AshtrayPost", shape = "cyl", size = Vector3.new(1.1, 0.15, 0.15),
		cf = CFrame.new(x0 + 8.5, 10.55, 2.1) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(30, 26, 24), material = M.Metal,
	})
	dress(meta, {
		name = "AshtrayTray", shape = "cyl", size = Vector3.new(0.08, 0.5, 0.5),
		cf = CFrame.new(x0 + 8.5, 11.15, 2.1) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(30, 26, 24), material = M.Metal,
	})
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
	local stencilCrates = {}
	for _, s in ipairs(spots) do
		if rng:NextNumber() < 0.5 then
			local lootable = lootLeft > 0 and rng:NextNumber() < 0.45
			if lootable then
				lootLeft -= 1
				lootablePlaced += 1
			end
			local box = crate(meta, CFrame.new(s[1], FLOOR + 1.2, s[2]), rng, lootable)
			if #stencilCrates < 3 then
				table.insert(stencilCrates, box)
			end
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
	-- one hard swinging pool mid-car; black at both ends
	local swingGlow = addLamp(meta, CFrame.new(x0 + L / 2, 17.3, 0), { swing = true, range = 12, brightness = 1.6 })

	-- dressing: dim, hollow, worked-in
	local drng = meta.drng
	kitCeiling(meta, { ribEvery = 10, ribColor = Color3.fromRGB(40, 38, 36), ribMaterial = M.Metal, coves = false, rails = false })
	for _, side in ipairs({ -1, 1 }) do
		for _, gy in ipairs({ 12.8, 16.2 }) do
			dress(meta, {
				name = "Girt", size = Vector3.new(42, 0.35, 0.12),
				cf = CFrame.new(x0 + 22, gy, side * 5.30),
				color = Color3.fromRGB(44, 40, 36), material = M.CorrodedMetal,
			})
		end
		for _, m in ipairs({ 1, 3, 5, 7 }) do
			dress(meta, {
				name = "HatBrace", size = Vector3.new(0.5, 8.4, 0.14),
				cf = CFrame.new(x0 + 2 + m * 5, 14.2, side * 5.28),
				color = Color3.fromRGB(44, 40, 36), material = M.CorrodedMetal,
			})
		end
	end
	for _ = 1, 6 do
		dress(meta, {
			name = "FloorStain", size = Vector3.new(drng:NextNumber(2, 4), 0.03, drng:NextNumber(1.5, 3)),
			cf = CFrame.new(x0 + drng:NextNumber(4, 40), 10.02, drng:NextNumber(-4, 4))
				* CFrame.Angles(0, drng:NextNumber(-3.1, 3.1), 0),
			color = Color3.fromRGB(26, 23, 20), material = M.Slate, transparency = 0.25,
		})
	end
	for _ = 1, 7 do
		dress(meta, {
			name = "Straw", size = Vector3.new(1.6, 0.04, 1.0),
			cf = CFrame.new(x0 + drng:NextNumber(3, 41), 10.03, drng:NextNumber(-4.5, 4.5))
				* CFrame.Angles(0, drng:NextNumber(-3.1, 3.1), 0),
			color = Palette.Straw, material = M.Grass,
		})
	end
	-- stencils on the first few crates
	local stencils = { "N. 7 — SALT", "GLASS", "DO NOT OPEN" }
	for i, box in ipairs(stencilCrates) do
		local face = box.Position.Z > 0 and Enum.NormalId.Front or Enum.NormalId.Back
		Forge.surfaceText(box, face, stencils[i], {
			color = Color3.fromRGB(168, 158, 140), font = Palette.FontHeader, pps = 20, lightInfluence = 1,
		})
	end
	local placard = dress(meta, {
		name = "Manifest", size = Vector3.new(0.08, 1.4, 1.1),
		cf = CFrame.new(x0 + 0.68, 14.8, 3.0),
		color = Palette.UIPaperDim, material = M.Plaster,
	})
	Forge.surfaceText(placard, Enum.NormalId.Right, "MANIFEST\nshort by one crate", {
		color = Palette.UIInk, font = Palette.FontHeader, pps = 26, lightInfluence = 1,
	})
	-- barrels in the far corner (floor pair solid, topper loose)
	local barrelSpots = {
		{ x0 + 37.2, 11.1, -3.9, true },
		{ x0 + 38.6, 11.1, -2.6, true },
		{ x0 + 37.2, 13.3, -3.9, false },
	}
	for _, b in ipairs(barrelSpots) do
		dress(meta, {
			name = "Barrel", shape = "cyl", size = Vector3.new(2.2, 1.7, 1.7),
			cf = CFrame.new(b[1], b[2], b[3]) * CFrame.Angles(0, 0, math.rad(90)),
			color = Color3.fromRGB(74, 58, 40), material = M.Planks,
			cancollide = b[4], canquery = b[4],
		})
		dress(meta, {
			name = "BarrelBand", shape = "cyl", size = Vector3.new(0.1, 1.75, 1.75),
			cf = CFrame.new(b[1], b[2] + 0.6, b[3]) * CFrame.Angles(0, 0, math.rad(90)),
			color = Color3.fromRGB(50, 50, 54), material = M.Metal,
		})
	end
	dress(meta, {
		name = "RopeCoil", shape = "cyl", size = Vector3.new(0.25, 1.6, 1.6),
		cf = CFrame.new(x0 + 4, 10.15, 3.9) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(96, 84, 60), material = M.Fabric,
	})
	dress(meta, {
		name = "RopeCoil", shape = "cyl", size = Vector3.new(0.2, 1.2, 1.2),
		cf = CFrame.new(x0 + 4, 10.38, 3.9) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(96, 84, 60), material = M.Fabric,
	})
	-- dust motes drifting through the lamp pool
	Forge.particles(swingGlow, {
		color = ColorSequence.new(Color3.fromRGB(180, 170, 150)),
		size = NumberSequence.new(0.15, 0),
		transparency = NumberSequence.new(0.7, 1),
		lifetime = NumberRange.new(3, 5),
		rate = 3,
		speed = NumberRange.new(0.1, 0.3),
		lightEmission = 0.2,
	})
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

	-- dressing: the sort was abandoned mid-shift
	local drng = meta.drng
	kitRunner(meta)
	kitCeiling(meta, { coves = false, rails = false })
	-- guard bars over every window
	for _, win in ipairs(meta.windows) do
		for _, gy in ipairs({ 13.9, 14.9, 15.9 }) do
			dress(meta, {
				name = "GuardBar", shape = "cyl", size = Vector3.new(4.4, 0.08, 0.08),
				cf = CFrame.new(win.x, gy, win.side * 5.30),
				color = Color3.fromRGB(60, 60, 64), material = M.Metal,
			})
		end
	end
	-- scattered letters on the sort table
	for _ = 1, 7 do
		dress(meta, {
			name = "Letter", size = Vector3.new(0.55, 0.02, 0.4),
			cf = CFrame.new(x0 + drng:NextNumber(9.5, 14.5), 12.52, drng:NextNumber(-0.9, 0.9))
				* CFrame.Angles(0, drng:NextNumber(-3.1, 3.1), 0),
			color = drng:NextNumber() < 0.5 and Palette.UIPaper or Color3.fromRGB(210, 196, 168),
			material = M.Smooth,
		})
	end
	-- letter scale
	dress(meta, {
		name = "ScaleBase", shape = "cyl", size = Vector3.new(0.12, 0.5, 0.5),
		cf = CFrame.new(x0 + 14.2, 12.56, 0.7) * CFrame.Angles(0, 0, math.rad(90)),
		color = Palette.BrassDark, material = M.Metal,
	})
	dress(meta, {
		name = "ScaleColumn", shape = "cyl", size = Vector3.new(0.7, 0.08, 0.08),
		cf = CFrame.new(x0 + 14.2, 12.95, 0.7) * CFrame.Angles(0, 0, math.rad(90)),
		color = Palette.BrassDark, material = M.Metal,
	})
	dress(meta, {
		name = "ScalePan", shape = "cyl", size = Vector3.new(0.06, 0.4, 0.4),
		cf = CFrame.new(x0 + 14.2, 13.25, 0.7) * CFrame.Angles(0, 0, math.rad(90)),
		color = Palette.BrassDark, material = M.Metal,
	})
	-- low desk lamp over the table (dies with lamp-outs like the rest)
	addLamp(meta, CFrame.new(x0 + 13.5, 14.4, 0), {
		stem = 4.4, scale = 0.6, range = 9, brightness = 0.7, shadows = false,
	})
	dress(meta, {
		name = "DeskShade", shape = "cyl", size = Vector3.new(0.2, 1.1, 1.1),
		cf = CFrame.new(x0 + 13.5, 14.85, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(30, 58, 40), material = M.Metal,
	})
	-- stuffed cubby slots
	local slots = {}
	for col = 1, 6 do
		for row = 1, 3 do
			table.insert(slots, { col, row, -1 })
			table.insert(slots, { col, row, 1 })
		end
	end
	local stuffHues = {
		Color3.fromRGB(206, 192, 164), Color3.fromRGB(164, 148, 120), Color3.fromRGB(120, 104, 76),
	}
	for k = 1, 10 do
		local pick = table.remove(slots, drng:NextInteger(1, #slots))
		dress(meta, {
			name = "CubbyMail", size = Vector3.new(1.5, 0.9, 0.35),
			cf = CFrame.new(x0 + 20.5 + pick[1] * 2.05, 10.9 + pick[2] * 1.5, pick[3] * 3.62),
			color = stuffHues[k % 3 + 1], material = M.Plaster,
		})
	end
	-- twine-bound bundles
	for i, by in ipairs({ 10.25, 10.75, 11.25 }) do
		dress(meta, {
			name = "Bundle", size = Vector3.new(1.2, 0.5, 0.9),
			cf = CFrame.new(x0 + 5, by, -3.4) * CFrame.Angles(0, drng:NextNumber(-0.2, 0.2), 0),
			color = stuffHues[i], material = M.Plaster,
		})
	end
	for _, sx in ipairs({ x0 + 4.7, x0 + 5.3 }) do
		dress(meta, {
			name = "BundleStrap", size = Vector3.new(0.1, 1.6, 0.95),
			cf = CFrame.new(sx, 10.75, -3.4),
			color = Color3.fromRGB(70, 58, 40), material = M.Fabric,
		})
	end
	-- route board
	local board = dress(meta, {
		name = "RouteBoard", size = Vector3.new(3.2, 1.8, 0.1),
		cf = CFrame.new(x0 + 34.5, 15.0, 5.34),
		color = Color3.fromRGB(24, 26, 24), material = M.Wood,
	})
	Forge.surfaceText(board, Enum.NormalId.Front, "WESTBOUND — SORT BY LINE\nNO NAMES. NO RETURN ADDRESSES.", {
		color = Palette.UIPaper, font = Palette.FontHeader, pps = 30, lightInfluence = 1,
	})
	-- registered-cage sign
	dress(meta, {
		name = "SignHanger", shape = "cyl", size = Vector3.new(0.5, 0.06, 0.06),
		cf = CFrame.new(x0 + 38, 16.9, -0.78) * CFrame.Angles(0, math.rad(90), 0),
		color = Color3.fromRGB(60, 60, 64), material = M.Metal,
	})
	local cageSign = dress(meta, {
		name = "CageSign", size = Vector3.new(1.6, 0.6, 0.06),
		cf = CFrame.new(x0 + 38, 16.5, -0.78),
		color = Color3.fromRGB(140, 30, 26), material = M.Metal,
	})
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		Forge.surfaceText(cageSign, face, "REGISTERED", {
			color = Color3.fromRGB(222, 214, 196), font = Palette.FontHeader, pps = 40, lightInfluence = 1,
		})
	end
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
		Forge.light(marker, { color = Color3.fromRGB(255, 44, 28), range = 6, brightness = 0.8, shadows = false })
	end
	-- rope coils lashed to the deck
	for _, spot in ipairs({ { x0 + 14, -3.5 }, { x0 + 30, 3.6 } }) do
		Forge.cyl({
			parent = meta.model, name = "RopeCoil",
			size = Vector3.new(0.25, 1.6, 1.6),
			cf = CFrame.new(spot[1], 10.15, spot[2]) * CFrame.Angles(0, 0, math.rad(90)),
			color = Color3.fromRGB(96, 84, 60), material = M.Fabric,
			cancollide = false, canquery = false, castshadow = false,
		})
		Forge.cyl({
			parent = meta.model, name = "RopeCoil",
			size = Vector3.new(0.2, 1.2, 1.2),
			cf = CFrame.new(spot[1], 10.38, spot[2]) * CFrame.Angles(0, 0, math.rad(90)),
			color = Color3.fromRGB(96, 84, 60), material = M.Fabric,
			cancollide = false, canquery = false, castshadow = false,
		})
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
			color = Palette.CandleFlame, material = M.Neon, cancollide = false,
		})
		Forge.light(flame, { color = Color3.fromRGB(255, 96, 44), range = 8, brightness = 1.2, flicker = true, shadows = true })
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

	-- dressing: opulence gone quiet
	local cx = x0 + L / 2
	kitWainscot(meta, nil, Palette.RedCarGold)
	for _, side in ipairs({ -1, 1 }) do
		dress(meta, {
			name = "CarpetBorder", size = Vector3.new(38, 0.06, 0.4),
			cf = CFrame.new(cx, 10.13, side * 3.1),
			color = Palette.RedCarGold, material = M.Fabric,
		})
	end
	-- velvet ceiling inlay, gilt-edged
	dress(meta, {
		name = "CeilVelvet", size = Vector3.new(41, 0.12, 8.5),
		cf = CFrame.new(cx, 18.92, 0),
		color = Palette.RedCarVelvet, material = M.Fabric,
	})
	for _, side in ipairs({ -1, 1 }) do
		dress(meta, {
			name = "CeilGilt", size = Vector3.new(41, 0.15, 0.1),
			cf = CFrame.new(cx, 18.8, side * 4.3),
			color = Palette.RedCarGold, material = M.Metal, reflectance = 0.35,
		})
	end
	for _, gx in ipairs({ x0 + 11, x0 + 22, x0 + 33 }) do
		dress(meta, {
			name = "CeilGiltRib", size = Vector3.new(0.15, 0.12, 8.4),
			cf = CFrame.new(gx, 18.82, 0),
			color = Palette.RedCarGold, material = M.Metal, reflectance = 0.35,
		})
	end
	-- heavy drapes between windows (skipping the portrait walls)
	local drapeX = {
		[-1] = { 7, 12, 17, 22, 27, 32, 37 },
		[1] = { 7, 12, 22, 27, 37 },
	}
	for side, list in pairs(drapeX) do
		for _, dx in ipairs(list) do
			dress(meta, {
				name = "Drape", size = Vector3.new(1.0, 5.2, 0.22),
				cf = CFrame.new(x0 + dx, 14.6, side * 5.16),
				color = Color3.fromRGB(46, 12, 14), material = M.Fabric,
			})
			dress(meta, {
				name = "DrapeTie", size = Vector3.new(0.3, 0.5, 0.26),
				cf = CFrame.new(x0 + dx, 13.4, side * 5.16),
				color = Palette.RedCarGold, material = M.Fabric,
			})
		end
	end
	-- chandelier over the center of the room
	dress(meta, {
		name = "ChandelierStem", shape = "cyl", size = Vector3.new(1.6, 0.12, 0.12),
		cf = CFrame.new(cx, 18.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color = Palette.BrassDark, material = M.Metal,
	})
	local hub = dress(meta, {
		name = "ChandelierHub", shape = "ball", size = Vector3.new(0.5, 0.5, 0.5),
		cf = CFrame.new(cx, 17.0, 0),
		color = Palette.Brass, material = M.Metal, reflectance = 0.3,
	})
	for k = 0, 3 do
		local yaw = math.rad(45 + k * 90)
		local dir = CFrame.Angles(0, yaw, 0)
		local armCf = CFrame.new(cx, 17.0, 0) * dir * CFrame.new(0.7, 0, 0)
		dress(meta, {
			name = "ChandelierArm", shape = "cyl", size = Vector3.new(1.4, 0.1, 0.1),
			cf = armCf, color = Palette.BrassDark, material = M.Metal,
		})
		local tipCf = CFrame.new(cx, 0, 0) * dir * CFrame.new(1.4, 0, 0)
		dress(meta, {
			name = "ChandelierCup", size = Vector3.new(0.2, 0.3, 0.2),
			cf = CFrame.new(tipCf.X, 17.15, tipCf.Z),
			color = Palette.Brass, material = M.Metal,
		})
		dress(meta, {
			name = "ChandelierFlame", size = Vector3.new(0.16, 0.3, 0.16),
			cf = CFrame.new(tipCf.X, 17.45, tipCf.Z),
			color = Palette.CandleFlame, material = M.Neon,
		})
	end
	Forge.light(hub, { color = Color3.fromRGB(255, 140, 70), range = 13, brightness = 0.8, shadows = false, flicker = true })
	-- gilt fringe on the chairs
	for k = 1, 4 do
		local chairX = x0 + 6 + k * 6.5
		local zc = (k % 2 == 0) and 3.2 or -3.2
		for _, fz in ipairs({ zc - 0.9, zc + 0.9 }) do
			dress(meta, {
				name = "ChairFringe", size = Vector3.new(1.8, 0.3, 0.1),
				cf = CFrame.new(chairX, 10.55, fz),
				color = Palette.RedCarGold, material = M.Fabric,
			})
		end
	end
	-- side tables with a last glass of something dark
	for _, spot in ipairs({ { x0 + 15, -3.6 }, { x0 + 28.5, 3.6 } }) do
		dress(meta, {
			name = "TableTop", shape = "cyl", size = Vector3.new(0.1, 1.3, 1.3),
			cf = CFrame.new(spot[1], 12.1, spot[2]) * CFrame.Angles(0, 0, math.rad(90)),
			color = Color3.fromRGB(24, 18, 16), material = M.Wood,
		})
		dress(meta, {
			name = "TableStem", shape = "cyl", size = Vector3.new(1.5, 0.18, 0.18),
			cf = CFrame.new(spot[1], 11.3, spot[2]) * CFrame.Angles(0, 0, math.rad(90)),
			color = Color3.fromRGB(24, 18, 16), material = M.Wood,
		})
		dress(meta, {
			name = "TableBase", shape = "cyl", size = Vector3.new(0.06, 0.8, 0.8),
			cf = CFrame.new(spot[1], 10.58, spot[2]) * CFrame.Angles(0, 0, math.rad(90)),
			color = Color3.fromRGB(24, 18, 16), material = M.Wood,
		})
		dress(meta, {
			name = "WineGlass", shape = "cyl", size = Vector3.new(0.35, 0.22, 0.22),
			cf = CFrame.new(spot[1] + 0.3, 12.33, spot[2] - 0.2) * CFrame.Angles(0, 0, math.rad(90)),
			color = Color3.fromRGB(60, 16, 18), material = M.Glass, transparency = 0.3,
		})
	end
	-- dark mats behind the faceless portraits, picture lights above
	for k = 1, 3 do
		local px = x0 + 8 + k * 8
		dress(meta, {
			name = "PortraitMat", size = Vector3.new(2.6, 3.4, 0.05),
			cf = CFrame.new(px, 15.2, 5.315),
			color = Color3.fromRGB(24, 20, 18), material = M.Fabric,
		})
		dress(meta, {
			name = "PictureLight", shape = "cyl", size = Vector3.new(0.5, 0.12, 0.12),
			cf = CFrame.new(px, 16.9, 5.2),
			color = Palette.BrassDark, material = M.Metal,
		})
	end
	-- end-wall mirror
	dress(meta, {
		name = "MirrorFrame", size = Vector3.new(0.12, 3.8, 3.0),
		cf = CFrame.new(x0 + 43.35, 15.0, 3.9),
		color = Palette.RedCarGold, material = M.Metal, reflectance = 0.25,
	})
	dress(meta, {
		name = "MirrorGlass", size = Vector3.new(0.1, 3.4, 2.6),
		cf = CFrame.new(x0 + 43.24, 15.0, 3.9),
		color = Color3.fromRGB(16, 18, 22), material = M.Glass, reflectance = 0.6,
	})
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
	local moteBall
	for k = 1, 7 do
		local ball = Forge.ball({
			parent = nest,
			size = Vector3.new(rng:NextNumber(2.5, 4.5), rng:NextNumber(1.6, 2.6), rng:NextNumber(2.5, 4.5)),
			cf = CFrame.new(nx + rng:NextNumber(-4, 4), FLOOR + rng:NextNumber(0.5, 1.4), rng:NextNumber(-2.5, 2.5)),
			color = Palette.SleeperHide, material = M.Fabric,
		})
		if k == 4 then
			moteBall = ball
		end
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
	-- two guttering lamps only; the nest stays in true dark between them
	addLamp(meta, CFrame.new(x0 + 8, 17.5, 0), { swing = true, brightness = 0.9, range = 9, shadows = false, color = Palette.LampGlowDeep })
	addLamp(meta, CFrame.new(x0 + 38, 17.5, 0), { swing = true, brightness = 0.9, range = 9, shadows = false, color = Palette.LampGlowDeep })
	addHide(meta, CFrame.new(x0 + 6, FLOOR + 0.8, 4.4), Vector3.new(3.4, 1.5, 1.6), "Crouch behind")

	-- restraint is the look here: torn cloth, claw marks, a broken ceiling
	local drng = meta.drng
	kitCurtains(meta, "torn")
	local clawClusters = {
		{ x0 + 20, 13.5, 5.24 },
		{ x0 + 31, 12.8, -5.24 },
	}
	for _, cl in ipairs(clawClusters) do
		for k = 0, 2 do
			dress(meta, {
				name = "ClawMark", size = Vector3.new(1.8, 0.15, 0.05),
				cf = CFrame.new(cl[1], cl[2] + k * 0.35, cl[3]) * CFrame.Angles(0, 0, math.rad(18)),
				color = Color3.fromRGB(28, 20, 18), material = M.Wood,
			})
		end
	end
	for _, bx in ipairs({ x0 + 12, x0 + 22, x0 + 32 }) do
		dress(meta, {
			name = "BrokenRib", size = Vector3.new(0.35, 0.18, drng:NextNumber(3, 5)),
			cf = CFrame.new(bx, 18.91, drng:NextNumber(-2, 2)),
			color = Color3.fromRGB(120, 110, 96), material = M.Wood,
		})
	end
	dress(meta, {
		name = "DanglingPlank", shape = "wedge", size = Vector3.new(2.2, 0.3, 0.6),
		cf = CFrame.new(x0 + 22, 17.8, 1.0) * CFrame.Angles(math.rad(35), 0.4, 0),
		color = Palette.SleeperWood, material = M.Wood,
	})
	-- an overturned chair, kicked aside
	local chairCf = CFrame.new(x0 + 14, 10.5, 3.0) * CFrame.Angles(0, 0.7, math.rad(90))
	dress(meta, {
		name = "FallenChairSeat", size = Vector3.new(1.5, 0.25, 1.5),
		cf = chairCf, color = Palette.SleeperWood, material = M.Wood,
	})
	dress(meta, {
		name = "FallenChairBack", size = Vector3.new(0.25, 1.6, 1.5),
		cf = chairCf * CFrame.new(0.75, 0.9, 0), color = Palette.SleeperWood, material = M.Wood,
	})
	dress(meta, {
		name = "FallenChairLeg", size = Vector3.new(0.2, 1.2, 0.2),
		cf = chairCf * CFrame.new(-0.65, -0.7, 0.65), color = Palette.SleeperWood, material = M.Wood,
	})
	if moteBall then
		Forge.particles(moteBall, {
			color = ColorSequence.new(Color3.fromRGB(60, 56, 66)),
			size = NumberSequence.new(0.2),
			transparency = NumberSequence.new(0.6, 1),
			lifetime = NumberRange.new(4, 6),
			rate = 2,
			speed = NumberRange.new(0.1, 0.4),
		})
	end
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
	-- the climax light of the train
	Forge.light(fireDoor, { color = Color3.fromRGB(255, 92, 24), range = 24, brightness = 2.6, flicker = true, shadows = true })
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
	-- fireman's kit left where it was dropped
	Forge.cyl({
		parent = meta.model, name = "ShovelHandle",
		size = Vector3.new(2.6, 0.12, 0.12),
		cf = CFrame.new(x0 + 30, 11.2, 3.9) * CFrame.Angles(0, 0, math.rad(70)),
		color = Color3.fromRGB(78, 58, 38), material = M.Wood,
		cancollide = false, canquery = false, castshadow = false,
	})
	Forge.part({
		parent = meta.model, name = "ShovelBlade",
		size = Vector3.new(0.05, 0.8, 0.6),
		cf = CFrame.new(x0 + 30.45, 10.15, 3.9) * CFrame.Angles(0, 0, math.rad(-20)),
		color = Color3.fromRGB(60, 60, 64), material = M.Metal,
		cancollide = false, canquery = false, castshadow = false,
	})
	Forge.cyl({
		parent = meta.model, name = "OilCan",
		size = Vector3.new(0.7, 0.4, 0.4),
		cf = CFrame.new(x0 + 41, 10.55, 4.2) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(40, 40, 44), material = M.Metal,
		cancollide = false, canquery = false, castshadow = false,
	})
	Forge.cyl({
		parent = meta.model, name = "OilSpout",
		size = Vector3.new(0.5, 0.08, 0.08),
		cf = CFrame.new(x0 + 41.2, 11.0, 4.2) * CFrame.Angles(0, 0, math.rad(55)),
		color = Color3.fromRGB(40, 40, 44), material = M.Metal,
		cancollide = false, canquery = false, castshadow = false,
	})
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
	-- dressing stream: decorative extras draw from here so the original rng
	-- stream (hide rows, crates, bags) stays byte-identical across versions
	meta.drng = Random.new(entry.variant * 7919 + entry.index)
	local builder = Builders[entry.archetype] or Builders.coach
	builder(meta, rng)

	-- lashed roof cargo on some enclosed cars: the roof route pays rent
	if meta.enclosed and entry.archetype ~= "caboose" and rng:NextNumber() < 0.35 then
		local rx = meta.x0 + rng:NextNumber(9, L - 9)
		-- clamped to the monitor walk so lashed cargo sits on the new arched roof
		local rz = rng:NextNumber(-0.9, 0.9)
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

	-- rear porch on the tail car: the last thing the night sees of the train
	if entry.index == 1 and entry.archetype == "caboose" then
		local px = meta.x0
		Forge.part({
			parent = model, name = "PorchDeck",
			size = Vector3.new(2.6, 0.4, 8.5),
			cf = CFrame.new(px - 1.3, 9.8, 0),
			color = Palette.FloorWood, material = M.Planks,
		})
		for _, pz in ipairs({ -4.0, -1.5, 1.5, 4.0 }) do
			Forge.cyl({
				parent = model, name = "PorchPost",
				size = Vector3.new(3.2, 0.2, 0.2),
				cf = CFrame.new(px - 2.45, 11.6, pz) * CFrame.Angles(0, 0, math.rad(90)),
				color = Color3.fromRGB(40, 36, 32), material = M.Metal, cancollide = false, canquery = false,
			})
		end
		for _, side in ipairs({ -1, 1 }) do
			for _, ry in ipairs({ 11.9, 13.1 }) do
				Forge.cyl({
					parent = model, name = "PorchRail",
					size = Vector3.new(2.5, 0.18, 0.18),
					cf = CFrame.new(px - 2.45, ry, side * 2.75) * CFrame.Angles(0, math.rad(90), 0),
					color = Color3.fromRGB(40, 36, 32), material = M.Metal, cancollide = false, canquery = false,
				})
			end
		end
		local tail = Forge.part({
			parent = model, name = "TailBoard",
			size = Vector3.new(0.12, 0.9, 2.6),
			cf = CFrame.new(px - 2.56, 17.6, 0),
			color = Palette.CarLetterboard, material = M.Wood,
			cancollide = false, canquery = false, castshadow = false,
		})
		-- rear of the train faces -X; the outward face there is Left
		Forge.surfaceText(tail, Enum.NormalId.Left, "THE 11:59", {
			color = Palette.CarLetters, font = Palette.FontHeader, pps = 44,
			lightInfluence = 0.55, brightness = 1.1,
		})
	end

	model:SetAttribute("Enclosed", meta.enclosed)
	return meta
end

return CarPlans
