--[[
	Palette.luau
	The film look of THE 11:59 in one file: colors, materials, fonts.
	Cold moonlit indigo exteriors against warm gaslit interiors — values
	pushed apart so pools of lamplight read against true darkness, tuned
	for Future lighting with environment specular enabled.
]]

local Palette = {}

-- Night world
Palette.NightSky = Color3.fromRGB(10, 14, 28)
Palette.NightFog = Color3.fromRGB(16, 21, 40)
Palette.Moonlight = Color3.fromRGB(176, 198, 238)
Palette.Moon = Color3.fromRGB(228, 236, 255)
Palette.MoonHaloInner = Color3.fromRGB(110, 124, 168)
Palette.MoonHaloOuter = Color3.fromRGB(58, 68, 102)
Palette.GroundNight = Color3.fromRGB(17, 21, 26)
Palette.PineDark = Color3.fromRGB(23, 36, 34)
Palette.PineMid = Color3.fromRGB(36, 52, 40)
Palette.PineTrunk = Color3.fromRGB(38, 31, 28)
Palette.TreelineDark = Color3.fromRGB(13, 20, 17)
Palette.MountainFar = Color3.fromRGB(11, 14, 28)
Palette.RidgeNear = Color3.fromRGB(21, 27, 46)
Palette.RidgeFar = Color3.fromRGB(14, 18, 33)
Palette.HorizonApron = Color3.fromRGB(12, 16, 26)
Palette.MistBlue = Color3.fromRGB(56, 68, 94)
Palette.RockGray = Color3.fromRGB(47, 49, 54)
Palette.DitchDark = Color3.fromRGB(14, 17, 19)
Palette.MarshWater = Color3.fromRGB(14, 22, 30)
Palette.MarshReed = Color3.fromRGB(44, 48, 32)
Palette.SnagWood = Color3.fromRGB(44, 40, 38)
Palette.RailSteel = Color3.fromRGB(108, 112, 122)
Palette.SleeperWood = Color3.fromRGB(58, 48, 40)
Palette.Gravel = Color3.fromRGB(48, 50, 54)
Palette.TunnelRock = Color3.fromRGB(26, 25, 28)
Palette.HayStraw = Color3.fromRGB(74, 66, 40)
Palette.CropRow = Color3.fromRGB(40, 40, 28)
Palette.CropRowAlt = Color3.fromRGB(33, 34, 24)
Palette.ContainerRust = Color3.fromRGB(74, 34, 28)
Palette.ContainerBlue = Color3.fromRGB(28, 40, 56)
Palette.ContainerOlive = Color3.fromRGB(42, 46, 34)
Palette.YardSteel = Color3.fromRGB(16, 17, 20)
Palette.SignalAmber = Color3.fromRGB(255, 170, 60)
Palette.WarmWindow = Color3.fromRGB(255, 190, 110)

-- Per-biome atmosphere targets (client LightingDirector)
Palette.BiomeFog = {
	pine = Color3.fromRGB(22, 29, 50),
	marsh = Color3.fromRGB(23, 34, 44),
	fields = Color3.fromRGB(28, 30, 50),
	yard = Color3.fromRGB(32, 30, 44),
	gorge = Color3.fromRGB(18, 26, 48),
}

-- The train herself
Palette.CarBody = Color3.fromRGB(24, 50, 38)       -- deep viridian Pullman
Palette.CarBodyAlt = Color3.fromRGB(58, 28, 30)    -- oxblood variant
Palette.CarBodyShadow = Color3.fromRGB(23, 40, 31) -- lower-body battens (green cars)
Palette.CarLetterboard = Color3.fromRGB(19, 29, 23)     -- upper band, green cars
Palette.CarLetterboardAlt = Color3.fromRGB(34, 19, 19)  -- upper band, oxblood cars
Palette.CarTrim = Color3.fromRGB(15, 24, 19)       -- trim/mullions/posts, green cars
Palette.CarTrimAlt = Color3.fromRGB(26, 14, 14)    -- same for oxblood cars
Palette.CarRoof = Color3.fromRGB(33, 34, 38)
Palette.CarRoofCanvas = Color3.fromRGB(56, 54, 49) -- roof slopes catch the moon
Palette.CarWalkboard = Color3.fromRGB(74, 64, 52)  -- monitor walk planks
Palette.CarUnderframe = Color3.fromRGB(28, 28, 30)
Palette.BogieIron = Color3.fromRGB(24, 24, 27)
Palette.CouplerIron = Color3.fromRGB(30, 29, 31)
Palette.MarkerLensDead = Color3.fromRGB(120, 26, 22)
Palette.CarLetters = Color3.fromRGB(226, 192, 112) -- gilt lettering
Palette.RedCarBody = Color3.fromRGB(70, 14, 18)

-- Interiors
Palette.FloorWood = Color3.fromRGB(70, 48, 34)
Palette.WallWood = Color3.fromRGB(99, 64, 42)
Palette.WallPanel = Color3.fromRGB(52, 38, 30)
Palette.Ceiling = Color3.fromRGB(214, 200, 176)
Palette.CeilingRib = Color3.fromRGB(170, 158, 138)
Palette.WoodTrim = Color3.fromRGB(44, 32, 26)
Palette.SeatLeather = Color3.fromRGB(102, 36, 32)
Palette.SeatLeatherAlt = Color3.fromRGB(38, 60, 46)
Palette.Brass = Color3.fromRGB(208, 164, 64)
Palette.BrassDark = Color3.fromRGB(140, 110, 40)
Palette.Curtain = Color3.fromRGB(80, 28, 32)
Palette.CurtainCream = Color3.fromRGB(188, 158, 120)
Palette.CarpetRunner = Color3.fromRGB(86, 26, 26)
Palette.CarpetTrim = Color3.fromRGB(46, 16, 14)
Palette.RugWarm = Color3.fromRGB(128, 74, 44)
Palette.TableLinen = Color3.fromRGB(222, 212, 192)
Palette.Bone = Color3.fromRGB(224, 214, 194)
Palette.BottleGreen = Color3.fromRGB(26, 46, 32)
Palette.BottleAmber = Color3.fromRGB(104, 62, 22)
Palette.Straw = Color3.fromRGB(118, 100, 58)
Palette.GrimeDark = Color3.fromRGB(30, 26, 22)
Palette.RedCarVelvet = Color3.fromRGB(40, 10, 12)
Palette.RedCarGold = Color3.fromRGB(214, 172, 84)
Palette.LampGlow = Color3.fromRGB(255, 167, 74)    -- ~2100K gaslight
Palette.LampGlowDeep = Color3.fromRGB(255, 148, 64)
Palette.LampGlass = Color3.fromRGB(255, 200, 126)
Palette.CandleFlame = Color3.fromRGB(255, 118, 48)
Palette.EmergencyRed = Color3.fromRGB(255, 52, 38)
Palette.Crate = Color3.fromRGB(96, 78, 54)
Palette.Tarp = Color3.fromRGB(46, 52, 50)
Palette.MailSack = Color3.fromRGB(120, 104, 76)
Palette.GlassNight = Color3.fromRGB(16, 24, 44)

-- Entities
Palette.FurnaceCore = Color3.fromRGB(255, 106, 26)
Palette.FurnaceEmber = Color3.fromRGB(255, 160, 60)
Palette.InspectorCoat = Color3.fromRGB(24, 22, 26)
Palette.InspectorSkin = Color3.fromRGB(214, 200, 186)
Palette.InspectorLantern = Color3.fromRGB(255, 196, 124)
Palette.GloomBody = Color3.fromRGB(8, 8, 12)
Palette.ParallelSkin = Color3.fromRGB(226, 228, 236)
Palette.SleeperHide = Color3.fromRGB(36, 30, 40)
Palette.EyeShine = Color3.fromRGB(255, 244, 180)
Palette.GhostBlue = Color3.fromRGB(120, 190, 255)

-- UI
Palette.UIPaper = Color3.fromRGB(232, 220, 196)
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
	Brick = Enum.Material.Brick,
	Ice = Enum.Material.Ice,
	Sand = Enum.Material.Sand,
	Smooth = Enum.Material.SmoothPlastic,
	Plastic = Enum.Material.Plastic,
	Cobble = Enum.Material.Cobblestone,
	Pebble = Enum.Material.Pebble,
	Asphalt = Enum.Material.Asphalt,
	Mud = Enum.Material.Mud,
	Snow = Enum.Material.Snow,
	Foil = Enum.Material.Foil,
}

return Palette
