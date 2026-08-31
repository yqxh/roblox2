--[[
	SoundBank.luau
	The whole soundscape is built from engine-shipped rbxasset:// files —
	they exist in every client with zero uploads or moderation risk — bent
	far out of shape with pitch, EQ and reverb. Each cue below is a recipe:
	layers of {id, pitch, volume, delay}.

	To upgrade to licensed audio later: replace the `id` fields only.
	Every cue keeps the same name, so no game code changes.
]]

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local SoundBank = {}

-- Engine-shipped source files (guaranteed present, no network fetch).
local SRC = {
	Ping = "rbxasset://sounds/electronicpingshort.wav",
	Button = "rbxasset://sounds/button.wav",
	Snap = "rbxasset://sounds/snap.mp3",
	Swoosh = "rbxasset://sounds/swoosh.wav",
	Unsheath = "rbxasset://sounds/unsheath.wav",
	Slash = "rbxasset://sounds/swordslash.wav",
	Lunge = "rbxasset://sounds/swordlunge.wav",
	Moan = "rbxasset://sounds/uuhhh.mp3",
	Splash = "rbxasset://sounds/impact_water.mp3",
	Steps = "rbxasset://sounds/action_footsteps_plastic.mp3",
	Jump = "rbxasset://sounds/action_jump.mp3",
	Land = "rbxasset://sounds/action_jump_land.mp3",
	GetUp = "rbxasset://sounds/action_get_up.mp3",
	Falling = "rbxasset://sounds/action_falling.mp3",
	Swim = "rbxasset://sounds/action_swim.mp3",
}
SoundBank.SRC = SRC

-- name -> { {id, pitch, vol, delay?, len?}, ... }
SoundBank.Cues = {
	-- UI
	UiTick = { { SRC.Button, 1.6, 0.25 } },
	UiConfirm = { { SRC.Button, 1.1, 0.35 }, { SRC.Ping, 1.4, 0.15, 0.05 } },
	UiDeny = { { SRC.Button, 0.55, 0.4 } },
	Toast = { { SRC.Ping, 1.8, 0.12 } },
	Purchase = { { SRC.Snap, 1.3, 0.4 }, { SRC.Ping, 1.2, 0.2, 0.08 } },

	-- Train
	Clack = { { SRC.Snap, 0.55, 0.32 }, { SRC.Snap, 0.5, 0.26, 0.09 } },
	Clack2 = { { SRC.Snap, 0.62, 0.28 }, { SRC.Snap, 0.45, 0.22, 0.11 } },
	CouplerBang = { { SRC.Land, 0.4, 0.8 }, { SRC.Snap, 0.35, 0.6, 0.04 } },
	Whistle = { { SRC.Moan, 0.62, 0.55 }, { SRC.Moan, 0.93, 0.35, 0.25 } }, -- the 11:59 does not whistle; she moans
	WhistleFar = { { SRC.Moan, 0.5, 0.3 }, { SRC.Moan, 0.75, 0.2, 0.4 } },
	BrakeHiss = { { SRC.Swim, 0.35, 0.5 }, { SRC.Falling, 0.3, 0.3, 0.2 } },
	DoorSlide = { { SRC.Swoosh, 0.7, 0.5 } },
	DoorSlam = { { SRC.Land, 0.6, 0.7 }, { SRC.Snap, 0.4, 0.5, 0.03 } },
	DoorBash = { { SRC.Land, 0.5, 0.9 }, { SRC.Snap, 0.3, 0.7, 0.05 } },
	PryCreak = { { SRC.Unsheath, 0.4, 0.6 } },
	HatchOpen = { { SRC.Unsheath, 0.6, 0.5 }, { SRC.Snap, 0.8, 0.4, 0.2 } },
	BlindPull = { { SRC.Swoosh, 1.2, 0.35 }, { SRC.Snap, 1.1, 0.25, 0.12 } },
	WindowShatter = { { SRC.Snap, 1.4, 0.9 }, { SRC.Slash, 1.3, 0.7, 0.02 }, { SRC.Snap, 1.8, 0.5, 0.09 } },
	Rummage = { { SRC.Steps, 1.5, 0.4 }, { SRC.Snap, 1.2, 0.25, 0.2 } },
	LatchOpen = { { SRC.Snap, 1.05, 0.45 } },
	Piano = { { SRC.Ping, 0.5, 0.5 }, { SRC.Ping, 0.63, 0.45, 0.12 }, { SRC.Ping, 0.42, 0.4, 0.26 }, { SRC.Ping, 0.35, 0.5, 0.45 } },
	LampBurst = { { SRC.Snap, 1.7, 0.6 }, { SRC.Ping, 0.7, 0.3, 0.03 } },
	LampRelight = { { SRC.Unsheath, 1.4, 0.3 }, { SRC.Ping, 2.0, 0.12, 0.1 } },

	-- Player
	Land = { { SRC.Land, 1.0, 0.45 } },
	Heal = { { SRC.GetUp, 1.1, 0.5 } },
	Hurt = { { SRC.Moan, 1.35, 0.5 } },
	Down = { { SRC.Moan, 0.8, 0.7 }, { SRC.Land, 0.5, 0.6, 0.1 } },
	Death = { { SRC.Moan, 0.55, 0.8 } },
	Revive = { { SRC.GetUp, 0.9, 0.6 }, { SRC.Ping, 1.1, 0.25, 0.3 } },
	HeartThump = { { SRC.Land, 0.36, 0.5 }, { SRC.Land, 0.3, 0.35, 0.16 } },
	Breath = { { SRC.Swim, 0.5, 0.14 } },
	FlareStrike = { { SRC.Slash, 1.6, 0.5 }, { SRC.Swim, 0.6, 0.4, 0.08 } },
	FlashClick = { { SRC.Button, 1.3, 0.4 } },
	WatchTick = { { SRC.Button, 2.2, 0.09 } },
	GhostRise = { { SRC.Falling, 0.6, 0.4 }, { SRC.Ping, 0.6, 0.25, 0.3 } },
	PingMark = { { SRC.Ping, 1.0, 0.35 }, { SRC.Ping, 1.5, 0.2, 0.12 } },

	-- Entities
	FurnacePiston = { { SRC.Land, 0.45, 0.85 }, { SRC.Snap, 0.35, 0.6, 0.07 }, { SRC.Steps, 0.4, 0.5, 0.02 } },
	FurnaceRoar = { { SRC.Moan, 0.4, 1 }, { SRC.Slash, 0.5, 0.6, 0.1 }, { SRC.Falling, 0.35, 0.7, 0.05 } },
	InspectorBell = { { SRC.Ping, 0.8, 0.6 }, { SRC.Ping, 0.8, 0.5, 0.7 }, { SRC.Ping, 0.8, 0.45, 1.4 } },
	InspectorHmph = { { SRC.Moan, 1.1, 0.35 } },
	InspectorPunch = { { SRC.Snap, 0.9, 0.5 } }, -- the ticket punch, not a fist
	InspectorFine = { { SRC.Slash, 0.7, 0.7 }, { SRC.Moan, 0.9, 0.6, 0.1 } },
	GloomHiss = { { SRC.Swim, 0.28, 0.6 }, { SRC.Falling, 0.25, 0.45, 0.3 } },
	GloomFeed = { { SRC.Splash, 0.5, 0.8 }, { SRC.Moan, 0.6, 0.6, 0.15 } },
	ParallelWhisper = { { SRC.Swim, 0.42, 0.25 }, { SRC.Moan, 1.7, 0.12, 0.5 } },
	ParallelSlam = { { SRC.Land, 0.55, 1 }, { SRC.Snap, 1.3, 0.8, 0.03 } },
	StowawayBite = { { SRC.Slash, 0.8, 0.8 }, { SRC.Moan, 1.5, 0.5, 0.05 } },
	SleeperGrowl = { { SRC.Moan, 0.45, 0.55 } },
	SleeperWake = { { SRC.Moan, 0.32, 1 }, { SRC.Land, 0.3, 0.8, 0.2 }, { SRC.Slash, 0.4, 0.6, 0.35 } },
	EngineerShovel = { { SRC.Slash, 0.5, 0.7 }, { SRC.Snap, 0.45, 0.6, 0.12 } },
	EngineerBellow = { { SRC.Moan, 0.38, 1 }, { SRC.Moan, 0.5, 0.7, 0.3 } },
	Uncouple = { { SRC.Snap, 0.5, 1 }, { SRC.Land, 0.35, 0.9, 0.1 }, { SRC.Unsheath, 0.5, 0.7, 0.3 } },

	-- World stingers
	StationBell = { { SRC.Ping, 0.66, 0.5 }, { SRC.Ping, 0.66, 0.4, 0.9 } },
	TunnelIn = { { SRC.Falling, 0.4, 0.6 }, { SRC.Moan, 0.5, 0.4, 0.3 } },
	BeamWhoosh = { { SRC.Swoosh, 0.45, 0.9 } },
	Thunder = { { SRC.Land, 0.25, 0.9 }, { SRC.Falling, 0.28, 0.7, 0.2 } },
}

local function buildLayer(layer, parent, spec)
	local sound = Instance.new("Sound")
	sound.SoundId = layer[1]
	sound.PlaybackSpeed = (layer[2] or 1) * (spec.pitchScale or 1)
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
	Returns total scheduled length estimate (for sequencing).
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
		local delay = layer[4] or 0
		longest = math.max(longest, delay + 1.2)
		task.delay(delay, function()
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
function SoundBank.loop(sourceName, parent, spec)
	spec = spec or {}
	local sound = Instance.new("Sound")
	sound.SoundId = SRC[sourceName] or sourceName
	sound.Looped = true
	sound.Volume = spec.volume or 0.3
	sound.PlaybackSpeed = spec.pitch or 1
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
