--[[
	Config.luau
	Single source of truth for every tuning number in THE 11:59.
	Server and client both read this; nothing gameplay-critical is trusted
	from the client regardless of what's in here.
]]

local Config = {}

Config.GameName = "THE 11:59"
Config.Tagline = "The last train out of the valley."
Config.Version = "0.9.5"

----------------------------------------------------------------
-- Train geometry. The train is static in the world; the night
-- outside scrolls past it. Forward (toward the engine) is +X.
----------------------------------------------------------------
Config.Train = {
	Cars = 28,             -- car 1 = caboose (boarding), car 28 = tender + engine cab
	CarPitch = 48,         -- X distance between car origins
	CarLength = 44,
	CarWidth = 12,         -- outer shell width
	CarHeight = 9,         -- interior ceiling height above floor
	FloorY = 10,           -- world Y of the interior floor's top surface
	WallThick = 0.6,
	RoofThick = 0.5,

	CruiseSpeed = 38,      -- studs/sec of the *illusion* of motion
	AccelSeconds = 9,      -- ramp time between stopped and cruise

	BuildAhead = 2,        -- cars kept built ahead of the front-most player
	KeepBehind = 1,        -- cars kept built behind the rear-most (non-ghost) player
}

----------------------------------------------------------------
-- Run structure
----------------------------------------------------------------
Config.Run = {
	LobbyCountdown = 30,        -- seconds after first boarder before departure
	StationCars = { 10, 19 },   -- arriving at these cars triggers a station stop
	StationStopSeconds = 80,
	StationWarnSeconds = 15,    -- final whistle warning before departure
	SleeperCarRange = { 14, 16 },
	RedCarRange = { 21, 24 },
	FlatcarCars = { 7, 17 },
	InspectorCars = { 6, 13, 22 },
	DefeatResetSeconds = 14,
	VictoryResetSeconds = 45,
	StartFare = 15,             -- pocket money each rider starts with
}

----------------------------------------------------------------
-- Players
----------------------------------------------------------------
Config.Player = {
	MaxHealth = 100,
	WalkSpeed = 16,
	SprintSpeed = 23,
	CrouchSpeed = 8,
	GhostSpeed = 22,
	RoofSpeedCap = 13,
	JumpHeight = 5,

	SprintSeconds = 7.5,      -- full-tank sprint duration
	StaminaRegenPerSecond = 0.22,

	SoloSecondChance = true,  -- a lone rider's first death is a warning, not the end

	BleedOutSeconds = 40,
	ReviveHoldSeconds = 5,
	ReviveHealth = 35,
	StationReviveHealth = 60,
	GhostRevivalFarePenalty = 0.25,
}

----------------------------------------------------------------
-- Noise. Server-computed 0..1 meter per player; several entities
-- listen to it. Values are added per event / per second then decay.
----------------------------------------------------------------
Config.Noise = {
	DecayPerSecond = 0.35,
	SprintPerSecond = 0.30,
	WalkPerSecond = 0.08,
	CrouchPerSecond = 0.02,
	Jump = 0.15,
	Land = 0.18,
	DoorSlam = 0.22,
	Bash = 0.55,
	Pry = 0.3,
	Flare = 0.5,
	Piano = 0.7,
	WatchTickPerSecond = 0.02,
}

----------------------------------------------------------------
-- Entities
----------------------------------------------------------------
Config.Entities = {
	Furnace = {
		WarnSeconds = 6,
		Speed = 55,               -- studs/sec down the aisle
		Damage = 70,
		RepassChance = 0.12,      -- chance it doubles back for a second pass
		MinGapSeconds = 85,       -- scheduling spacing while moving
		MaxGapSeconds = 150,
		CampSeconds = 95,         -- linger this long in one car and it is sent for you
		LampRelightSeconds = 24,  -- shattered car lamps rekindle after this
	},
	Inspector = {
		WarnSeconds = 25,
		WalkSpeed = 6.5,
		Damage = 55,              -- fallback if DamageByVisit is trimmed
		DamageByVisit = { 35, 55, 70 }, -- he grows less forgiving up the line
		FineFraction = 0.3,       -- fare stolen when caught ticketless
		StrictChance = { 0, 0.35, 0.7 }, -- per visit: odds he checks hide spots
		PauseSeconds = 1.1,
	},
	Gloom = {
		DriftSpeed = 9,
		HuntSpeed = 16,
		GrazeDamage = 15,
		SourceDamage = 60,
		SpawnChanceNoLights = 0.4, -- may prowl even a dark tunnel
	},
	Parallel = {
		GazeWhisperSeconds = 2.2, -- whispers begin
		GazeBreakSeconds = 4.0,   -- it comes through the glass
		Damage = 45,
		CarChance = 0.22,         -- ambient roll per newly-entered car
		CooldownSeconds = 55,
		MinDuration = 18,
		MaxDuration = 36,
	},
	Stowaway = {
		Damage = 35,
		BaseChance = 0.08,        -- mimic odds per eligible container, early cars
		DeepChance = 0.2,         -- odds beyond car 15
	},
	Sleeper = {
		StirAt = 0.4,             -- car-noise thresholds
		PanicAt = 0.7,
		WakeDamage = 50,
		MeterDecayPerSecond = 0.06,
	},
	Engineer = {
		PatrolSpeed = 8,
		ChaseSpeed = 14,
		Damage = 60,
		FlareStaggerSeconds = 5,
		CoupleSeconds = 10,       -- shared hold-progress to uncouple the engine
	},
}

----------------------------------------------------------------
-- Timetable (the director)
----------------------------------------------------------------
Config.Timetable = {
	TunnelBands = 3,             -- tunnels per run (dug out of the distance line)
	TunnelMinLength = 900,       -- studs of darkness
	TunnelMaxLength = 1900,
	GorgeBands = 2,              -- trestle bridge crossings
	GorgeLength = 2200,
	BeamSpacing = 420,           -- studs between low beams while on a gorge
	GraceAfterDamageSeconds = 12,-- no fresh scheduled events right after a mauling
	FirstEventCar = 3,           -- cars 1-2 are safe to learn the ropes
}

----------------------------------------------------------------
-- Ambient scares (client-local, personal, never damaging)
----------------------------------------------------------------
Config.Scares = {
	MinGapSeconds = 45,
	MaxGapSeconds = 115,
	FirstScareCar = 2,
	Weights = {
		phantom = 30,    -- a passenger who was never there
		stutter = 25,    -- the gaslight forgets itself
		whisper = 20,    -- someone close behind you
		coldpass = 15,   -- something moves through you
		doorcreak = 10,  -- the door ahead opens a hand's width
	},
	MimicBreathRange = 9, -- uneasy luggage is audible this close
}

----------------------------------------------------------------
-- Economy
----------------------------------------------------------------
Config.Economy = {
	Prices = {
		Ticket = 15,
		Bandage = 10,
		Flare = 12,
		Battery = 8,
		Oil = 8,
		Tonic = 25,
		Prybar = 20,
		Pocketwatch = 30,
	},
	PianoTipChance = 0.05,
	PianoTip = 10,
}

----------------------------------------------------------------
-- Scenery (client illusion of motion)
----------------------------------------------------------------
Config.Scenery = {
	ChunkLength = 96,
	ChunksAhead = 14,
	ChunksBehind = 8,
	GroundY = 0,               -- rail head height; train floor sits above
	FarLayerZ = 260,           -- mountain silhouettes
	FarParallax = 0.3,         -- fraction of train speed for the far layer
	BiomeBandLength = 2600,    -- how long each biome stretch lasts, roughly
}

----------------------------------------------------------------
-- Interaction hold durations (seconds)
----------------------------------------------------------------
Config.Interact = {
	Door = 0,
	JammedBash = 4,
	JammedPry = 1.5,
	Container = 0.6,
	CrateOpen = 1.4,
	CratePry = 0.6,
	Hide = 0,
	Revive = Config.Player.ReviveHoldSeconds,
	RoofClimb = 1,
	Blind = 0,
	Vend = 0.4,
	Couple = 1,               -- per-tick channel; total handled by Engineer logic
}

return Config
