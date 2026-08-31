# THE 11:59

*The last train out of the valley.*

A co-operative horror game for Roblox, built for groups of 1–8 friends.
Not another doors-and-rooms game: **the whole game is one moving night
train**. You board the caboose of a 28-car express and fight your way
forward, car by car, to the engine — through ticket inspections, tunnel
blackouts, gorge crossings, a thing that keeps pace with the windows, and
the Furnace that comes screaming down the aisle — then uncouple the
engine and coast into the dawn.

Everything is generated from parts at runtime from a per-run seed: no
uploaded assets, no external dependencies, one `rojo build` from a fresh
clone to a playable place file.

---

## Quick start

You need [Rojo](https://rojo.space) 7.x. Either install it yourself, or use
[rokit](https://github.com/rojo-rbx/rokit):

```bash
rokit install        # reads rokit.toml (rojo, selene, stylua)
rojo build -o The1159.rbxlx
```

Open `The1159.rbxlx` in Roblox Studio and press **Play**. That's it — the
game assembles itself on run.

For live-sync development:

```bash
rojo serve
# then in Studio: Rojo plugin -> Connect
```

### Testing multiplayer

In Studio: **Test → Clients and Servers → 2–4 players → Start**. The run
begins when anyone boards the caboose (or pulls the brass brake wheel
inside it to depart early).

### Publishing checklist

1. Publish the place to Roblox (File → Publish to Roblox As…).
2. In Game Settings → Security, enable **Studio Access to API Services**
   if you want persistent stats (escapes / best car) while testing in
   Studio. In live servers DataStores work automatically.
3. Recommended max server size: **8**.
4. The game already ships with `Lighting.Technology = Future`, PBR
   materials, tuned Atmosphere/Bloom/ColorCorrection/DepthOfField, and a
   full dynamic soundscape. Players on low graphics settings will
   automatically get a cheaper (but still correct) frame.

---

## How to play

| Input | Action |
| --- | --- |
| **WASD / stick** | Move |
| **Shift** | Sprint (stamina tank — watch the sliver under your health) |
| **C / Ctrl** | Crouch — quiet feet, and the only way to survive low bridge beams on the roof |
| **E** | Interact (doors, luggage, hide spots, blinds, vending machines) |
| **Q** | Ping — place a marker your whole crew can see |
| **1–6 / tap** | Hotbar |
| **Jump** | Slip out of a hide spot |

**The rules of the line**

- **Fare** is the currency. It's in the luggage. Spend it at station stops.
- **Be seated with a ticket** when the Inspector's three bells ring.
- **When the lamps die car by car — hide, or climb.** The under-seat
  crawl spaces, lockers and tarps are marked with prompts. The roof is
  always safe from the Furnace and never safe from anything else.
- **In dark tunnels, douse your lights.** The thing that lives there
  drinks light, and whoever holds it. A thrown flare is a meal that
  buys the rest of you time.
- **Don't stare at the thing outside the windows.** Pull the blinds.
- **Some luggage breathes.** Listen before you open.
- One car on the train is asleep. **Keep it that way.**
- Downed friends can be lifted (hold E). The dead ride on as **ghosts** —
  they can scout loot through the walls and mark mimics — and are made
  solid again at the next station stop. If everyone is a ghost, the
  line keeps you.
- The train stops twice, briefly. **The 11:59 waits for no one.**

The run ends at the tender: crank the coupling release while the
Engineer stalks the coal, and ride the freed cars into the sunrise.

---

## Project layout

```
default.project.json      Rojo tree: services, Future lighting, night grade
src/
  shared/                 Config (all tuning), Net (one-remote protocol),
                          RunPlan (seed -> whole run, shared by server+client),
                          Forge (part builders), Palette, SoundBank, ItemDefs,
                          Tags, Util
  server/                 Main bootstrap + GameLoop (state machine & motion),
                          TrainBuilder / CarPlans (procedural cars),
                          DoorSystem, HideSystem, LootSystem, ItemService,
                          PlayerService (health/downed/ghost/noise),
                          EconomyService, StationService, StatsService,
                          Timetable (the director), EntityUtil
  server/entities/        Furnace, Inspector, Gloom, Parallel, Stowaway,
                          Sleeper, Engineer
  client/                 ClientState, SceneryController (the moving night),
                          LightingDirector (the film grade), CameraFX,
                          AudioController, CharacterFX, PromptTheme,
                          GhostController, UIKit, UIController
  assets/                 ToolClient template cloned into every tool
```

Design details — every entity, the director's rules, the coordinate
system of the scrolling world — live in [DESIGN.md](DESIGN.md).

## Sound

The entire soundscape is synthesized from engine-shipped `rbxasset://`
files (pitched, layered, EQ'd), so the game is fully audible with zero
uploads and zero moderation risk. Every sound is a named **cue** in
`src/shared/SoundBank.luau`. To upgrade to licensed audio later, replace
only the `id` fields in the `SRC` table / cue recipes — no game code
changes anywhere.

## Linting

`selene.toml` + the vendored `roblox.yml` standard library lint offline:

```bash
selene src
```

(The official selene release binaries also parse Luau syntax; the vendored
std just avoids the network fetch of the Roblox API dump.)

## License

Do whatever you like with it. A credit ("THE 11:59") is appreciated.
