--[[
	Palette.luau
	The film look of THE 11:59 in one file: colors, materials, fonts.
	Warm gaslight interiors against a cold indigo night.
]]

local Palette = {}

-- Night world
Palette.NightSky = Color3.fromRGB(10, 14, 28)
Palette.NightFog = Color3.fromRGB(13, 18, 34)
Palette.Moonlight = Color3.fromRGB(168, 186, 224)
Palette.Moon = Color3.fromRGB(235, 240, 255)
Palette.GroundNight = Color3.fromRGB(24, 30, 34)
Palette.PineDark = Color3.fromRGB(26, 38, 32)
Palette.PineTrunk = Color3.fromRGB(46, 36, 30)
Palette.MountainFar = Color3.fromRGB(16, 20, 36)
Palette.MarshWater = Color3.fromRGB(18, 26, 32)
Palette.SnagWood = Color3.fromRGB(52, 46, 42)
Palette.RailSteel = Color3.fromRGB(96, 100, 108)
Palette.SleeperWood = Color3.fromRGB(58, 48, 40)
Palette.Gravel = Color3.fromRGB(56, 58, 60)
Palette.TunnelRock = Color3.fromRGB(30, 30, 34)

-- The train herself
Palette.CarBody = Color3.fromRGB(31, 59, 44)       -- Pullman green
Palette.CarBodyAlt = Color3.fromRGB(56, 32, 34)    -- oxblood variant
Palette.CarRoof = Color3.fromRGB(38, 38, 40)
Palette.CarUnderframe = Color3.fromRGB(28, 28, 30)
Palette.CarLetters = Color3.fromRGB(214, 186, 110) -- gilt lettering
Palette.RedCarBody = Color3.fromRGB(64, 16, 18)

-- Interiors
Palette.FloorWood = Color3.fromRGB(78, 56, 40)
Palette.WallWood = Color3.fromRGB(94, 68, 48)
Palette.WallPanel = Color3.fromRGB(58, 44, 36)
Palette.Ceiling = Color3.fromRGB(206, 196, 178)
Palette.SeatLeather = Color3.fromRGB(94, 38, 34)
Palette.SeatLeatherAlt = Color3.fromRGB(44, 58, 48)
Palette.Brass = Color3.fromRGB(201, 162, 39)
Palette.Curtain = Color3.fromRGB(74, 30, 32)
Palette.TableLinen = Color3.fromRGB(216, 206, 188)
Palette.LampGlow = Color3.fromRGB(255, 178, 90)    -- gaslight
Palette.LampGlass = Color3.fromRGB(255, 214, 150)
Palette.EmergencyRed = Color3.fromRGB(255, 64, 48)
Palette.Crate = Color3.fromRGB(96, 78, 54)
Palette.Tarp = Color3.fromRGB(52, 58, 52)
Palette.MailSack = Color3.fromRGB(120, 104, 76)
Palette.GlassNight = Color3.fromRGB(24, 34, 52)

-- Entities
Palette.FurnaceCore = Color3.fromRGB(255, 106, 26)
Palette.FurnaceEmber = Color3.fromRGB(255, 160, 60)
Palette.InspectorCoat = Color3.fromRGB(24, 22, 26)
Palette.InspectorSkin = Color3.fromRGB(214, 200, 186)
Palette.InspectorLantern = Color3.fromRGB(255, 190, 120)
Palette.GloomBody = Color3.fromRGB(8, 8, 12)
Palette.ParallelSkin = Color3.fromRGB(226, 228, 236)
Palette.SleeperHide = Color3.fromRGB(36, 30, 40)
Palette.EyeShine = Color3.fromRGB(255, 244, 180)
Palette.GhostBlue = Color3.fromRGB(120, 190, 255)

-- UI
Palette.UIPaper = Color3.fromRGB(232, 220, 196)    -- old ticket stock
Palette.UIPaperDim = Color3.fromRGB(196, 182, 158)
Palette.UIInk = Color3.fromRGB(34, 28, 24)
Palette.UIPanel = Color3.fromRGB(16, 14, 16)
Palette.UIPanelEdge = Color3.fromRGB(201, 162, 39)
Palette.UIBlood = Color3.fromRGB(150, 30, 26)
Palette.UIWarn = Color3.fromRGB(255, 178, 90)
Palette.UIGood = Color3.fromRGB(120, 200, 140)
Palette.UIGhost = Color3.fromRGB(120, 190, 255)

-- Fonts (built-in Roblox faces; SpecialElite = typewriter, fits the era)
Palette.FontTitle = Enum.Font.Fondamento
Palette.FontHeader = Enum.Font.SpecialElite
Palette.FontBody = Enum.Font.Gotham
Palette.FontBodyBold = Enum.Font.GothamBold
Palette.FontMono = Enum.Font.RobotoMono

-- Handy material shorthands (new 2023 base materials included)
Palette.M = {
	Wood = Enum.Material.Wood,
	Planks = Enum.Material.WoodPlanks,
	Metal = Enum.Material.Metal,
	CorrodedMetal = Enum.Material.CorrodedMetal,
	DiamondPlate = Enum.Material.DiamondPlate,
	Fabric = Enum.Material.Fabric,
	Leather = Enum.Material.Leather,
	Carpet = Enum.Material.Carpet,
	Plaster = Enum.Material.Plaster,
	Cardboard = Enum.Material.Cardboard,
	Glass = Enum.Material.Glass,
	Neon = Enum.Material.Neon,
	Slate = Enum.Material.Slate,
	Grass = Enum.Material.Grass,
	Ground = Enum.Material.Ground,
	Rock = Enum.Material.Rock,
	Basalt = Enum.Material.Basalt,
	Concrete = Enum.Material.Concrete,
	Granite = Enum.Material.Granite,
	Ice = Enum.Material.Ice,
	Sand = Enum.Material.Sand,
	Smooth = Enum.Material.SmoothPlastic,
	Plastic = Enum.Material.Plastic,
	Brick = Enum.Material.Brick,
	Cobble = Enum.Material.Cobblestone,
	Pebble = Enum.Material.Pebble,
	Asphalt = Enum.Material.Asphalt,
	Mud = Enum.Material.Mud,
	Snow = Enum.Material.Snow,
	Foil = Enum.Material.Foil,
}

return Palette
