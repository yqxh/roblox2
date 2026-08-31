--[[
	SoundBank.luau
	The whole soundscape is built from the EIGHT audio files every Roblox
	client is guaranteed to ship today (they're referenced by the engine's
	own RbxCharacterSounds): footsteps, jump, land, get-up, falling, swim,
	water impact, and the death moan. Everything else — bells, clacks,
	whooshes, creaks — is those eight bent hard by pitch, layering and EQ.

	SRC maps an "instrument" name to a real file plus a base pitch shift,
	so cue recipes read like music. To upgrade to licensed audio later:
	point the SRC entries at your uploaded rbxassetid:// files and set
	shift = 1. No other game code changes.
]]

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local SoundBank = {}

-- The guaranteed files (engine-shipped, no uploads, no moderation).
local FILES = {
	Steps = "rbxasset://sounds/action_footsteps_plastic.mp3",
	Jump = "rbxasset://sounds/action_jump.mp3",
	Land = "rbxasset://sounds/action_jump_land.mp3",
	GetUp = "rbxasset://sounds/action_get_up.mp3",
	Falling = "rbxasset://sounds/action_falling.ogg",
	Swim = "rbxasset://sounds/action_swim.mp3",
	Splash = "rbxasset://sounds/impact_water.mp3",
	Moan = "rbxasset://sounds/uuhhh.mp3",
}
SoundBank.FILES = FILES

-- Instruments: { file, baseShift }. Cue pitches multiply the shift.
local SRC = {
	-- true voices
	Steps = { FILES.Steps, 1 },
	Jump = { FILES.Jump, 1 },
	Land = { FILES.Land, 1 },
	GetUp = { FILES.GetUp, 1 },
	Falling = { FILES.Falling, 1 },
	Swim = { FILES.Swim, 1 },
	Splash = { FILES.Splash, 1 },
	Moan = { FILES.Moan, 1 },
	-- impersonations of the old orchestra
	Ping = { FILES.Splash, 2.6 },   -- bright plink
	Button = { FILES.Steps, 2.3 },  -- dry tap
	Snap = { FILES.Land, 1.7 },     -- wooden clack
	Swoosh = { FILES.Swim, 1.3 },   -- air
	Unsheath = { FILES.GetUp, 0.55 }, -- long creak
	Slash = { FILES.Swim, 2.0 },    -- sharp cut
	Lunge = { FILES.Swim, 0.8 },    -- heavy swing
}
SoundBank.SRC = SRC

-- name -> { {instrument, pitch, volume, delay?}, ... }
SoundBank.Cues = {
	-- UI
	UiTick = { { "Button", 1.6, 0.25 } },
	UiConfirm = { { "Button", 1.1, 0.35 }, { "Ping", 1.4, 0.15, 0.05 } },
	UiDeny = { { "Button", 0.55, 0.4 } },
	Toast = { { "Ping", 1.8, 0.12 } },
	Purchase = { { "Snap", 1.3, 0.4 }, { "Ping", 1.2, 0.2, 0.08 } },

	-- Train
	Clack = { { "Snap", 0.55, 0.32 }, { "Snap", 0.5, 0.26, 0.09 } },
	Clack2 = { { "Snap", 0.62, 0.28 }, { "Snap", 0.45, 0.22, 0.11 } },
	CouplerBang = { { "Land", 0.4, 0.8 }, { "Snap", 0.35, 0.6, 0.04 } },
	Whistle = { { "Moan", 0.62, 0.55 }, { "Moan", 0.93, 0.35, 0.25 } }, -- the 11:59 does not whistle; she moans
	WhistleFar = { { "Moan", 0.5, 0.3 }, { "Moan", 0.75, 0.2, 0.4 } },
	BrakeHiss = { { "Swim", 0.35, 0.5 }, { "Falling", 0.3, 0.3, 0.2 } },
	DoorSlide = { { "Swoosh", 0.7, 0.5 } },
	DoorSlam = { { "Land", 0.6, 0.7 }, { "Snap", 0.4, 0.5, 0.03 } },
	DoorBash = { { "Land", 0.5, 0.9 }, { "Snap", 0.3, 0.7, 0.05 } },
	PryCreak = { { "Unsheath", 0.4, 0.6 } },
	HatchOpen = { { "Unsheath", 0.6, 0.5 }, { "Snap", 0.8, 0.4, 0.2 } },
	BlindPull = { { "Swoosh", 1.2, 0.35 }, { "Snap", 1.1, 0.25, 0.12 } },
	WindowShatter = { { "Snap", 1.4, 0.9 }, { "Slash", 1.3, 0.7, 0.02 }, { "Snap", 1.8, 0.5, 0.09 } },
	Rummage = { { "Steps", 1.5, 0.4 }, { "Snap", 1.2, 0.25, 0.2 } },
	LatchOpen = { { "Snap", 1.05, 0.45 } },
	Piano = { { "Ping", 0.5, 0.5 }, { "Ping", 0.63, 0.45, 0.12 }, { "Ping", 0.42, 0.4, 0.26 }, { "Ping", 0.35, 0.5, 0.45 } },
	LampBurst = { { "Snap", 1.7, 0.6 }, { "Ping", 0.7, 0.3, 0.03 } },
	LampRelight = { { "Unsheath", 1.4, 0.3 }, { "Ping", 2.0, 0.12, 0.1 } },

	-- Player
	Land = { { "Land", 1.0, 0.45 } },
	Heal = { { "GetUp", 1.1, 0.5 } },
	Hurt = { { "Moan", 1.35, 0.5 } },
	Down = { { "Moan", 0.8, 0.7 }, { "Land", 0.5, 0.6, 0.1 } },
	Death = { { "Moan", 0.55, 0.8 } },
	Revive = { { "GetUp", 0.9, 0.6 }, { "Ping", 1.1, 0.25, 0.3 } },
	HeartThump = { { "Land", 0.36, 0.5 }, { "Land", 0.3, 0.35, 0.16 } },
	Breath = { { "Swim", 0.5, 0.14 } },
	FlareStrike = { { "Slash", 1.6, 0.5 }, { "Swim", 0.6, 0.4, 0.08 } },
	FlashClick = { { "Button", 1.3, 0.4 } },
	WatchTick = { { "Button", 2.2, 0.09 } },
	GhostRise = { { "Falling", 0.6, 0.4 }, { "Ping", 0.6, 0.25, 0.3 } },
	PingMark = { { "Ping", 1.0, 0.35 }, { "Ping", 1.5, 0.2, 0.12 } },

	-- Entities
	FurnacePiston = { { "Land", 0.45, 0.85 }, { "Snap", 0.35, 0.6, 0.07 }, { "Steps", 0.4, 0.5, 0.02 } },
	FurnaceRoar = { { "Moan", 0.4, 1 }, { "Slash", 0.5, 0.6, 0.1 }, { "Falling", 0.35, 0.7, 0.05 } },
	InspectorBell = { { "Ping", 0.8, 0.6 }, { "Ping", 0.8, 0.5, 0.7 }, { "Ping", 0.8, 0.45, 1.4 } },
	InspectorHmph = { { "Moan", 1.1, 0.35 } },
	InspectorPunch = { { "Snap", 0.9, 0.5 } }, -- the ticket punch, not a fist
	InspectorFine = { { "Slash", 0.7, 0.7 }, { "Moan", 0.9, 0.6, 0.1 } },
	GloomHiss = { { "Swim", 0.28, 0.6 }, { "Falling", 0.25, 0.45, 0.3 } },
	GloomFeed = { { "Splash", 0.5, 0.8 }, { "Moan", 0.6, 0.6, 0.15 } },
	ParallelWhisper = { { "Swim", 0.42, 0.25 }, { "Moan", 1.7, 0.12, 0.5 } },
	ParallelSlam = { { "Land", 0.55, 1 }, { "Snap", 1.3, 0.8, 0.03 } },
	StowawayBite = { { "Slash", 0.8, 0.8 }, { "Moan", 1.5, 0.5, 0.05 } },
	SleeperGrowl = { { "Moan", 0.45, 0.55 } },
	SleeperWake = { { "Moan", 0.32, 1 }, { "Land", 0.3, 0.8, 0.2 }, { "Slash", 0.4, 0.6, 0.35 } },
	EngineerShovel = { { "Slash", 0.5, 0.7 }, { "Snap", 0.45, 0.6, 0.12 } },
	EngineerBellow = { { "Moan", 0.38, 1 }, { "Moan", 0.5, 0.7, 0.3 } },
	Uncouple = { { "Snap", 0.5, 1 }, { "Land", 0.35, 0.9, 0.1 }, { "Unsheath", 0.5, 0.7, 0.3 } },

	-- World stingers
	StationBell = { { "Ping", 0.66, 0.5 }, { "Ping", 0.66, 0.4, 0.9 } },
	TunnelIn = { { "Falling", 0.4, 0.6 }, { "Moan", 0.5, 0.4, 0.3 } },
	BeamWhoosh = { { "Swoosh", 0.45, 0.9 } },
	Thunder = { { "Land", 0.25, 0.9 }, { "Falling", 0.28, 0.7, 0.2 } },
}

local function resolve(instrument)
	local src = SRC[instrument]
	if src then
		return src[1], src[2]
	end
	-- allow raw ids (e.g. swapped-in rbxassetid:// uploads)
	return instrument, 1
end

local function buildLayer(layer, parent, spec)
	local id, shift = resolve(layer[1])
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.PlaybackSpeed = shift * (layer[2] or 1) * (spec.pitchScale or 1)
	sound.Volume = (layer[3] or 0.5) * (spec.volumeScale or 1)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = spec.min or 10
	sound.RollOffMaxDistance = spec.max or 120
	if spec.group then
		sound.SoundGroup = spec.group
	end
	sound.Parent = parent
	return sound
end

--[[
	Play a cue.
	where: nil (non-spatial, SoundService) | a BasePart/Attachment | a Vector3.
	spec: {pitchScale, volumeScale, min, max, group, jitter}
]]
function SoundBank.play(cueName, where, spec)
	spec = spec or {}
	local cue = SoundBank.Cues[cueName]
	if not cue then
		warn("SoundBank: unknown cue " .. tostring(cueName))
		return 0
	end

	local host = nil
	local temp = false
	if typeof(where) == "Vector3" then
		host = Instance.new("Part")
		host.Anchored = true
		host.CanCollide = false
		host.CanQuery = false
		host.CanTouch = false
		host.Transparency = 1
		host.Size = Vector3.new(0.2, 0.2, 0.2)
		host.Position = where
		host.Parent = workspace
		temp = true
	elseif typeof(where) == "Instance" then
		host = where
	else
		host = SoundService
	end

	local jitter = spec.jitter or 0.04
	local longest = 0
	for _, layer in ipairs(cue) do
		local wait = layer[4] or 0
		longest = math.max(longest, wait + 1.2)
		task.delay(wait, function()
			if host.Parent == nil and host ~= SoundService then
				return
			end
			local s = buildLayer(layer, host, spec)
			if jitter > 0 then
				s.PlaybackSpeed *= 1 + (math.random() * 2 - 1) * jitter
			end
			s.PlayOnRemove = false
			s:Play()
			Debris:AddItem(s, 6)
		end)
	end
	if temp then
		Debris:AddItem(host, longest + 6)
	end
	return longest
end

-- A configured looping sound (caller owns lifecycle).
function SoundBank.loop(instrument, parent, spec)
	spec = spec or {}
	local id, shift = resolve(instrument)
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = spec.volume or 0.3
	sound.PlaybackSpeed = shift * (spec.pitch or 1)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = spec.min or 10
	sound.RollOffMaxDistance = spec.max or 120
	if spec.group then
		sound.SoundGroup = spec.group
	end
	sound.Parent = parent
	if spec.play ~= false then
		sound:Play()
	end
	return sound
end

return SoundBank
