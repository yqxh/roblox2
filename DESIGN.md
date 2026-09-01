# THE 11:59 — design reference

A co-op horror where the dungeon is a moving train. This document is the
authoritative description of the systems; tuning constants live in
`src/shared/Config.luau`.

## The premise

1913. The valley's last evening service left Terminus at 11:59 and never
arrived. It still leaves every night. Riders board the caboose (car 1)
and push forward through 28 cars to the engine. Nobody drives the train;
nobody needs to. The goal is not to stop it — it cannot be stopped — but
to **uncouple the passenger cars from the engine** at the tender and
coast free.

## The illusion of motion

The train is *static geometry* along +X (car `i` spans
`X ∈ [(i-1)·48, (i-1)·48+44]`, floor top at `Y=10`, roof walk `~20.3`).
Motion is a shared number: the server integrates `distance` (studs of
night gone by) and replicates `TrainSpeed`/`TrainDistance` as workspace
attributes. Each client re-integrates locally (smooth at any ping) and
scrolls a **deterministic world** past the windows:

- A point on the ground at *track coordinate* `s` renders at
  `worldX = s - distance`.
- Chunks (96 studs) are generated from `hash(seed, chunkIndex)` —
  every player sees the same forest, the same lit farmhouse window.
- Biomes band the line: pine valley, marsh (fireflies, dead water),
  fields (fences, hay, farmhouses), freight yard (wrecks, signal eyes).
- A far ridge line scrolls at 0.3× speed for parallax; the moon stands
  still, camera-anchored.
- **Features** occupy windows of track: *tunnels* (rock walls swallow
  the line; portal faces at each end) and *gorges* (no ground at all —
  a trestle over black water 90 studs down).

Because chunk selection is positional, the *front* of the train enters a
tunnel before the rear leaves the moon — with zero networking.

The physical consequence: since the world moves and the train doesn't,
there are **no moving-platform physics bugs**, and everything outside
the glass costs the server nothing.

## The run

`Lobby → Journey ⇄ Station → Finale → Victory | Defeat → Lobby`

- **Lobby**: Terminus platform, tutorial plaques in the caboose,
  30 s countdown once anyone boards (brake wheel departs early).
- **Journey**: cars build 2 ahead of the leading rider and dissolve
  1 behind the trailing one (a black **void seal** eats the rear; the
  rear door locks). Fall off the train at speed and the valley keeps you.
- **Stations** (cars 10 and 19, names drawn per seed: Wick Hollow,
  Mournbrook…): the brakes find a stretch of track with no tunnel, a
  platform assembles alongside, side doors open. 80 seconds of vending
  machines, loose freight and breathing room. Lamps are relit, broken
  windows boarded, **ghosts are made flesh again** (at a fare penalty).
  At the whistle the doors shut; whoever is still on the platform
  watches it slide backward into the dark, and rides on as a ghost.
- **Finale**: the tender. Coal, an open sky, the Engineer, and the
  coupling release — a shared crank (each hold adds progress). Flares
  blind him for seconds. On release, everyone in the tender leaps back
  to car 27, the engine tears away, and dawn breaks over 20 seconds of
  sky as the cars coast home.
- **Defeat**: every rider a ghost at once. The train keeps its schedule.

## Riders

- 100 HP; lethal damage → **downed** (40 s bleed-out, any friend lifts
  you in 5 s to 35 HP). Death → inventory scatters where you fell and
  you rise as a **ghost**: translucent, uncollidable, ignored by
  entities, passes through doors, 22 walkspeed. Ghosts can't touch
  anything but they can **see** — unopened containers glow through the
  walls, and mimicked luggage glows red — and they can **ping**. The
  next station revives them. Late joiners board mid-run as ghosts.
  A rider with no living companions gets one **second chance** per run:
  their first death costs half their fare and puts them back on their
  feet at the rear of the train instead of into ghosthood.
- **Stamina**: 6 s of sprint, slow regen. **Crouch**: slow and quiet.
- **Noise** (server-computed, 0–1, shown as a candle flame that fattens):
  movement speed, jumps, door bashes, pried crates, flares, the piano.
  The Sleeper, the Gloom and the Stowaway all listen.

## Economy & items

**Fare** spills out of everything you rummage: under-seat bags, luggage
racks, sleeper drawers, dining cabinets, mail sacks, nailed crates (pry
bar: fast and quiet; shoulder: slow and loud), a caged strongbox, the
red car's chests — and lashed **roof cargo** on ~a third of enclosed
cars, so the roof route is an economy, not just a Furnace dodge. Two
vending stops to spend it.

Items (all procedural Tools; passives are counters):
**Torch** (battery-limited spotlight) · **Oil Lantern** (bright, warm,
*a liability in tunnels*) · **Flare** (strike, then hold or throw — light,
noise, bait, and Engineer-repellent) · **Bandage** (3 s channel, +35) ·
**Dr. Voss' Tonic** (full heal + speed) · **Ticket** (be seated at
inspection) · **Pry Bar** (jammed doors, nailed crates, unique) ·
**Conductor's Watch** (unique: reads the Timetable — next Furnace,
tunnels, stops — but it *ticks*, and ticks are noise) · **Battery/Oil**
refills · **Brass Key** (two locked doors per run; keys always spawn
within reach behind you).

Fairness guarantees baked into loot: tickets seed the two cars before
every inspection (extra in the car adjacent), a pry bar turns up by car
3, the watch surfaces mid-train if nobody found one, key cars are
deterministic per seed.

## The seven

1. **The Furnace** — the engine's appetite. Scheduled every 85–150 s
   (and *sent early* at anyone who camps a car past 95 s). Six seconds
   of warning: lamps flicker, pistons hammer, then every light down the
   line bursts car by car as it tears rearward at 55 stud/s through the
   aisle. Counterplay: any hide spot, or the roof. 12% of passes double
   back. Shattered lamps rekindle after ~24 s of dark aftermath.
2. **The Inspector** — three bells, 25 s, then he boards ahead and walks
   the whole occupied train rearward, lantern swinging, doors opening
   themselves before him. Seated + ticket → punched, safe. Hidden →
   safe the first visit; he checks hiding spots with rising suspicion on
   later visits (0% / 35% / 70%). Caught standing or ticketless: heavy
   damage and a 30% fare fine. He steps over the downed ("sleeping berth
   surcharge"). Roof riders are beneath his contempt.
3. **The Gloom** — lives in the dark tunnels (65% of them). It cannot
   see riders, only light, and drifts to the brightest source aboard:
   ground flare > held flare > lantern > torch. Reaching a held light:
   60 damage and the light is drunk dry. Reaching a thrown flare: it
   feeds for 5 s (the intended sacrifice play). With nothing lit it
   sweeps the aisle blind — crouch, hold still, let the cold pass
   through you.
4. **The Parallel** — something keeps pace with the train, out in the
   fields at window height, or standing on the far end of a flatcar
   deck. It obeys one rule, rendered per-client: **watched, it freezes
   mid-stride (only its head finds your face); unwatched, it closes the
   distance**, from the treeline to breathing on the glass, whispering
   louder the nearer it stands. Meanwhile your own gaze is measured and
   arbitrated by the server: 2.2 s of looking starts the whispers, 4 s
   and it comes through the nearest pane (45 damage, the window stays
   broken and howling until the next station). Blinds block it
   entirely — pulling them is teamwork. So the choice each time: pin it
   with your eyes and ration your seconds, or look away and let it walk.
5. **The Stowaway** — some luggage packed itself. Mimicked suitcases,
   crates and chests (8% early, 20% past car 15, always two among the
   red car's five chests) bite for 35, steal one belonging, and drag it
   *one car forward* — chase it or write it off. The tell: marked cases
   are subtly restless, and ghosts see them outlined in red.
6. **The Sleeper** — one car (14–16) is a nest, and the nest is full.
   A car-wide meter rises with every rider's noise inside (sprinting,
   slams, flares are worst) and decays slowly: eyes crack open at 40%,
   the breathing changes at 70%, and at 100% it *wakes* — 50 damage to
   everyone in the car, hurled down the aisle, and it howls the Furnace
   in early. The temptation: the richest loot on the train ring its bed.
7. **The Engineer** — the finale. Patrols tender and cab at 8 stud/s;
   line of sight sets him charging at 14 (sprint outruns him, walking
   doesn't). His shovel downs riders in two hits. A flare landing within
   seven studs blinds him for 5 s. He cannot leave the tender — car 27
   is the retreat line.

## The small lies (ambient scare director)

Between real events, each client runs a private scare scheduler
(45–115 s apart, suppressed near genuine tells so ambient dread never
teaches a false lesson): a passenger seated ahead who was never there
(approach or stare and they gutter out), gaslight stutters, a whisper
just behind the ear, a cold pass through the chest, the door ahead
easing open a hand's width. All personal, all harmless, all unshared —
"did anyone else see that?" is designed to have no witnesses. The same
system gives mimicked luggage its promised tell: within nine studs, the
case audibly breathes and faintly shivers.

Big hits (≥45) and deaths land a quarter-second jumpscare frame — a
black flash with pale eyes that blink once — skipped entirely by the
"Steady camera" accessibility toggle (the sound remains).

## The Timetable (director)

One scheduler owns the night: Furnace cadence with jitter, inspections
fixed at cars 6/13/22, tunnel/gorge features read positionally from the
seed, beams over the roof during gorges (3 s warning, crouch or take 45),
ambient Parallel rolls per newly-entered car (22%, 55 s cooldown, forced
in the red car), the Sleeper armed on entry to its car. Mercy rules: no
scheduled event lands within 12 s of the group's last mauling, and cars
1–2 are event-free so first-timers learn the verbs. Cruelty rule:
lingering anywhere too long summons the Furnace personally.

Holders of the Conductor's Watch receive the next three entries, ETA'd.

## The grade ("shaders")

Roblox exposes no custom shader pipeline, so the film look is built from
everything it does expose, pushed deliberately:

- `Lighting.Technology = Future` (set in the place file), full PBR
  materials, `EnvironmentDiffuse/SpecularScale = 1`, soft shadows.
- Client-owned post stack: tuned `Atmosphere` (indigo density that
  thickens in tunnels), `Bloom` for gaslight and the moon, a base
  `ColorCorrection` grade (cool exterior / warm interior crossfade as
  you move through the train), a second CC layer for damage/furnace
  pulses, subtle `DepthOfField`, dynamic `Clouds`.
- Gaslight **flicker** (Perlin, per-lamp phase, storm-flicker during
  Furnace warnings), **swinging fixtures** driven by train speed,
  red emergency strips that only live in tunnels.
- Camera: speed-scaled Perlin rumble, paired rail-joint clacks, sprint
  FOV stretch, directional damage kicks, the Furnace's rising quake —
  all behind a "Steady camera" accessibility toggle.
- Victory rewrites the sky: ClockTime rolls to dawn, the atmosphere
  warms, bloom lifts. Defeat drains the world grey.

## Audio without assets

Every cue is layered from engine-shipped `rbxasset://` sounds bent by
pitch/EQ/reverb (the train's whistle is a slowed human moan — she does
not whistle, she *moans*). Beds: wheel-rhythm clacks spaced by true
speed, wind that rises on the roof, a low drone, distant answering
moans. States: tunnel low-pass, hide-spot muffle + own heartbeat,
low-HP heartbeat. All swappable in one file (`SoundBank.luau`).

## Networking & trust

One RemoteEvent, string topics, per-topic rate limits. The client is
trusted with nothing but its own movement and its own eyes: loot rolls,
damage, fines, fuel, purchases, hide occupancy and inspection verdicts
are all server-side. The two client-reported signals (Parallel gaze,
stance) can only hurt the reporter.

## Performance

- Cars: ~150–300 parts each, at most ~6 built at once; scenery: ~30
  active chunks of ≤40 parts, recycled at ~0.4/s; entities are
  single-digit part rigs. No unanchored physics except thrown flares.
- Scenery, lighting, audio and UI are entirely client-local: the server
  simulates only gameplay.

## Deliberate omissions (scope guard)

No voice lines, no cutscene camera takeovers, no persistent upgrades
beyond stats, no branching train layout. The night itself is the
content; the seed makes it a different night each time.
