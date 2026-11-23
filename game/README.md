# Albion After — main game

**P1 terrain update:** The native large-world terrain now supports sparse height edits; this increment adds color-only patches without collision resets, non-destructive editor layer binding and viewport sculpt. See [Native Terrain Patch Streaming](docs/NATIVE_TERRAIN_PATCH_STREAMING.md).

**P1 GPU-resident meshlet pages (experimental):** bounded task/mesh shader geometry residency, camera-prioritized CPU page scheduling, and opt-in rendering with an actual Albion rock asset. Regular gameplay/materials remain unchanged. See [GPU Meshlet Residency](docs/P1_GPU_MESHLET_RESIDENCY.md).

**This is the canonical game project at `game/`.** All new gameplay
features belong here. It is the only game in the repository; `demo/` and `misc/` hold engine labs, not games.

**Story campaign — three playable chapters:** Beacon Seven's Last Transmission leads into the underground quarantine vault and the missing medical convoy. Player decisions in Chapter II affect Chapter III recordings and its four possible epilogues. Quest progress comes only from authenticated world actions, is saved per character, and is visible in the in-game journal. See [Chapter I](docs/STORY_CAMPAIGN_CHAPTER_1.md), [Chapter II](docs/STORY_CAMPAIGN_CHAPTER_2.md), and [Chapter III](docs/STORY_CAMPAIGN_CHAPTER_3.md).

**New engine/game feature — bounded AI decision replay:** Cgame now records optional multi-tick BehaviorTree traces, allows skipping unchanged decisions and ranks CPU-heavy tasks by estimated exclusive execution time. The playable sandbox has Previous/Next/Live replay, while Albion After server NPCs expose an optional eight-tick private decision history. See [Native AI Perception and Diagnostics](docs/NATIVE_AI_PERCEPTION.md).

**New engine/game feature — visual BehaviorTree inspector:** Cgame now exposes a full tree snapshot with visited/unvisited paths and CPU timing, an enabled **Cgame AI** dock in the Godot editor and a live colored debug tree in the AI sandbox. The canonical Albion After infected server state machine exposes a compatible private diagnostic hierarchy. See [Native AI Perception and Diagnostics](docs/NATIVE_AI_PERCEPTION.md).

**New engine/game feature — opt-in AI execution tracing:** the native `AIBehaviorTrace` records bounded per-node execution order, paths, status and CPU time for BehaviorTree runners, with **T** to view active traces in the AI sandbox. The canonical server's zombie AI also supports on-demand native target-selection traces, disabled in normal gameplay. See [Native AI Perception and Diagnostics](docs/NATIVE_AI_PERCEPTION.md).

**New engine/game feature — timed AI decorators and authoritative howler cooldowns:** the Cgame BehaviorTree gains native `BehaviorTreeTimeout` and `BehaviorTreeCooldown` Resources and a reusable `AIActionCooldowns` ledger. The playable sandbox limits sound searches; Albion After howlers now prevent overlapping pack-alert bursts without touching combat cooldowns. See [Native AI Perception and Timers](docs/NATIVE_AI_PERCEPTION.md).

**New engine/game feature — source-aware AI perception history:** the native `AIStimulusHistory2D` keeps a bounded history of confirmed visual and audible events per infected NPC. When the strongest sound expires, an independently verified later sound can guide investigation without granting hidden-player targeting or bypassing safe zones. See [Native AI Perception](docs/NATIVE_AI_PERCEPTION.md).

**New engine/game feature — deterministic AI update scheduling:** the native `AIUpdateScheduler` spreads nonurgent target scans across stable server ticks when 128+ infected are active, while initial selection, combat threats and attacks remain responsive. The same scheduler throttles A* repaths in the playable AI sandbox. See [AI Update Scheduling](docs/AI_UPDATE_SCHEDULING.md).

**New engine/game feature — server encounter director:** world incidents now
respect nearby living infected, actual survivor health and global spawn headroom.
The authoritative `GameServer` reduces or delays additional waves when an
area is overcrowded; its tests run in `game/tests/run_all.gd`. See
[Server Encounter Director](docs/SERVER_ENCOUNTER_DIRECTOR.md).

**New server engine functionality — tick profiler and adaptive workloads:**
the dedicated server records a bounded history of simulation tick durations
and CPU-side p95; sustained overload temporarily limits *new random incident*
reinforcements without skipping AI, attacks or network ticks. Every 10 seconds
the server logs p95 and current incident cap. Start with
`--fixed-incidents` to disable automatic backpressure. See
[Server Tick Profiler](docs/SERVER_TICK_PROFILER.md).

**New server engine functionality — spatial player presence index:** infected
population maintenance now builds one index of living survivor positions and
uses it for exact 12 m no-spawn and 130 m unload checks. Large multiplayer
sessions benefit from spatial candidate filtering; solo and small groups
retain fast direct checks. Dedicated-server diagnostics report the number of
queries, player candidates examined and bucket lookups per maintenance pass.
See [Server Player Presence Grid](docs/SERVER_PLAYER_PRESENCE_GRID.md).

An original post-apocalyptic survival sandbox RPG: infected enemies,
scavenging, hunger/thirst, safe hub and dangerous zones, tiered resource
gathering, crafting/refining, equipment-based combat, full-loot risks outside
the hub, and a server-authoritative simulation. Genre ideas are used without
copying proprietary assets or content from other titles.

## Three survivor slots in solo play

The title screen offers three separate offline solo survivors, each with its
own inventory/skills, persistent world barriers, local stop signal, and a
loopback-only ENet server port. Slot 1 reuses all the old solo save files and,
when local Nakama is available, still supports the account-backed character.
Slots 2 and 3 always use independent local saves instead of sharing the
Nakama account. **Join server** remains unchanged. See
`game/docs/SOLO_CHARACTER_SLOTS.md`.

## Start with Play solo or Join server

The default `game/project.godot` scene is the unified online client
(`scripts/client/online_main.tscn`). **Play solo** launches a loopback-only
headless world, using the same multiplayer GameServer as online play. When a
local Nakama service is available it uses authenticated character persistence.
When Nakama is not running, the dedicated solo server instead saves one real
survivor's inventory, stash, skills, and health into
`user://albion_after_solo_character.json`, on a 20-second interval and logout.
The solo launcher requests a **graceful stop** so the world and character are
flushed before quitting (with a bounded emergency hard-kill fallback).
Public offline guest servers still do not persist anonymous characters.

There is one client: `scripts/client/online_main.tscn`. The old offline
preview scene (`client_main`) was removed on 2026-11-22 so every feature lands
in the game players actually run.

## Run the game

Open `game/project.godot` with a compiled Cgame editor or start:

```bash
godot --path game
```

This launches `scripts/client/online_main.tscn`: choose **Play solo** (a
loopback-only local world on the same `GameServer` as online play) or **Join
server**. Movement, crafting, combat and survival rules live only in the server
simulation; the client renders and sends input.

New melee choice: **Ruin Machetes T1–T4** combine scavenged scrap with
tier-matched planks and metal bars at the workbench. Equip one with **4**
(which cycles owned weapons), then press **G** for Cleaving Arc: 28 combat
energy, 7-second cooldown, up to three distinct enemies in a 3-metre
forward melee cone. Spear thrusts keep their narrower piercing line.
A miss still spends energy; safe-hub, party, and guild PvP protection
remain authoritative. No native engine change is needed.

A new **Salvage Sledgehammer T1–T4** can be crafted at the workbench from
tiered planks, metal bars and scavenged scrap. Its equipped **G** skill,
Concussive Blow, costs 35 combat energy with a 9-second cooldown. A real melee
hit staggers ordinary infected for 1.3 seconds and elites for 0.65 seconds;
a raid boss is immune. Stagger interrupts an active acid-spit windup, never
affects a player or creates free damage, and appears as a blue enemy highlight
in both clients. All hit, energy, timing and immunities are server-owned.

Controls: WASD movement, Shift sprint, E gather, Q loot, F attack,
Tab choose recipe, C craft, 1 food, 2 water, 3 bandage,
4 equip club, 5 equip jacket, R drink from natural water.

### Crafting tiers and classless progression in the client

The local preview now lists **every recipe in the authoritative item registry**,
including T1-T4 tools, refined materials, melee gear and armor.
Use **Tab / Shift+Tab** to choose the next/previous recipe and **C** to craft.
Actual station, materials, profession-tier and inventory-space checks remain
on `GameServer`, so a higher-tier recipe appearing in the menu does not mean
it can be crafted without training.

The HUD also shows separate wood, stone, ore, fiber and crafting levels,
current carried kilograms, encumbrance-adjusted movement speed, and whether
the character is in the **safe hub** or at risk of **PvP/full loot**.
These values come from the existing server-owned inventory and progression
rather than being guessed from player actions.

### Safe hub protected stash (local preview)

Return to the blue stash building beside the workbench (x=5, z=0).
Press **B** to open/close the stash, **J** to select the next item,
**K** to deposit one item and **L** to withdraw one. Hold Shift with K/L
for up to 10 at once, limited by the source quantity and item stack size.
The HUD shows selected item, carried and stored quantities, and available
items. The window closes if you leave the station or die.

Transfers call the existing `GameServer.cmd_stash` authoritative validation:
the player must be alive, close to the workbench, and have sufficient items
and destination space. Deposited equipment is automatically unequipped if
it is no longer carried. The protected stash does not drop on death.
The local preview's memory resets when the process exits; account-bound
persistence requires the connected server/Nakama path.

No new engine APIs are needed: Godot's UI and the existing inventory/network
interfaces cover this feature. Verify in the compiled engine with:

```bash
godot --headless --path game --script res://tests/smoke_client_scene.gd
godot --headless --path game --script res://tests/run_all.gd
```

The workbench is near world coordinates x=9, z=0. Leave the safe hub
to collect resources; higher-tier nodes require higher-tier tools.

## Sprint stamina

Survivors have 100 stamina. Sprinting with a light-enough backpack consumes
18 stamina per second. After 0.8 seconds of rest, stamina regenerates at
11 points per second. Hunger or thirst at 20 or below halves recovery;
critical hunger or thirst (5 or less) blocks sprint. The dedicated server
deducts stamina only from accepted movement time and includes the result in
snapshots; client prediction uses the same rule, then reconciles to the server.
Stamina survives account logouts, defaults to full in legacy v1 saves and
is restored on respawn. Existing Cgame script APIs suffice.

## Dedicated server and tests

```bash
godot --headless --path game --script res://scripts/server/server_main.gd -- --port 24565
godot --headless --path game --script res://tests/run_all.gd
godot --headless --path game --script res://tests/smoke_client_scene.gd
```

The dedicated server runs without optional Nakama integration.
If `--nakama` is supplied, a separately provided
`scripts/server/nakama_gateway.gd` integration is required; when absent,
startup fails with a clear error rather than a broken script preload.

Game features use existing engine APIs. Only move code into Cgame when a
reusable feature is missing, backed by native regression tests. These scripts
have not yet passed a headless Godot run in this environment.

## Hardened server-side save loading

The authoritative server now rejects malformed carried or banked item stacks,
unknown item types, fractional/nonfinite quantities and invalid equipment
slots before changing a live character. Survival stats and counters receive
the same bounded validation. Existing version-1 Nakama characters without
progression or a protected bank remain compatible. The offline regression
suite includes `game/tests/test_save_validation.gd`:

```sh
godot --headless --path game --script res://tests/run_all.gd
```

This logic lives in the game, not in the engine, because Godot already
provides the necessary script and serialization features.


## Survival stealth: noise attracts infected

The authoritative server computes temporary noise from **actual running
movement** (21 m for 0.8 s) and **pistol fire with ammunition** (32 m for
3 s). Nearby infected can notice a noisy survivor beyond their ordinary
sight radius, but safe-zone and pursuit-distance restrictions still apply.
Noise expires if the player stops making it, clears on respawn, and is never
trusted as a client-provided RPC value.

No network protocol, native engine API or save-schema migration is required:
the existing player-input simulation and zombie state machine implement the
mechanic inside `game/`. The new `test_sound.gd` exercises input budgets,
empty ammunition, sound expiry and server-to-AI detection. Run all suites with:

```sh
godot --headless --path game --script res://tests/run_all.gd
```

## Reconnect and persistence ordering

With Nakama enabled, account writes are serialized by user ID, and a second
login cannot reload an old snapshot until the previous session has been
saved. Simultaneous logins for the same account are gated while verification
and restoration are in progress. Failed disconnect saves remain in memory;
a player cannot rejoin from an older storage snapshot until a retry succeeds.
Existing corrupt character saves are refused rather than replaced with a
fresh starter kit. An orderly `--quit-after` stop flushes online accounts.

**Production limitation:** this protects a single running world server, not
multiple servers sharing an account store. In-memory pending saves are lost
on process crash, and periodic autosaves can lose progress after abrupt exit.
Before enabling real-money markets or cross-server trading, implement durable
transaction journals and optimistic storage versions at the backend.

## World risk, PvP and full loot

Green (T1) and yellow (T2) are **PvE-only** in this first iteration.
Death to zombies or survival hazards in those zones retains carried gear,
including equipped equipment. Respawning there does **not** duplicate starter
items. Red (T3) and black (T4) enable PvP and full carried-inventory loot on
death. Only a character *and* their target inside red/black can PvP, so
border sniping into protected zones is blocked. The hub remains a safe area.
Account-bound stash and permanent profession XP are protected everywhere.
This yellow-zone behavior is intentionally simpler than Albion's nonlethal
PvP; it can be extended once a downed/knockout system exists.

The zone banner and death overlay clearly show the risk, with server-authoritative
checks and regression tests in `game/tests/test_zone_risk.gd`. Run
`godot --headless --path game --script res://tests/run_all.gd`.

## Safe-hub NPC vendor — the canonical `game/` economy

A working server-authoritative NPC vendor is available at the existing
workbench (around x=9, z=0). It links Days After-style scavenging to
Albion-style resource progression and the existing silver currency.

| Action | Server-defined cost or payout |
| --- | --- |
| Buy water bottle | 12 silver |
| Buy canned food | 18 silver |
| Buy bandage | 16 silver |
| Sell scrap metal | +3 silver |
| Sell T1 wood / stone / fiber | +2 silver each |
| Sell T1 ore | +3 silver |
| Sell T2–T4 resources | Higher fixed, tier-scaled silver payouts |

In the local preview, **N** buys one water bottle and **V** sells one piece
of scrap (or wood if no scrap is carried) at the hub. Existing **B** stash
controls are unchanged. The online client has buy/sell buttons in the **I**
inventory panel. All requests are sent to the same authoritative server,
not executed locally by the client.

Trades require a live player within workbench range, a listed item,
and a quantity of 1–50. A private copy of the inventory is debited and
credited, then committed only if both halves fit. Invalid prices, insufficient
silver/materials, full backpack slots and remote requests change nothing.
The successful transaction is included in the existing inventory snapshots
and persistent Nakama character state.

This is an NPC vendor, **not** a player-run auction house or a finished MMO
economy. The mechanism uses existing Cgame network and inventory APIs;
no engine C++ change was necessary.

```sh
godot --headless --path game --script res://tests/run_all.gd
```

The suite includes `test_vendor.gd` with capacity-rollback,
replay-rejection and location-authority regressions. The dedicated
`albion-after-vendor.yml` CI also runs the complete test suite.

## Selling refined crafting materials

The existing authoritative hub vendor also buys player-refined **planks,
metal bars and cloth** at tier-scaled prices. Refining two raw materials
therefore adds a small silver premium, connecting gathering, professions and
the settlement economy without duplicating server market systems.

`Vendor.first_sellable(inventory)` chooses a carried refined material first,
then falls back to raw salvage. The local preview `V` key and a new inventory
panel button use this helper. The same server-side `cmd_vendor` validates
each transaction; Nakama persistence and safe-bank rules remain unchanged.
The existing `test_vendor.gd` suite also covers refined-goods payouts.


## Equipment-granted active combat skill

In `game/`, press **G** with any crafted club equipped for a server-driven
**Heavy Strike**. It deals **1.6×** club damage within **2.8 metres**, uses
**30 combat energy** and has a **6-second** cooldown. Energy regenerates at
**9 per second** while alive (max 100); respawn restores energy and clears
combat timers. The live HUD shows energy, cooldown and weapon.

The local preview calls `GameServer.cmd_skill`; the dedicated transport
exposes the same move through `Net.c_skill`. Only aim direction comes from
the client. Weapon ownership, damage, energy, cooldown and protected-hub PvP
rules are enforced by the server. These are game-specific mechanics, so no
native engine modification was necessary.

Regression tests are in `game/tests/test_weapon_skills.gd` and run with
`godot --headless --path game --script res://tests/run_all.gd`.

## Defensive construction in the canonical game

The shared GameServer owns player-built barricades. Outside the Haven safe hub,
survivors can build up to 12 wooden/stone barricades by spending **4 wood T1
and 2 stone T1**. Placement requests include a position, but the server
validates real player range, water depth, terrain slope, existing world geometry,
other players and enemies, and material stacks before spending anything.

The shared WorldGen movement blocker index immediately prevents survivors and
infected from walking through a structure, including in the local playable
preview. The preview renders a `StaticBody3D` and a box collision shape at each
structure; the server's **authoritative gameplay collision** is a lightweight
circular blocker and does not claim to be full mesh/rigid-body simulation.
Infected who get stuck while chasing survivors gradually damage a nearby wall.

Owner-only repairs restore up to 40 of 120 durability for 1 wood T1; full-health
repairs and invalid attempts are free. Destroyed barriers disappear from
movement collision and proximity-filtered network snapshots. The server
exposes rate-limited `c_build` and `c_repair` requests, and the client can
replicate the same visual wall/HP state. The world imposes a 300-wall cap for
this experimental gameplay slice.

**Scope:** barricades currently survive only while the server/session is
running. They are not included in Nakama character saves, and do not yet have
guild ownership, decay, mesh damage, server-sharded persistence, or siege tools.
These are planned for a future unified world-building milestone.

To run all game tests, including terrain collision, resources, construction,
repairs, enemy impacts, and save compatibility:

```sh
godot --headless --path game --script res://tests/run_all.gd
```

CI: `.github/workflows/game-barricades.yml`. Cgame-native full-engine
testing is still required after any upstream physics API changes.




## Reclaiming and rebuilding a safe outpost

The server supports **owner-only dismantling** of a nearby barricade: press **X**
while facing a wall within 3 metres in the local preview, or use the
"Dismantle nearby barricade" button inside the online client's inventory.
An intact or mostly intact structure returns 2 wood T1 + 1 stone T1;
a severely damaged wall returns 1 wood T1. You can never recover the full
original construction cost, so repeated build/salvage cannot create materials.

`GameServer.cmd_dismantle` checks that the survivor is alive, owns the wall
and is physically near it, then simulates the entire refund in a copy of their
backpack. If even one recovered item cannot fit, **nothing changes**. On success,
the wall and its movement blocker are removed together; network snapshots
stop exposing it, and the inventory is marked for server persistence.

Authenticated account ownership is now independent of ephemeral network peer
IDs for *new* barricades: reconnecting to the same account restores repair and
dismantle permissions, and a different account cannot hijack an old peer ID.
Guest walls remain peer/session-owned. Account identities are never included in
public structure snapshots. This does not yet make barricades durable across
world-server restarts; server-side world persistence is a separate milestone.

Tests: `game/tests/test_dismantle.gd` in the existing headless suite.

## Chat and guilds (online client)

Press Enter to talk in the world room. `/guild Name` founds a guild, `/guilds` lists them, `/join Name` joins,
`/g text` talks to your guild only, `/leave` leaves. All of it is Nakama (rooms, groups, group channels).


## Coordinated infected and last-known-position search

AI in the canonical `game/` now shares an acquired target between infected
within 18 metres in the authoritative server simulation. The server uses
small spatial buckets and spreads only from enemies already chasing or
attacking; this avoids unbounded instant alert chains. Safe-zone players,
dead players, and survivors outside each zombie's pursuit leash cannot be
recruited as targets.

When a survivor escapes that leash, the pursuer investigates the last
tracked position for up to four seconds before abandoning the search and
returning home. This is implemented in the game state machine and requires
no new Cgame engine APIs or network commands.

The game tests include `test_zombie_pack.gd` and expanded
`test_zombie_ai.gd` regression checks. Run them with
`godot --headless --path game --script res://tests/run_all.gd`.

## Server-authoritative camp contracts (scavenging + sandbox professions + PvE)

The same multiplayer game in `game/` now includes three finite original
survivor missions at the hub **workbench** (x=9, z=0). They connect the
Days After scavenging / infected loop with Albion-like tiered gathering,
classless crafting and in-world silver rewards.

| Order | Mission | Objective | Reward |
| --- | --- | --- | --- |
| 1 | Supply the camp | Hand in 4 wood T1 and 3 fiber T1 | 12 silver and 1 bandage |
| 2 | Arm the survivors | Own one crafted T1 club (not consumed) | 18 silver and 1 water bottle |
| 3 | Clear the infected | Kill two infected **after** accepting the patrol | 35 silver and 2 canned foods |

In the **local playable** client, press **M** to accept the next mission,
**Shift+M** to turn it in, while near the hub. In the **online network
client**, open the **I** inventory panel and use **Accept next mission**
or **Turn in mission**. The current objective appears in the interface.

The client never sends a reward amount, objective progress or completed
mission ID. Every decision is made by the authoritative `GameServer`.
The server confirms the character is alive and at the hub, validates
inventory/kill conditions, and simulates every reward transfer on a copy
before committing it. Missing resources or a full backpack cannot produce
partial payment or free items. Completed missions cannot be claimed again.

The journal (`active`, `progress`, `completed`) is included in the existing
version-1 Nakama character save, synchronized in the owner's private
snapshot and validated **before** loading a character. Older saves without
the journal remain loadable with an empty one. A character's account
progress survives ordinary combat death, while red/black-zone loot follows
the existing PvP/full-loot rules.

```sh
godot --headless --path game --script res://tests/run_all.gd
```

The `test_contracts.gd` suite checks server-only authority, fixed rewards,
no item duplication, weapon crafting, unique infected kill counts,
all-or-nothing inventory transfers and old / malformed saved characters.

This is a **first NPC quest chain**, not a procedural quest generator,
guild mission board, live events or multiplayer marketplace. No missing
generic Cgame engine primitive was identified; reusable networking,
inventory, movement and persistence APIs already provide the foundation.

## Durable server-authoritative barricades

The canonical dedicated server now checkpoints **authenticated-account
barricades** between restarts. Owner IDs are kept in the server-only world
checkpoint and are *not sent to clients*. On reconnect, the same authenticated
account can repair or dismantle its structures using its new network peer ID;
a recycled guest peer ID cannot claim someone else's walls. Guest/anonymous
barricades remain session-only until they have a stable account identity.

By default, the dedicated server loads a seed-specific file such as
`user://albion_after_world_1337.json`. Changes are saved every 45 seconds
and on graceful `--quit-after` shutdown. A bad file refuses server startup:
schema, world seed, account IDs, health, stable IDs, placement collision,
protected areas, terrain slope, overlap and ownership caps are validated
**before** any collision blocker is installed. Saves use a temporary file
and rename, rather than truncating an existing valid checkpoint.

Use an explicit save file or disable persistence for disposable tests:

```bash
godot --headless --path game --script res://scripts/server/server_main.gd -- --seed 1337 --world-save user://my_world.json
godot --headless --path game --script res://scripts/server/server_main.gd -- --no-world-save --quit-after 3
```

`test_world_persistence.gd` checks durable walls, owner reconnect,
collision, rejection of damaged and foreign-seed saves, session-only guest
walls and defense against recycled connection IDs. This is not yet a
multi-shard world database: crash recovery is limited to the last successful
autosave, and account-based ownership requires an authenticated identity.

### Checkpoint backups and operator recovery

Each **second or later** successful checkpoint save now keeps the previous
complete snapshot in a sibling `.bak` file, while the new checkpoint is
written through a temporary file and renamed. The first save has no backup.
Invalid existing JSON or a snapshot belonging to another seed is **not
overwritten** during backup rotation. Save failures leave the server world
marked dirty for a later retry and are reported on graceful shutdown.

The dedicated server **never automatically loads the backup**. Falling back
silently could resurrect a dismantled barricade and duplicate salvaged
materials. If the primary file becomes corrupted, stop the server, preserve
both files, investigate, then deliberately copy the verified backup over
the primary world file before restarting. Any changes since that backup will
be lost. Keep independent offsite backups for valuable worlds.

The `--world-save` path is normalized and must remain inside Cgame's
`user://` data directory; paths that escape using `../` are refused.
Nested directories under `user://` are created when saving. This is not a
substitute for filesystem permissions or protection against attacker-controlled
symbolic links on the host.

Run `game/tests/test_world_backup.gd` through
`godot --headless --path game --script res://tests/run_all.gd` to check disk
rotation, manual recovery, invalid primary handling and path confinement.


## Ruin recovery: fourth outpost contract

Complete the existing three camp missions to unlock a **two-cache ruins
expedition**. Opening distinct, reachable ruin supply crates advances the
objective on the server. Repeated requests, loot bags, and refilling the
same cache do not advance the mission again. The character's visited crate
IDs are saved, and legacy version-1 accounts with the previous three-field
contract journal remain compatible. At the safe hub board, claim **60 silver
and 10 rounds of 9mm ammunition**. The common `run_all.gd` suite now runs
`test_contracts.gd` and covers quest progress, replay, persistence and
validation. This is game logic and needs no Cgame engine API changes.

## Tactical radar in the canonical game

Press **M** to toggle the player-following, north-up 72-metre radar in the
local survival preview or the network client's HUD. The player arrow points
where the survivor is facing. Red = live infected, yellow = undepleted
resource nodes, green = unopened crates/dropped bags, ochre = player-built
barricades and blue = the safe settlement. All markers use world generation
plus the current authoritative server simulation (local) or server snapshots
(online); the radar never simulates enemies or generates loot. The shared
`scripts/client/survival_radar.gd` supplies both displays.

Projection and live state tests are included in `tests/test_survival_radar.gd`
under the standard headless regression runner. Full visual verification
still requires an engine/editor playtest.

## Voxel base building (opt-in engine module)

Destructible terrain and base building will use Zylann's Godot Voxel. It is not part of the default engine build:
`misc/third_party/fetch_voxel_module.sh` fetches it and `custom_modules=out/custom_modules` builds it in.
Verified here: it compiles on this fork unchanged and its classes register. No game feature uses it yet.


## Zombie infection and field medicine (canonical game)

Real infected melee strikes add server-authoritative infection severity:
walker +8, runner +12, brute +20. Untreated wounds progress by
0.065 severity/second, max 100; severity above 30 reduces health over time
(up to 1.4 HP/s). Death/respawn clears infection.

- **Field Antiseptic**: craft from 1 bandage + 1 cloth T1 + 1 clean water
  bottle (no workbench required); heals 8 HP and reduces infection by 40.
- **Antibiotics**: rare loot from ruin crates, more likely in red/black zones.
  One dose clears up to 100 infection severity.
- **6** uses an antiseptic kit, **7** uses antibiotics in the local preview.
  Medicine is not consumed when it could neither heal nor treat the player.
- The authoritative server decides all zombie exposures and treatments,
  publishes infection in snapshots, and persists it in character saves.
  Older version-1 character saves without infection load healthy; invalid
  severity, nonfinite numbers and corrupt types are rejected atomically.
- The playable HUD and multiplayer HUD show the infection state.

This uses existing Cgame scripting, inventory and networking APIs; no
native engine change was required. Regression tests in
`game/tests/test_infection.gd` run with
`godot --headless --path game --script res://tests/run_all.gd`.

## Direct survivor-to-survivor barter (authoritative multiplayer)

In the networked client inventory panel, invite a nearby survivor, select an
item and quantity, click **Offer**, then both players click **Accept**.
The event shows the current trade ID, offer revision and both accept states.
Every offer change invalidates previous approvals.

Trades work only while both players are alive, in the safe hub and within
6 metres of each other. Up to four item types per participant are supported;
silver can be offered like any other inventory item. No item moves at the
proposal stage. Only after both players approve the **same revision** does the
server recheck counts and capacity, simulate both inventories independently,
and commit both transfers together. A failed check commits neither side.
Timeout (45 seconds), death, leaving the safe hub, exceeding range, cancel
or disconnect all invalidate the trade. Completed trade IDs cannot be replayed.

The rules live in `scripts/shared/player_trade.gd` and the
`GameServer.cmd_trade_*` family, exposed via `scripts/shared/net.gd`.
`tests/test_player_trade.gd` checks conservation of silver and materials,
inventory capacity rollback, stale approvals, cancellation and replay.

**Persistence limitation:** this is an authoritative *single-world-session*
exchange. Trade results become dirty character snapshots and use existing
Nakama save mechanics, but two separate character saves are **not yet one
durable database transaction**. Do not use for production cross-server markets
until a backend transactional ledger or transactional character write is added.
No Cgame engine changes were needed; the current networking API supports
these commands and reliable events.

## Shared day/night cycle and night infected threat

The canonical network client already displayed a 900-second lighting cycle,
but its clock was duplicated and the offline playable client never changed
lighting. `game/scripts/shared/world_cycle.gd` now defines the same
sunrise-to-sunrise period for the **dedicated server and both clients**.
The offline demo varies directional and ambient light and sky color using
that shared clock; the online client keeps the same established sky and fog
behavior but reads the shared time calculations. Both HUDs identify day/night.
At night, the authoritative server increases an infected's **visual notice
radius by 35%**, capped by its existing pursuit range. Existing noise detection,
safe-hub immunity, attack damage and chase speed are unchanged. No client
request can forge the world time or night detection multiplier. The cycle
uses server elapsed time; it restarts with the game server rather than being
persisted as a calendar. Run the full suite, which includes
`game/tests/test_world_cycle.gd` (clock boundaries, detection, safe hub,
network snapshots).


## Server-authoritative dodge / sidestep (Space)

**Space** performs a short 2.56 m tactical dodge in the movement direction,
or facing direction when standing still. This is implemented in the canonical
`game/` simulation, not in the separate `demo/` prototypes.

- Costs **24 stamina**, has a **3-second** cooldown and shares a short
  0.32-second lock with normal attacks.
- Grants **0.30 seconds of protection against infected melee wounds**,
  including associated infection; it does **not** prevent PvP damage.
- A valid dodge interrupts gathering and makes footstep noise that may
  alert infected. It is unavailable while overencumbered, severely hungry,
  dehydrated, exhausted or dead.
- The server owns direction validation, travel distance, stamina, cooldown,
  collision checks and protection. The client supplies only a direction.
  Four 0.08-second collision steps reuse `Movement.move`; barricades,
  terrain obstacles and deep water stop the motion, without charging
  stamina when completely blocked.
- The local scene uses `GameServer.cmd_dodge`; online clients use
  `Net.c_dodge` and normal authoritative position reconciliation.
  Owner snapshots include `dodge_cooldown` and `dodge_immunity`.
  The local and multiplayer HUDs display the cooldown.

Run `godot --headless --path game --script res://tests/run_all.gd`
to exercise `test_evasion.gd` alongside combat, movement, encumbrance,
PvP-risk, zombie infection and save regressions.

All mechanics use existing Cgame movement and networking capabilities.
A native engine change is unnecessary until a reusable engine limitation
is demonstrated.

## Server-authoritative weather and cold exposure

The combined survival/sandbox game now has deterministic regional weather
computed from the **world seed**, 256-metre climate cells and dedicated-server
time. Conditions change every four in-game minutes, with local storms,
biome-dependent temperature and the safe settlement acting as a sheltered
refuge. Storms in cold environments accumulate **exposure** (0–100), which
eventually causes health damage; returning to shelter or reaching milder
weather lowers exposure. Equipped armor reduces buildup by 35%. Existing
zombie infection, hunger, thirst, stamina, combat and equipment rules remain
server-owned.

Both the local playable client and network HUD show the current weather,
temperature, shelter status and exposure. The multiplayer snapshot carries
the authoritative values rather than accepting arbitrary climate data from
players. Character saves include exposure, while older accounts load with
zero exposure. Invalid exposure in account storage rejects the entire saved
character before inventory or any other live state changes.

Regression: `godot --headless --path game --script res://tests/run_all.gd`
runs `test_weather.gd`, checking deterministic storm cycles, gear
insulation, shelter, damage, reset, server ticks, snapshot, migration and
corrupt-save rejection.

This is a gameplay weather system, not yet volumetric clouds, physically
simulated rain, wind fluid dynamics or an actual temperature field inside
buildings. Current Cgame/Godot scripts provide the required simulation API.

## Emergency heat packs (weather survival)

Survivors can handcraft a **thermal wrap** from 1 cloth T1, 2 fiber T1
and 1 wood T1. Carry it into cold mountains or storms, then use it
from the online inventory or press **8** in the local sandbox. A consumed
pack reduces weather exposure intensity by **70% for 180 seconds**.
It is not a permanent stat or class ability. The server rejects repeat use
while insulation is active (without spending an extra item), decrements the
remaining time, handles mid-tick expiration proportionally, and clears
the temporary protection on death. The timer is sent only to the owning
character's snapshot and persists in version-1 character saves with
strict finite bounds and compatibility for older saves. Server weather
and equipped armor still determine the underlying exposure intensity.
The `test_thermal_wrap.gd` regression runs with `game/tests/run_all.gd`.
This is a fictional game mechanic, not real cold-exposure advice.

## Fishing, cooking and classless gathering mastery

The canonical survival MMORPG in `game/` now supports **shore fishing** as
another independent profession alongside woodcutting, stone, ore and fiber.
This extends both the offline local preview and the authoritative network
server, not a standalone prototype.

- Craft a **Fishing Rod** at the camp workbench from 2 T1 planks and
  3 T1 fiber. Carry it in the normal inventory.
- Stand on dry ground within approximately 4 m of water, then press **T**
  in the local preview, or use **Cast fishing rod** in the online **I**
  inventory panel. The server checks shoreline, life state, the carried
  rod, free inventory capacity and the cooldown.
- A catch takes **5 seconds** without moving away. The authoritative
  server awards 1–2 raw fish, followed by a **2-second** recast cooldown.
  Interrupting a cast, losing the rod or leaving the shore awards nothing.
- Fishing awards **fishing profession XP**, independently of crafting or
  other resource-gathering skills. XP is based on the fish that actually
  entered the inventory; a full pack grants no phantom XP.
- Cook **1 raw fish + 1 T1 wood** at the camp workbench to make
  **1 cooked fish** restoring 35 hunger. Raw fish is a material, not
  immediately edible; cooking uses the existing authoritative crafting
  and item-consumption systems.
- Progression persists through ordinary character saves, including Nakama.
  Previous version-1 characters with only four gathering professions are
  loaded with fishing XP = 0; malformed or infinite XP values are rejected.
- Fishing, casting and cooking do not accept client-provided fish amounts,
  paid currency, elapsed times or XP.

Run the canonical smoke suite:

```sh
godot --headless --path game --script res://tests/run_all.gd
```

`test_fishing.gd` covers generated-shore water access, crafting, delayed
reward, anti-spam cooldowns, casting interruption, inventory capacity,
food recovery and backward-compatible progression saves.

**Not included yet:** multiplayer fishing parties, boats, fish shoals,
bait, weather-dependent catches, T2–T4 rods or regional fish prices.
These can be added through shared game rules without duplicating an engine.


## Fishing end-to-end networking and gameplay regression

Fishing is an actual interaction in `game/`: **T** in the local playable
client, or **Cast fishing rod** from the network inventory panel. The server
owns the shore proximity, fishing rod, five-second cast, movement cancellation,
two-second cooldown, 1–2 fish catch, inventory limits and fishing profession XP.

The authoritative `fished` completion event now passes the network filter
**only to the player who performed the cast**. Other players are not sent the
catch notification. Cooking raw fish uses the existing workbench recipe.

Run `godot --headless --path game --script res://tests/run_all.gd` to
exercise `test_fishing.gd`, plus
`godot --headless --path game --script res://tests/smoke_client_scene.gd`
to check that local fishing is accessible via the actual playable scene.

## Full semantic validation before world backup rotation

A parseable JSON checkpoint is not necessarily a recoverable world. The
server now checks a previous primary snapshot against fresh procedural
terrain before copying it into `.bak`: account ownership, wall IDs,
collision-free placement, durability, world seed and owner limits must all
validate. Captured current-world state is checked the same way **before**
writing it. Active in-memory walls are excluded from validation by using
a fresh world generator, avoiding false overlap failures.

Corrupt files still fail closed; the server does **not** silently load an
older backup, which could resurrect structures already dismantled and
refunded. Regression scenarios are in `game/tests/test_world_backup.gd`.

## Online player market (server-authoritative prototype)

The shared hub now has an **online sale listing board** alongside direct player
barter and the NPC vendor. Open the inventory panel, select an item in the barter
item selector, choose the listing quantity and silver price, then click
**List item**. Use **Refresh** to browse, **Buy** to purchase selected stock
or **Cancel mine** to remove your own advert. The buyer and seller must both
be alive and at the hub workbench. A listing expires after 30 minutes, when
the seller leaves the hub, disconnects, dies or no longer has the promised stock.

Posting a listing does **not** remove or reserve goods. At purchase time the
authoritative server rechecks the seller's inventory, buyer's silver, both
capacities, listing ownership and remaining quantity. Goods and silver move
atomically within the simulation, with partial purchases supported. Failed
settlements change neither backpack, and filled listings are removed so an
old request cannot be replayed. Maximum: 4 listings per seller, 80 global,
40 units per listing and 2,000 silver per item. Only online players can sell.

**Not a persistent auction house yet.** Active listings and the bounded
session receipts are in RAM. Crash/restart clears adverts, but does not
strand escrow because nothing was pre-debited. A successful purchase marks
both character states dirty for existing Nakama saves; those two saves are
not one database transaction. For persistent offline orders, add backend
escrow, atomic settlement across accounts and a crash-recovery journal
before enabling them in production.

The core tests live in `tests/test_market_board.gd`, included in
`tests/run_all.gd`. Existing Cgame/Godot networking supports the feature,
so it requires no native engine modifications.

## Night infected sieges against player defenses

While a survivor is **outside the safe Haven settlement** and remains within
26 meters of a player-built barricade, the authoritative game simulation
may start a small infected siege **at night**. The threat grows with the tier
of the defended barricade: T1 starts with two walkers, rising to a bounded
five-enemy mixed wave at T4 (walkers, runners and a brute).

Waves spawn only on traversable, dry ground **10–28 meters from the active
survivor**, outside the protected hub and away from existing terrain or
structure collision. They enter the established server-owned chase AI, where
obstacles stop their movement and infected chip away at barricades. The world
sends a nearby-player warning; the connected HUD displays it.

The scheduler permits at most one wave per check, imposes a **45-second
global interval**, a **180-second per-wall interval**, and refuses spawns once
the live world has **90 active infected**. Distant, dead or safe-zone players
cannot trigger a wave, and the server removes wall cooldowns when a structure
is dismantled or destroyed. Players cannot invoke waves via an RPC.

Waves are live-world events, not a persisted loot farm or a new dungeon
instance. Barricades, durability and tier remain in the existing persistent
world checkpoint; temporary raid timers and spawned infected do not.

The server rule regression `game/tests/test_base_sieges.gd` checks daytime
safety, valid placement, server-owned target pursuit, cooldowns, T4 wave
limits, the global population cap and deletion of destroyed bases. No
engine changes were necessary: Cgame's collision and enemy simulation already
support this gameplay logic.

## Upgradable bases: four defensive tiers

The canonical `game/` server now upgrades existing barricades **T1 → T4**
rather than spawning a separate second game. Owner-only upgrades within 3 m
consume server-defined items crafted or gathered through the existing economy.

| Upgrade | Cost | Maximum health | Incoming damage |
| --- | --- | ---: | ---: |
| T1 initial | 4 wood T1, 2 stone T1 | 120 | 100% |
| T2 | 4 planks T2, 2 stone T2 | 240 | 82% |
| T3 | 4 planks T3, 3 metal bars T3 | 400 | 66% |
| T4 | 6 planks T4, 4 metal bars T4 | 600 | 50% |

Upgrading keeps the current **health percentage**; it cannot bypass repair
costs. Repairs require 1 wood T1, plank T2, metal bar T3 or metal bar T4
respectively, restoring 40/60/85/110 HP up to the tier cap. Zombies use the
same server-side damage multipliers.

**Local preview controls:** U builds, H repairs, **Y upgrades**, X dismantles.
The connected client uses U/H/Y/X with server-validated RPCs. The online
HUD identifies the nearby wall tier, durability and next upgrade cost.
Visual colors move from reclaimed timber through stone and reinforced metal
to hardened alloy, based on values replicated by the authoritative server.

New saves include a `tier` field in each world checkpoint. Old checkpoints
without that field still load as T1 with their old HP, without changing the
world schema version. Values outside T1–T4, fractional tiers and HP higher
than the chosen tier permits are rejected. Account ownership, original
structure IDs and collision footprints remain unchanged. Demolition returns
only the original T1 salvage, never the expensive T2–T4 materials.

The server test suite includes `test_structure_tiers.gd`: resource cost and
failure atomicity, damaged upgrades, repairs, owner/range access, damage,
replication, saved-world roundtrip and old-save migration. No C++ engine
extension is needed; existing Cgame gameplay, physics and serialization
primitives support this feature.


## River and lake water safety

Survivors can drink from **actual nearby lake shores**, but untreated water
restores 35 thirst and adds 8 fictional infection points. A crafted **Field
Water Filter** (one cloth T1, one wood T1, one stone T1) is automatically
consumed when drinking from a lake and prevents that exposure. Drinking
has a **12-second server-enforced cooldown**; being fully hydrated, far from
water or in cooldown rejects the action without spending filters. Clean
bottled water remains available via existing trading and crafting economy.
The server persists the cooldown so reconnecting cannot spam hydration,
validates restored timers before mutating the account and accepts older
version-1 save files. The owner receives the remaining cooldown in the
network snapshot, and the online HUD reports whether a lake drink was
filtered. In the offline game use **R** at a shoreline.

Run the common suite including `test_field_water.gd` to check shore
validation, dose, filter spending, server cooldown, atomic crafting,
serialization and save corruption. The contamination model is a fictional
risk/reward mechanic, not medical or water-safety advice.


## Classless weapon mastery (melee / ranged)

Victories against infected now build *equipment-family* expertise in the
canonical `game/` project, alongside existing gathering, crafting and fishing
professions. This is a persistent progression feature, not a character class.

- A confirmed infected kill with an **owned and equipped club** grants melee XP;
  a kill with an **owned and equipped pistol** grants ranged XP.
- Walker, runner and brute XP values come from the server's existing infected
  definitions (5 / 8 / 25). Missed attacks, nonlethal hits, corpses, and unarmed
  kills do **not** grant mastery XP.
- Each family starts at **level 1**. Every **80 XP** unlocks another level,
  capped at **level 5**. Each level above 1 adds **3% damage**, up to **+12%**,
  including the equipped club's special Heavy Strike.
- The server decides the kill, weapon ownership, awarded experience and damage
  multiplier; clients cannot submit mastery XP or damage. PvP kills currently
  award **no mastery XP**, avoiding easy farming with colluding players.
- Combat XP is saved with existing character progression, is retained through
  full-loot deaths, and is present in owner snapshots and both game HUDs.
  Older character saves without a `combat` subtree migrate to zero XP; malformed,
  fractional, negative, nonfinite or foreign mastery entries reject the entire
  load before touching live state.

Run `godot --headless --path game --script res://tests/run_all.gd` and inspect
`game/tests/test_combat_mastery.gd` for server hit, kill, damage, save and
anti-exploit regression coverage.

No Cgame native engine change was needed; this extends the existing
server-authoritative game progression and combat APIs.

## Temporary field campfires for hostile weather

Place a temporary **field campfire** outside the protected settlement using
**O** in the local or online game, or the online **I** inventory-menu button.
Each fire costs 3 T1 wood + 1 T1 stone, burns for 300 seconds, and warms all
survivors within a 5-metre radius. The authoritative server validates dry,
non-steep terrain, range, proximity to obstacles, fuel, and ownership limits
(2 active fires per player, 96 per world). Invalid placements cost nothing.

Proximity to an active fire makes weather exposure decay, without healing
existing injuries or curing infection. Existing hunger, thirst, infection,
combat, PvP and weather systems remain active. Flames are visible to nearby
players through interest-filtered server snapshots; IDs and positions come
from the server, not clients. Campfires are **session-only** and intentionally
not part of durable account-owned barricade checkpoints.

The regression suite includes `tests/test_field_campfire.gd` for fuel,
placement validation, shared warmth, snapshot privacy, and expiry. No native
Cgame API changes were required for this vertical slice.


### Regional fishing and coastal economy: T1–T4

The same multiplayer game now extends shore fishing into the zone-tier,
gear-tier and profession-tier economy:

- T1 rod and fish remain supported exactly as before. T2–T4 fishing rods
  require matching-tier planks, cloth and metal bars at the workbench,
  and the existing classless crafting level gates the recipes.
- The server chooses the catch tier using **the minimum** of the region's
  zone tier (green T1, yellow T2, red T3, black T4), the carried fishing
  rod's tier and the survivor's permanent fishing skill tier. A player
  cannot request a higher-tier fish or forge a catch in a client RPC.
- The server fixes the catch item/tier at the start of a 5-second cast
  and checks the position, rod, region, backpack capacity and fishing
  mastery again before delivering 1–2 fish. Moving away or losing
  eligibility aborts the cast without creating an item or XP.
- Tier 2–4 raw coastal fish are distinct inventory/market goods.
  Cooking one fish with matching-tier wood at the workbench produces
  cooked fish restoring progressively more hunger.
- The safe-hub NPC buys T1–T4 raw fish at 4, 8, 14 and 22 silver
  respectively, while the online player market can list them at
  player-chosen prices. The price difference rewards risk and
  professions without allowing vendor purchase/resale arbitrage.
- The existing **T** cast key in local play and online inventory cast
  button continue to work. The network HUD now reports the actual
  tier and item name of each successful catch.

`game/tests/test_fishing_tiers.gd` is registered in the main
headless suite and covers all four zone/rod/mastery limits, inventory
capacity, tiered rod crafting, cooking and server-atomic sales.

No general Cgame engine feature was missing for this step: the shared
game data, authoritative simulation, client networking and tiered
inventory/crafting APIs already provide the required primitives.

### Exactly-once processing of market buy requests (within one server session)

Every network purchase now carries a strictly increasing, per-client request
ID. The server records the last ID, listing ID, quantity and result for each
connected peer. Repeating an identical request returns its *original* result
and receipt without transferring items a second time; reusing the ID with
different parameters is rejected, as are older or invalid IDs. This also
protects partially filled listings, for which a duplicate purchase was
previously possible. The per-peer record is cleared at disconnect and
does not grow with the number of purchases.

**Scope:** this is session-level RPC idempotency, not durable settlement.
A new higher ID is an intentionally new purchase. Server crashes can still
lose unsaved balances; durable cross-account transaction storage in Nakama
remains necessary for an offline auction house and crash-safe markets.

## Shared campfire refueling

Temporary wilderness campfires (already part of the main world simulation)
can now be **refueled cooperatively**. Any living survivor standing within
3.2 metres can spend **2 T1 wood** to add **120 seconds** of warmth for
everyone nearby. The total remaining burn time is capped at **600 seconds**;
a refill is rejected rather than consuming wood if a full 120-second
extension would exceed that cap. Expired fires cannot be restarted by
refueling and must be rebuilt using the normal campfire recipe.

The authority is entirely in `GameServer.cmd_refuel_campfire`: actual
distance, survival status, authoritative inventory, current deadline,
and fuel limit are all checked before changing either items or burn time.
This does **not** create a PvP-safe zone, checkpointed structure or new
instance of an existing fire.

Controls: **9** while standing near a burning campfire in either local or
multiplayer play; the online inventory also contains a **Refuel Campfire**
button. A refueled fire's remaining lifetime is replicated to nearby peers.
Tests in `test_field_campfire.gd` cover resource conservation, shared
contributions, denial of remote/unknown/expired attempts, duration caps
and replication. This uses the existing Cgame inventory, network and
rendering APIs; no engine source change is necessary.


## Scavenging profession: dangerous ruins and valuable salvage

The canonical `game/` survival world now includes a permanent **Scavenging**
profession alongside gathering, fishing, crafting and weapon mastery:

- Searching a **real, nearby, unopened ruin crate** awards 15 / 20 / 30 / 45 XP
  in the green / yellow / red / black territories respectively. Risky zones
  reward more exploration, but red/black zones retain their full-loot PvP risks.
- Every **75 XP** increases scavenging level, up to level **5**. From level 2,
  a red/black crate awards extra ordinary scrap (+1 to +4 depending on rank).
  Medicine, rare weapons and other RNG drops are **not** multiplied.
- The server determines crate proximity, depleted state, zone, deterministic
  base drops, bonus scrap and earned XP. A crate can reward exploration only
  once until it respawns. Searching corpse bags or missed/duplicate crates
  does not award XP. Overflow loot still goes to the normal ground bag.
- XP persists across logouts and full-loot deaths, and appears in the local
  and multiplayer HUDs with the owner's current rank. Old characters without
  scavenging XP load as novices; invalid or nonfinite XP is rejected before any
  saved character state is changed.
- Implemented in `scripts/shared/scavenging.gd`, authoritative
  `scripts/server/game_server.gd` and persistent
  `scripts/shared/progression.gd`. No new engine primitive was required.

Run `godot --headless --path game --script res://tests/run_all.gd` to
execute `tests/test_scavenging.gd` along with the existing server suites.

## Extinguishing a field campfire

A survivor can now extinguish a **fire they own** by pressing **-** near it,
or by choosing **Extinguish my nearby campfire** from the online inventory.
The command is validated by the dedicated server: the fire must still be
burning, the owner must be alive and within 3.2 metres, and account ownership
must match. Authenticated owners retain this permission after reconnecting
with a different network peer ID; another account reusing that peer ID cannot
steal it. Guests may manage their fires in the same session.

Extinguishing removes the shared warmth immediately and frees the temporary
campfire slot. It **does not refund fuel**, making repeated build/extinguish
cycles a resource sink rather than a duplication strategy. Owner account IDs
remain server-only and are never replicated to nearby players. A separate
`tests/test_campfire_extinguish.gd` suite covers authorization, distance,
reconnect ownership, no refunds and replay resistance. No engine C++ change
was necessary for these game rules.


## Quick-cooking fish in field expeditions

Press **0** (zero) in either the local or connected game to quick-cook the
highest-tier meal for which the survivor has **fish, matching-tier wood and
crafting mastery**. The online inventory panel also has a quick-cook button,
so players need not search the full workbench recipe list after fishing.

Recipe choice is shared client-side logic only. The ordinary server command
still rejects cooking without a live campfire within range or the permanent
hub workbench. Higher-tier crafting restrictions, ingredient costs, failure
atomicity and granted experience are unchanged. Other workbench-only recipes
can never be chosen by this shortcut.

`game/tests/test_quick_cooking.gd` checks tier priority, lower-tier
fallback, skill prerequisites, lack of side effects and station validation.
No Cgame engine additions or network protocol changes are required.

## Versioned Nakama character saves and atomic pair storage

The authoritative Nakama Lua module now uses optimistic storage versions.
`character_load` supplies a version (`*` for an uncreated document); all
`character_save` calls require that version and return the replacement one.
The Godot `NakamaGateway` caches these versions, so an outdated autosave
cannot silently overwrite a newer document after a reconnect or conflict.
On version conflict, the save fails closed; do **not** silently retry using
the new storage version with the old character snapshot.

A new server-key-only `character_pair_save` RPC commits **two existing
character documents plus one immutable transaction receipt** in a single
conditional Nakama storage write. The receipt rejects reuse of a transaction
ID with different character contents and permits querying a committed
operation after an ambiguous response. Character versions protect against
overwriting another writer's updates. Neither the character documents nor
the receipt are partly committed if the conditional batch is rejected.

**Important integration boundary:** this is the durable backend primitive,
not yet wired to live player barter or market purchases. The current world
simulation applies trades synchronously and persists its characters later.
Using this RPC for those trades requires a server-side freeze/transaction
coordinator that locks both characters against movement-related deaths,
inventory mutations, autosaves and disconnects while the async Nakama
response is pending. Until that coordination is added and tested, live
market/barter exchanges still have the documented crash window.

Run `godot --headless --path game --script res://tests/test_nakama_backend.gd`
with Nakama running via `game/backend/docker-compose.yml`. Integration tests
cover stale saves, dual-account settlement, idempotent receipts, tampered
transaction IDs, old versions rejecting the entire batch, and the server-key
permission boundary. The `albion-after-nakama.yml` workflow runs them.


## Cooperative survivor parties: group PvE and weapon mastery

The canonical online game in `game/` now supports **temporary server-owned
survivor parties** for Lineage-style cooperative adventuring without abandoning
Days After survival risks or Albion-style classless gear progression.

- Any living survivor can invite another living player within **16 metres**.
  The first invite creates the group; accepting joins it. Parties hold at
  most **5** members. Invitations expire after **30 seconds** and cannot be
  accepted at a distance, faked, or replayed. Only the leader can invite
  additional members or kick anyone; leadership transfers when they leave.
  Disconnects remove members and pending invitations.
- Open the online **I** inventory panel to select a nearby survivor, **Invite**,
  **Join**, **Decline**, **Leave**, or (leader-only) **Kick**. The private party
  roster shows participant names, health and who leads; invite prompts
  appear only to the invited player.
- **Friendly fire is disabled between members of the same party**, even in
  dangerous PvP zones. Unaffiliated players still follow existing zone rules.
- The **killing blow** awards its normal weapon mastery XP and kill/contract
  progress to the actual killer. Eligible party members within **28 metres**
  of that infected can earn **50% assist mastery XP** only if they actually
  landed a server-validated, armed hit on that same infected within the
  last **20 seconds**, are alive, and still carry the weapon used.
  Simply staying nearby or joining a group without fighting grants nothing.
- No loot, currency or contract progress is duplicated or automatically
  granted to party members. The existing world loot bags remain accessible
  according to current game rules. Parties are **session-local** and do not
  pretend to be permanent guilds or persistent clans.
- All party mutations come through rate-limited authenticated server RPCs.
  Client data contains only intended recipients for invitations/removals;
  no client may set the leader, membership list or granted XP.

The headless regression suite includes `game/tests/test_party.gd` covering
party capacity, leader handoff, expired and replayed invitations,
network roster privacy, friendly fire, assist contribution requirements,
nonparticipant/stale-damage XP rejection, and safe cleanup.

```sh
godot --headless --path game --script res://tests/run_all.gd
```

Future Lineage-inspired steps can build **clans, raid encounters, party-wide
quests and territory sieges** atop these authoritative group primitives.
Any missing general-purpose engine capability will be added and tested in
Cgame rather than reimplemented privately for a single game.


### Party combat safety: targeting and XP caps

The canonical online game treats members of the same survivor party as
non-targetable in PvP aiming: a friendly player standing between a survivor
and an infected enemy does not intercept a melee or ranged attack. The same
friendly-fire prohibition remains enforced in the final damage handler.

On a real infected kill, actual recent contributors in the party receive
limited weapon-mastery assist XP (50% of the infected's normal XP, capped at
100 per kill), only while alive, in range and in the same risk zone.
A dead infected, AFK bystander, former member, absent equipment or stale
contribution cannot generate shared XP.

`tests/test_party_combat_safety.gd` exercises live server attacks,
roster changes, PvP hit selection, XP limits and exploit rejections.
This is cooperative PvE progression, not an automated loot distribution
or guild/clan replacement.

## Party rally beacon (group coordination)

A formed expedition party can mark a temporary **rally point** using
**Set rally** in the online **I** inventory menu. Only its leader can place
a marker, and the position comes from the leader's actual server-side
character coordinates — there is no client-supplied map position to forge.
The party sees the shared blue 3D waypoint plus its X/Z coordinates and
remaining lifetime. It lasts 45 seconds and can be refreshed only once
per 12 seconds. Solo players, non-leaders and outsiders cannot place or
observe group markers, even if they stand nearby. A party disband or
expiration hides the waypoint; markers do not survive server restarts.

This is separate from guild territory claims and loot rights. Existing
Godot/Cgame script and scene APIs are sufficient. Regression tests:
`game/tests/test_party_rally.gd` in the canonical headless runner.


## Elite infected encounters (MMORPG ruin champions)

Rare **elite infected** appear deterministically among ruin spawn points in
**red and black** risk zones only (approximately one in seven ruin spawns).
They have **2.5× health**, **1.4× damage** and **3× base weapon mastery XP**,
and retain existing aggro, party-assist, group threat and protection rules.
Elites are larger and gold-tinted in both clients; multiplayer snapshots
replicate an `elite` flag rather than trusting clients to label enemies.

Elite kills drop the original infected loot plus guaranteed salvage,
silver and one **Infected Core**, in an ordinary lootable world bag. Two
cores, a bandage and a water bottle can be crafted at the workbench into
**Purified Survivor Serum** (T3), which heals 16 health and treats 65
infection using the existing medical item rules. This connects cooperative
PvE hunts with the survival and player-economy loops.

`tests/test_elite_infected.gd` checks deterministic rarity, safe-zone
exclusion, stat isolation, server visibility, one-time loot rewards and
the trophy crafting recipe. It is included in the main `game/` test suite.
No native Cgame engine change is required for this game-layer feature.

### Non-overlapping survival hotkeys

**0** remains quick-cook fish in both offline and connected clients; **-**
(minus) now extinguishes the nearest owned campfire. These actions previously
shared key 0, causing ambiguous/unreachable behaviour. The inventory buttons
remain available as alternative controls.

## Group-combat XP integrity

A group assist now remembers the **server-side party ID at the time of
confirmed infected damage**, not merely at the moment the enemy dies.
Joining a party after damaging an infected or leaving and reforming a
new party cannot retroactively turn that old hit into shared weapon mastery
XP. Fresh damage while an eligible party member continues to award the
normal bounded assist XP.

The new headless `test_party_assist_integrity.gd` regression is included
in `tests/run_all.gd`. It verifies pre-invite hits, legitimate assists,
corpse replay denial, regrouping and single-loot accounting. Existing
Lineage-style invitations, rally points, contribution windows, party
friendly-fire immunity and guild systems remain unchanged.

## Contested survivor outposts (Lineage-style siege prototype)

Three seed-deterministic outposts are placed on traversable land in the
**red and black full-loot PvP zones**. In the multiplayer HUD the nearest
outpost is displayed with its world coordinates, distance, controller and
capture progress. The same public state travels in authoritative snapshots.

At least **two living members of one server-owned party** must stand within
12 metres of a flag for 30 accumulated seconds to claim it. A rival nearby
survivor contests the capture, even if not yet in a party. Rival parties can
retake the flag by driving the defenders away and capturing it themselves.
Ownership lasts for at most 15 minutes, and ends earlier if its party
disbands. Outpost ownership and capture timers are server-session data only.
There are no client RPCs for setting owners, changing progress or claiming
unearned rewards.

While a party controls an outpost, its members gain **2 additional stamina
per second** while within 18 metres, provided they are alive, sufficiently
fed and hydrated, and not in the normal stamina-recovery delay. The benefit
is capped at the normal stamina maximum and never applies remotely.
Successful captures emit one server-owned event; the list and progress are
synchronized in the existing snapshots.

This is a **party-controlled siege prototype**, not permanent Nakama guild
ownership or a persistent castle economy. Proper clan wars will require
authenticated guild membership, authority rules for scheduling sieges, and
durable territory ownership before they can be enabled. Static battle
logic is in `scripts/shared/territory_control.gd`, integrated with
`scripts/server/game_server.gd`, and regression-tested by
`tests/test_territory_control.gd` through `tests/run_all.gd`.
Existing Cgame physics, ENet and snapshot APIs are sufficient.

## On-screen cooperative party health

The multiplayer HUD now shows a **compact persistent party frame** below
the survivor's equipment readout. It displays the server-reported party
size, leader marker, teammates' current health, and whether anyone is
down. The local player is labeled separately. Players fighting a night
siege, a ruin elite or an infected pack no longer have to open their
inventory to check allies' status.

The new pure formatter in `scripts/client/party_frames.gd` uses only the
authoritative `you.party.roster` snapshot. It limits the display to five
members, truncates/sanitizes names and clamps malformed health values.
The `tests/test_party_frames.gd` regression checks leader identity,
health, death state, sanitization and empty-party behavior. No engine
modifications are required.

## Bleeding wounds and first aid

Real zombie strikes and eligible player melee hits outside protected areas can cause
persistent bleeding. Bleeding gradually clots but drains health while active;
its severity is computed only by the authoritative server. Zombies still cause
infection independently, and dodged strikes cannot wound the survivor.

Bandages and crafted field antiseptic now **stop bleeding** as well as retaining
their original healing / infection effects. A bandage is usable even at full
health if a wound is bleeding; no medicine is spent on a completely healthy
survivor. The wound severity appears in both the local HUD and networked UI,
is saved with existing version-1 character data, defaults to zero in legacy
saves, and rejects corrupt values during restore.

The implementation uses existing Cgame APIs, so this change does not need
modifications to the native engine. Run:

```bash
godot --headless --path game --script res://tests/run_all.gd
```

The `test_bleeding.gd` suite verifies bleed damage/decay, cure rules, zombie
strikes, PvP protection, persistence and invalid save rejection.

## Raid loot ownership (Lineage-style cooperative PvE)

Defeating a server-spawned raid boss creates **one shared loot bag**.
For the first **75 seconds**, pickup is reserved for the killing survivor
and surviving same-party members who actually damaged the boss within
20 seconds, remained close, and carried the weapon used in combat.
Nonparticipating spectators and other parties cannot take these rare
materials immediately. After the reservation, any nearby survivor can
collect what remains; normal zombie loot is unchanged.

The server freezes entitlement at the confirmed kill and uses trusted
account identities (or per-object guest session IDs), never client-supplied
loot ownership. A reconnecting account keeps its earned access, while a
recycled guest peer number cannot steal it. Public snapshots reveal only
bag location and remaining reservation time, not account identities.
The bag is not duplicated for each player, and repeated pickups cannot
create items. The new `tests/test_raid_loot_rights.gd` is part of the
headless suite. Existing Cgame APIs were sufficient.


## Cooperative dangerous-zone raid boss — Lineage-inspired PvE

The canonical online game in `game/` now features a **server-scheduled
mutant warlord encounter**. It builds on the existing survivor parties,
zombie AI, tank threat lists, classless weapon mastery and loot-bag economy.

- Assemble at least **two living members of the same party** within
  **20 metres** of its leader in a **red or black zone**. After the world
  has been running for 90 seconds, the dedicated scheduler can summon
  a raid boss nearby. A lone player, strangers without a party, a safe-zone
  group or distant teammates cannot trigger it.
- The server chooses an accessible spawn spot **22–30 metres** from the
  leader, away from all players, water, blocked terrain and safe-zone or
  risk-zone boundaries. Client input cannot nominate a boss ID, position,
  rewards or timer.
- Only **one raid boss** can exist at a time. It has **600 HP**, uses the
  existing brute zombie chase and threat mechanics, and retreats after
  **4 minutes** or when no survivor remains nearby. A new encounter
  requires **10 minutes since the previous spawn**.
- The boss performs a **telegraphed 5-metre area slam**. The networked
  client sees a red ground disc and a warning **2 seconds** before impact.
  Players can move outside it or dodge. The server calculates damage,
  armor mitigation, life state and protected-zone restrictions.
- Defeating it produces **exactly one shared world loot bag**, with
  silver, infected cores, high-tier metal bars and field bandages.
  The normal zombie loot and classless combat XP still apply. Party
  members receive bonus weapon mastery only after actual confirmed
  contributions, not for standing idle.
- Raid messages are distributed only to nearby observers. No reward
  duplication, client-owned boss spawns, duplicated quest progress or
  persistence of session timers is allowed.

This is an original, small cooperative world-boss encounter — **not yet**
an instanced dungeon, a scheduled global raid calendar, a persistent
guild war or a fully balanced MMO boss rotation. Those systems can grow
from the same authoritative primitives rather than creating copies
of NPC logic in `demo/`.

Run the existing test suite:

```sh
godot --headless --path game --script res://tests/run_all.gd
```

`test_raid_encounter.gd` covers safe-zone/group restrictions, 2-player
eligibility, bounded terrain-safe spawning, private announcements, attack
warning/dodge/damage, once-only shared loot and boss cooldown/expiry.
The `albion-after-raid-boss.yml` GitHub Actions workflow invokes the
same tests. Successful Godot/Cgame execution must be checked before a
production deployment. No additional C++ engine primitive was needed
for this gameplay feature.


## Party-first PvE loot and public full-loot drops

An infected kill creates a loot bag exclusively available to the **actual
server-confirmed killer and the party members present at the moment of death**
for the first 18 seconds. After that, the bag is public for the remainder of
its normal five-minute lifetime. Players who join the party after the kill
cannot retroactively gain rights to earlier bags. Loose items left over after
scavenging a crate have the same short protection for that scavenger's party.

The server validates every `cmd_loot` against the original eligibility
snapshot, including distance checks and inventory limits. Unauthorized
attempts return `reserved` without transferring or deleting items. Clients
see their own `can_loot` flag and remaining timer, but **never receive the
server's owner/party identity tokens**. Authenticated accounts can reclaim their PvE loot after reconnect, while a new guest reusing a disconnected peer ID cannot inherit an old session's rights. Online world bags are gold for eligible party
members, grey when reserved by someone else, and brown once public.

**Player-death bags in red and black zones are always public immediately.**
This feature does not weaken the full-loot PvP risk. No native engine additions
are necessary: the server owns access control, and the existing snapshot and
Godot 3D rendering APIs handle the client. Test via
`godot --headless --path game --script res://tests/run_all.gd`
(`game/tests/test_loot_rights.gd`).


## Team field medicine — server-authoritative party support

Survivors in the same squad can help injured or infected teammates without
choosing a fixed healing class. In the **online inventory/party panel**,
select a nearby member, select a medical item and press **Aid**.

- A healer and recipient must both be alive, in the same accepted party,
  within **3.2 metres horizontally** and **2.5 metres vertically**.
  Self-healing continues to use the existing personal item command.
- Aid uses **one real carried item**: bandage, field antiseptic, antibiotics
  or survivor serum. Healing/cure stats are read from the existing item
  definitions; the client cannot choose or multiply effect values.
- A successful treatment has a **five-second healer cooldown**, marks both
  accounts for saving, and sends private UI feedback to the two participants.
  Failed attempts never consume an item or start a cooldown.
- Medicine cannot revive a dead character, cannot be used remotely, and
  cannot be wasted when the target is completely healthy and uninfected.
- Cooldown is temporary session combat state and resets on respawn; HP,
  infection and inventory remain part of existing persistent character data.

The system is in `scripts/shared/party_aid.gd`,
`scripts/server/game_server.gd` and `scripts/shared/net.gd`.
The server test `tests/test_party_aid.gd` runs with the rest of the
game suite via `godot --headless --path game --script res://tests/run_all.gd`.

Existing Cgame networking, UI and gameplay APIs support the feature; no
native engine changes were necessary.

## Group first aid now stops bleeding

The existing **Party Aid** feature supports injured survivors with bandages,
field antiseptics and antibiotics at close range, using real carried items
and a server-owned cooldown. It now also treats the game's persistent
**bleeding wounds**: bandages and antiseptics can stop active bleeding even
if the teammate is at full health and has no infection. Antibiotics still
treat infection only. No-effect, cooldown, distance, unaffiliated-player
and deceased-patient attempts consume **no items**.

The server's `PartyAid.has_effect` now considers the patient's wound
severity. `GameServer.cmd_party_aid` calls the same
`Survival.stop_bleeding` action used for self-treatment and returns the
actual stopped severity to the medic and patient. The network HUD includes
bleeding treatment in feedback, while existing privacy protections remain.
`test_party_aid.gd` checks bleeding-only treatment at full health,
repeated no-effect calls, correct payment and antiseptic treating bleeding
and infection together. This uses existing Cgame medical/survival APIs.

## Raid boss phase two: enrage (Lineage-style PvE)

The group mutant warlord now enters a second server-controlled phase
at **35% health** (210 of 600 HP). It becomes crimson with an
**ENRAGED RAID BOSS** nameplate; nearby survivors receive a one-time
phase warning. Existing melee damage rises by 35%, telegraphed slams
rise from 34 to 44 base damage, and their cooldown drops from 14 to
8 seconds. The two-second danger circle, safe-zone rules, armor and
dodge immunity still apply. An already pending slam is never cancelled
or duplicated by a phase transition.

No client message can trigger enrage or modify its damage and timers.
Ordinary infected/elite stats remain unchanged. Bosses, rewards and
phase state remain session-only; the existing single shared loot bag
and participant-first loot rights continue unchanged. Test coverage:
`game/tests/test_raid_phase.gd` in the standard headless suite.
The feature uses existing Cgame scripting, networking and scene APIs.

## Resource-built outpost fortifications (survival x siege warfare)

Captured PvP outposts can now be **fortified up to tier 3** using materials
collected in the survival world. Stand within **4 metres** of your
party-owned flag and choose **Fortify controlled outpost** in the online
inventory. Any living party member may contribute resources, but the site
must be owned by the party, not expired and not currently under attack.

The server verifies ownership, current enemy presence, player coordinates
and the carried materials; clients cannot set fortification levels, prices
or owners. Exact costs are: T1 **4 wood / 3 stone**, T2 **8 wood / 6 stone**,
T3 **12 wood / 10 stone**, all tier-1 materials. Resource spending and
one-tier upgrading occur in one synchronous server operation. A failed
upgrade removes nothing and cannot change the level.

Enemy capture requires **30 seconds + 10 seconds per fortification tier**
of uncontested presence. The bonus affects only the current owner; when the
outpost is captured by another group, abandoned or expires, its
fortifications are destroyed without a material refund. The HUD displays
the fortification tier, and capture progress uses its actual duration.

Every fortification request has a monotonic per-player session ID. Duplicate
requests return their original result without spending resources again,
while stale IDs and reused IDs with changed arguments are refused.
Outpost capture and reinforcement events are visible only to players within
interest range. The logic and tests are in `outpost_fortification.gd`,
`territory_control.gd`, `game_server.gd` and
`tests/test_outpost_fortification.gd`.

This is still session-based **party** warfare, not durable guild
territory ownership. A future phase must authenticate guilds in Nakama
and persist fortification ownership transactionally before cross-server
clan sieges. No native Cgame engine changes were necessary for this stage.


## Pistol active skill: Focused Shot (classless ranged equipment ability)

Equipping an owned **pistol** grants **Focused Shot** on **G**, replacing
the club-only Heavy Strike. The real authoritative server charges **40 combat
energy and one 9mm round** per use, enforces an **8-second cooldown** and
a 0.55-second regular-attack lock, and calculates **1.75× pistol damage**
at **4 metres beyond normal pistol range**. Existing ranged weapon
mastery scales the shot, and the shot generates normal gunshot noise.

Invalid aim, insufficient energy, missing ammunition, missing weapon,
death and cooldown reject without consuming resources or issuing a shot.
Shots that miss still spend one real round and energy. The same `cmd_skill`
logic works in the local playable scene and through the online `c_skill`
RPC. Red/black PvP rules and group friendly-fire safeguards remain in force.

`game/tests/test_ranged_skills.gd` exercises real zombie damage, ammunition,
energy, noise, mastery, replay prevention, respawn and safe-hub PvP with
`godot --headless --path game --script res://tests/run_all.gd`.
Existing Cgame APIs suffice; no native engine addition was needed.


## Frontier outpost supply caches (survival + territorial MMO economy)

The canonical `game/` PvP siege outposts now hold **finite server-owned
supply caches**, connecting Lineage-style territorial control with the
Albion-style gathering economy and Days After survival loop.

- Capture an existing **red/black-zone outpost** with at least two living
  survivors in one real server party. This still requires uncontested
  presence for the usual capture period. Each new successful capture
  initializes **five shared supply parcels** at that flag.
- Any member of the controlling party can stand **within 4 metres** of
  the captured flag and use **Collect nearest captured outpost supplies**
  from the **I** inventory panel. The server checks actual position,
  current party membership, owner, expiry, and **live nearby enemies**.
  A contested outpost cannot be looted.
- Each successful parcel supplies **silver, scrap, one T3/T4 metal bar,
  and a bandage**. Red zone yields 30 silver, six scrap and one T3 bar;
  black zone yields 40 silver, eight scrap and one T4 bar.
  These items are normal inventory resources and remain subject to
  carry weight, trading, crafting and full-loot PvP rules.
- **One parcel per authenticated account per capture**. Repeated commands,
  relogging with the same Nakama identity, or changing the network peer
  number cannot create another parcel. Guests use a session-unique
  identity rather than their reusable network ID.
- The reward goes into a *transactional inventory copy* first: insufficient
  space results in **zero items added and zero stock consumed**. Successful
  claims atomically reduce the public `supplies_left` count by one.
- A disbanded or expired owner loses access immediately; on the next
  territory tick the remaining cache is cleared. The server initializes a
  new five-parcel stock only when a valid group captures the flag again.
  Cache claimant identities are **never included in public snapshots**.
- Supply stocks are server-session state, like the current outpost
  ownership; this is not yet a persistent guild treasury. The permanent
  character inventory received after a successful claim is saved by the
  normal Nakama autosave/logout flow.

This feature needs no additional C++ engine primitives: the existing
authoritative terrain, parties, combat risk, inventory and networking APIs
already cover safe transfer.

```sh
godot --headless --path game --script res://tests/run_all.gd
```

The `game/tests/test_outpost_supplies.gd` suite validates PvP-zone
reward tables, real capture requirements, proximity and hostile presence,
full-backpack rollback, once-per-account protection, finite shares, expiry
and renewal after recapture.


## Combat skill merge regression: maul + pistol both available

The **Purifier Maul T3** from elite/raid cores and the pistol's
**Focused Shot** now coexist in the same classless combat rules.
The maul has **Purifying Slam** (35 energy; 8-second cooldown) and grants
25% additional damage to infected only. The pistol retains its existing
ammunition-consuming ranged ability. The server derives melee/ranged
hits, stamina, cooldown and carried-weapon ownership from its own state.

Fixes an earlier merge that accidentally dropped the maul's skill and
its infected-only damage trait while adding the pistol skill. Also fixes
stale/ghost equipped items dealing weapon damage after the last copy has
left the inventory. PvP remains unaffected by the PvE bonus.

The existing `tests/test_purifier_maul.gd` is updated for Focused Shot
coexistence and re-registered in `tests/run_all.gd`; both the regular
`test_ranged_skills.gd` and relic tests must run together.


## Attacker siege breaches (crafting x dangerous-zone PvP)

The defenders' T1–T3 outpost walls now have a resource-paid counterplay
mechanic. **Two living members of the same attacking party** must be within
the outpost's 12-metre capture radius; the player performing the breach must
be within 4 metres. The target must have an active enemy owner and at least
one fortification tier. Each successful breach consumes **2 Planks T2 and
2 Metal Bars T2** from the attacker's backpack, destroys one fortification
tier and shortens the remaining capture requirement by 10 seconds. These
materials are produced through the existing gathering/refining economy.

An individual outpost has a server-owned **45-second breach cooldown**,
visible in the regular world snapshot and outpost HUD. The timer resets
when the outpost changes hands or becomes neutral. Attackers can fight
defenders while attempting a breach, but are exposed to full-loot PvP.
Owners cannot break their own defenses through this command.

The server authenticates the sending player, derives party membership and
number of nearby living attackers, checks backpack supplies and commits
both item removal and fortification reduction synchronously. Client RPCs
have monotonic request IDs, with cached receipts preventing repeat spends
and repeat siege damage. A breach emits a nearby-only network event.
Tests in `tests/test_outpost_breach.gd` cover ownership, group size,
distance, consumption, replays, cooldown, character dirty flags and
restoring defenses.

Outposts still belong to session-based parties, not persistent guilds.
This patch does not claim crash-atomic cross-character transactions or
durable territory ownership. The current engine already supports its
server-side simulation and reliable RPCs; no native Cgame change is required.

## Guardian frontliner — classless group tanking

A party survivor carrying an equipped **melee weapon** can press **F1**
or select **Guardian taunt** in the online **I** inventory/party panel.
The ability costs **25 combat energy**, has a **20-second cooldown**,
and briefly redirects up to **three nearby infected already chasing
teammates** toward the guardian. Forced focus lasts **3 seconds** within
12 metres. Aggro is released early when the guardian enters the safe
hub, dies, disconnects or runs beyond the infected pursuit leash.

This is a PvE role rather than a PvP stun or class lock: it does not
change other players' targeting, steal solo players' engagements, pull
neutral enemies or award fake damage/mastery. The dedicated server derives
party membership, current infected targets, range, equipped weapon and
energy from authoritative state. The client sends only a request and
shows its own cooldown. Rejected casts consume nothing. The offline
single-character preview has no party to protect, so this is an online
party-only ability. Regression coverage lives in
`game/tests/test_guardian_taunt.gd`, registered in `run_all.gd`.
No new C++ engine primitive was needed.


## Elite trophy armor: Infected Warden Jacket T3

Survivors can forge an **Infected Warden Jacket T3** at the workbench
with three elite/raid Infected Cores, four T3 cloth and one T3 bar.
Crafting T3 mastery and real server-owned material consumption are required.
Like ordinary T3 armor, the jacket reduces direct damage by 22%.

The jacket additionally reduces **infection from actual infected hits by
40%** and **bleeding from infected hits by 30%**. These modifiers are
implemented in the authoritative zombie-hit branch: the server checks
that the armor is still physically carried and equipped; a stale slot,
missing item or normal T3 jacket has no protection against secondary
wounds. PvP bleeding uses the original rules without these infected-only
bonuses. The armor is ordinary equippable and tradable full-loot equipment.

The new `test_warden_jacket.gd` suite checks T3 recipe gates, trophy costs,
actual zombie damage and wound events, stale equipment, and PvP separation.
No Cgame core changes are necessary for this feature.


## Survival spears T1–T4 — classless long-reach melee equipment

The canonical `game/` world now offers craftable **Survival Spears** at all
four equipment tiers. Each tier costs 2 matching planks, 1 matching metal bar
and 2 matching fibers at the workbench. Existing crafting mastery gates higher
tiers; spears are ordinary gear for inventory, trading, stash and full-loot PvP.

- **Basic spear attacks:** 3.5 m melee reach, 0.86 s attack interval,
  damage 12/20/28/36 by tier. Clubs remain faster and hit harder up close.
- **Piercing Thrust (G):** 4.5 m forward reach, 1.45× base spear damage,
  **25 combat energy**, **5.5 s cooldown**, and **0.9 s attack lock**.
- The server derives reach, damage and the skill from actually equipped and
  owned gear; it validates aim vectors, cooldown and combat energy. No RPC
  accepts client-authored attack reach or damage. Misses still consume energy.
- Spear kills advance the same persistent melee weapon mastery as clubs.
  Infected hits, PvP safe zones, group-friendly-fire rules and bleeding remain
  processed by the existing shared combat and survival code.
- Online HUD identifies **Piercing Thrust (G)** when a spear is equipped;
  the local gameplay scene already uses the same server skill command via G.

`game/tests/test_spears.gd` is part of
`godot --headless --path game --script res://tests/run_all.gd` and checks
recipes, server-side crafting, range, mastery, cooldown, anti-spam, stale gear
and safe-zone protection. The current Cgame engine APIs support this feature;
no changes to the engine core were necessary.


## Persistent survivor renown and supply discounts (Days After × Albion × Lineage)

Camp renown is a **per-character progression** that rewards verified survival
and PvE without permanent classes, extra PvP damage or free loot. It lives in
the canonical `game/` game server and is saved with the existing Nakama
version-1 character record.

The server, never a client request, grants renown **once per actual infected
death** (walker 1, runner 2, brute 4, elite +5, raid boss +35) or **once
per successful camp-contract turn-in** (+8). A failed claim, unaccepted
contract, duplicate hit on a corpse or idle party observer yields nothing.
The lifetime score is bounded at **10,000**. Rank milestones are:

| Renown | Title | Discount on NPC purchases |
|---:|---|---:|
| 0–39 | Newcomer | 0% |
| 40–159 | Settler | 10% |
| 160–499 | Ranger | 15% |
| 500+ | Warden | 20% |

Only the **hub NPC's water, food and bandages** use the ranked purchase
price. The server rounds each discounted unit price **up to at least one
silver**, and then multiplies by quantity. The **renown discount alone** does not alter NPC sale payouts,
player-to-player barter or market orders. If a survivor also has
PvP criminal infamy, the existing **infamy markup is applied after
the renown discount** (and infamy may independently penalize NPC sales).
Both effects are calculated server-side and the online/local UI displays
the resulting purchase price. This avoids a
buy/sell currency loop while giving established survivors modest relief
on necessities.

The online HUD shows the survivor's title, accumulated renown,
next milestone and current NPC discount, and displays recipient-only
renown notifications. The local preview shows the same values and actual
discounted water price when pressing **N** near the camp workbench.

Renown is restored transactionally alongside the survivor's inventory,
bank, contracts and professions. Legacy version-1 Nakama characters
missing the field start at zero; fractional, negative, infinite, string,
boolean or over-cap scores invalidate a corrupt save **without partially
mutating the live character**. A network client cannot send rank or points.

Test the shared server and world:

```bash
godot --headless --path game --script res://tests/run_all.gd
```

`game/tests/test_reputation.gd` covers rank boundaries, capped awards,
once-only walker/elite/raid kills and contract rewards, private network
notifications, discount pricing, atomic purchases, save migration and
invalid-save rejection. This is persistent **individual reputation**,
not yet a persistent guild ranking or shared clan treasury; those will
require an account-owned group domain to prevent cross-account fraud.


## Guardian brace — frontline damage mitigation

A successful party **Guardian taunt** now also grants its melee-equipped
user a short **3-second defensive brace**. While in a real party and
still carrying the weapon, the guardian takes **30% less direct damage
from infected**. The mitigation is applied *after armor* to both normal
zombie melee attacks and raid boss area attacks, without changing their
telegraphs or dodge timing. It does not protect against other players,
bleeding, infection, thirst, or environmental damage.

The server starts brace only after a successful energy-paid taunt and
expires it using the authoritative game tick. Leaving the party, losing
the equipped weapon, dying or respawning removes its protection;
rejected taunts cannot create free mitigation. HUD displays **Brace**
remaining seconds alongside the existing guardian cooldown. A new
`tests/test_guardian_brace.gd` suite covers damage, expiry, equipment
and group invalidation, server snapshots and death cleanup. No changes
to engine C++ are necessary for this mechanic.


## PvP infamy and outlaw reputation (classless frontier)

The canonical `game/` tracks **server-owned PvP infamy** (0–100).
Only an actual lethal attack on another survivor in an existing **red/black**
PvP zone adds 25 points. Hits, missed attacks, infected kills, protected-zone
attacks and damage to party members grant nothing. Two confirmed PvP kills
mark a character **OUTLAW** at 50 points.

Notoriety persists in the version-1 character account record; older saves
missing the field start at zero. Invalid, negative, non-numeric, non-finite
or over-cap values reject restoration atomically. Infamy decays one point
per **three minutes of online server simulation** and is not erased by death,
logout or respawn.

The safe-hub NPC first applies existing **survivor renown discounts**, then adjusts its own transaction prices using infamy:
up to **50% extra** for purchased survival supplies and up to **25% less**
for materials sold to the merchant. The unit cost is calculated by the
server before debiting or crediting real items; quantity splitting cannot
evade the per-unit price. The player market and private trades keep their
original negotiated prices.

The owner sees the exact score and outlaw flag in the multiplayer HUD.
Other nearby survivors see only an **OUTLAW** nameplate marker, not the
private score. The local preview also displays current reputation.
This system **does not change** safe-zone PvP protection or the
red/black full-loot policy. No automatic bounties or guild penalties
are added in this iteration.

Run `godot --headless --path game --script res://tests/run_all.gd`:
`game/tests/test_pvp_infamy.gd` covers red-zone kills, anti-replay,
safe-zone/PvE immunity, privacy, pricing, atomic vendor trades, decay,
legacy saves, invalid values and death retention. No new native engine
capability is required.

## Spear piercing attacks

The existing T1-T4 Survival Spear's **Piercing Thrust (G)** now hits up to
three distinct valid targets along its forward **4.5 m** line. It retains
its original 25-energy cost, 5.5-second cooldown and 1.45x damage. The
server enforces all existing party-friendly-fire and PvP zone protections.
Clubs and firearms retain single-target active skills.

The canonical local preview already cycles through owned weapons with **4**;
the online HUD names the currently equipped ability. Test coverage:
`game/tests/test_piercing_thrust.gd` within `game/tests/run_all.gd`.
No additional native engine APIs are required for this gameplay feature.


## Warden two-piece set aura for party expeditions

Survivors who **equip and physically carry both** the rare
`purifier_maul_3` and `warden_jacket_3` become expedition guardians.
Within **8 metres**, their living party allies receive **15% less
infection and bleeding from actual infected attacks**. The ward does
not stack with additional guardians, never activates for solo players
or for the guardian themselves, and immediately stops when the set is
removed, the guardian dies, party membership changes, or players
separate into different zones. The safe settlement does not emit a ward.

The server validates the complete two-piece set and party roster at each
actual zombie hit. The existing jacket's personal wound resistance is
calculated first; this party set bonus only mitigates secondary infected
wounds and never alters incoming damage, PvP bleeding, dodge immunity,
experience, attack threat or full-loot drops. The multiplayer HUD shows
**WARDEN'S WARD** only when the server reports it active. This makes
elite-core gear meaningful for classless Lineage-style group support.

The headless `tests/test_warden_aura.gd` covers real server combat,
multiple guardians, worn/owned equipment, movement, death, party changes
and unchanged PvP. No native Cgame engine changes are needed.

## Declared siege contracts (party war preparation and honor)

A party leader can declare a **timed siege challenge** against a hostile
player-controlled outpost from within 24 metres, provided a second living
party member is also nearby. The declaration consumes **2 Cloth T2 and 25
Silver** from the leader's real backpack. Players must own neither the
outpost nor its party; objectives about to expire refuse new challenges.
Any already-active declaration or recently resolved siege blocks repeat
contracts for that site.

The declaration announces a **20-second preparation countdown**, followed by
an **180-second assault window**. The normal territorial capture and full-loot
PvP rules are unchanged: another team can still seize an outpost without a
contract, but only a genuinely completed capture *during the declared
window* earns a siege-contract victory. Early conquest, capture by a third
party, loss of either group or the end of the window cancel the challenge
without rewarding honor. Site cooldown is 300 seconds after resolution;
the non-tradable siege victory counter belongs to the current server party.

The server derives leader permissions, teammate proximity, party identity,
target ownership, deadlines and item costs. Only the actual server
`outpost_taken` event can award a victory, once per challenge. Requests
carry monotonic peer IDs; retries return the prior result without
double-charging resources. Nearby players see declaration/result events,
and everyone receives public outpost preparation/assault timers through
the existing snapshot. The HUD adds a **Declare siege** action and displays
the current party's siege victories.

Source: `scripts/shared/siege_contracts.gd`, `game_server.gd`, network RPCs
and HUD; regression checks: `tests/test_siege_contracts.gd`. This is
**session-based party siege warfare**, not permanent authenticated guild
ownership, cross-server match scheduling or Nakama-backed honor. Those
features require an identity-checked guild persistence layer. No native
Cgame engine change is required by this phase.

## Clattering noise decoy — craftable stealth tactic

Craft a **Clattering Decoy** from **2 Wood T1 and 1 Scrap Metal** using
the ordinary crafting system. Press **comma (,)** in either local preview
or dedicated multiplayer to throw it **8 metres** forward; the online
inventory also offers a *Throw clattering decoy* button.

A decoy produces **8 seconds** of sound that attracts idle infected
within **23 metres** to investigate the landing site. It never acts as
a fake player, interrupts an active chase or tank-generated combat threat,
or distracts raid bosses. It does not change full-loot PvP, zombie damage,
or experience rewards.

The dedicated server checks the real player's inventory and position,
finite input direction, terrain, water, safe zone, and every obstruction
along the flight path. Each valid throw consumes exactly one item and
starts a **3-second cooldown**, with a maximum of **two active decoys
per player and 48 server-wide**. Temporary decoys are cleaned up after
expiration and never persisted. Only their visible position and remaining
lifetime are sent to nearby clients; both clients render a small yellow lure.

`test_noise_decoy.gd` verifies placement, inventory cost, cooldown,
zombie investigation, active combat and boss immunity, privacy, interest
filtering, and cleanup. Existing Cgame simulation, world geometry and
rendering APIs cover the feature without a native engine change.


## T2–T4 expedition stormcoats (weather-versus-combat loadouts)

Survivors can now craft **Expedition Stormcoats T2–T4** at the normal
workbench using **six matching-tier cloth and four matching-tier fiber**.
Higher tiers require matching server-owned crafting mastery. Coats are
equippable, storable, tradeable, and can be dropped under existing full-loot
rules, just like other armor.

Ordinary jackets and raid armor retain their existing **35% weather
insulation**. Expedition coats instead provide **55% (T2), 67% (T3), or
78% (T4)** storm insulation, while reducing ordinary attack mitigation
by three percentage points compared with a same-tier combat jacket.
They use the existing exclusive armor slot, so players must choose a
mountain/storm expedition loadout or their optimal PvP combat defense.

The actual game server verifies that the equipped coat still exists in
the backpack before granting any weather protection; a ghost equipment
slot cannot manufacture warmth. Both the local and connected HUDs display
the selected insulation percentage. Cold exposure, heat packs, campfires,
biome temperatures, shelter and death remain controlled by existing rules.

New `test_stormcoats.gd` checks every tier, recipe costs, profession gates,
real server cold exposure, owner snapshots and stale-item exploit prevention.
This game-layer expansion needs no changes to Cgame's native engine code.


## Blood scent: wounds affect infected detection (survival + zombie AI)

Untreated bleeding now affects stealth in both the canonical local preview
and authoritative multiplayer game. When bleeding exceeds **12/100**,
infected can smell a survivor's wound from **about 20–30 metres**,
compared with a walker's normal **16 m** sight range. The radius scales
with actual wound severity and drops as a wound naturally clots.
Bandages and party medical aid that stop bleeding immediately remove
this *additional* detection channel.

Existing safety and combat rules remain intact: infected cannot acquire
a dead or safe-hub survivor through scent, pack/threat and guardian
taunt priorities still apply, and scent never extends an enemy's
normal pursuit leash. A zombie already pursuing a player can keep
following until it ordinarily loses interest — healing does not
magically reset an established chase.

The server calculates scent exclusively from the authoritative character
`Survival.bleeding`, not a client RPC. Only the survivor gets their
effective scent radius in the private snapshot for a HUD warning;
bleeding values are not added to the replicated bystander list.
The local playable preview shows the same warning and first-aid hint.

Implementation: `scripts/shared/blood_scent.gd`,
`scripts/shared/zombie.gd`, and `scripts/server/game_server.gd`.
Tests: `game/tests/test_blood_scent.gd` in the headless suite
(`godot --headless --path game --script res://tests/run_all.gd`).
Existing GDScript simulation and networking provide this mechanic;
no native Cgame engine extension is necessary.


## Classless archery: crafted bows T1–T4 and quiet Power Draw

The canonical `game/` project now has **Survival Bows T1–T4** for
survivors who prefer hunting infected without loud gunfire. Each bow is
crafted at the workbench from 2 planks, 2 fibres and 1 cloth of its tier;
higher tiers use the existing crafting mastery gates. Equip with the
online inventory panel or the local preview's **4** weapon-cycle key.

- **Normal shot:** 27 m range, 1.05-second interval, 10/17/24/31 base
  damage by tier. A real wooden arrow is consumed for each successful shot
  attempt (including shots that miss).
- **Wooden Arrows:** 2 wood T1 + 2 fibre T1 craft **16 arrows** without
  a workbench. They are ordinary consumable inventory and market goods.
- **G — Power Draw:** 32 m range, 1.6× bow damage, 30 combat energy,
  one arrow, 6-second skill cooldown, 1.2-second regular-attack lock.
- **Quiet ranged combat:** a bow shot makes 9 m noise for 0.8 seconds;
  a pistol retains its original 32 m noise for 3 seconds. Both normal
  shots and active skills feed the existing zombie hearing AI.
- **Ranged mastery:** bows share the existing permanent weapon mastery
  with pistols; owned equipment, arrows, aim vectors, distance, damage,
  cooldown, risk-zone PvP and party-friendly-fire are validated server-side.

The new regression `game/tests/test_bows.gd` covers real crafting and
inventory, authoritative damage, arrow consumption, quiet sound, mastery,
PvP safe zones, stale equipment and saved gear. Run it with the rest of
the game via `godot --headless --path game --script res://tests/run_all.gd`.

The feature reuses existing Cgame gameplay, physics, audio signalling
and multiplayer primitives. No native engine changes were required.

## PvP self-defense and hunting criminal outlaws

A real damaging PvP attack in red/black zones opens a **30-second legal
retaliation** window for the victim against that attacker. The original
aggressor cannot earn an exemption simply because their victim hits back.
Players marked **OUTLAW** (50+ infamy) may also be defeated without
accruing criminal infamy. Ordinary unprovoked kills continue to add
25 infamy. Server-only timers expire automatically and are cleared upon
an aggressor disconnect, a victim's death or respawn. They are never
stored in Nakama saves, and a recycled peer ID cannot transfer guilt.

The existing kill/death, full-loot and anti-farming PvP honor rules stay
unchanged; this system creates no new silver, experience or loot. Online
HUD and private network messages inform the defender and lawful hunter.
Headless checks are registered as `tests/test_pvp_justice.gd`. Existing
Cgame PvP simulation and RPC APIs are sufficient; no C++ work is required.

## Scalable infected hearing for noise lures

Temporary sound lures use a bounded, deterministic spatial hearing index
instead of checking every active lure against every infected on each AI pass.
Cells are one hearing radius wide, so a zombie checks only nine nearby
cells. Among audible devices the nearest wins (ties use world ID). Expired
or invalid sources are excluded. An infected already investigating a lure
finishes its investigation rather than switching targets every quarter
second; active combat and raid targeting remain unchanged.

A forged very large client direction is rejected before vector normalization,
and a lure cannot be thrown out of the protected settlement from inside it.
The existing ordinary items, NPCs, snapshots, recipes and controls are
unchanged. Tests: `game/tests/test_noise_decoy_grid.gd`.

## Verified Nakama guild identity and guild-safe PvP

Authenticated ENet players now receive a **server-verified guild affiliation**.
A server-key-only Nakama Lua RPC queries `user_groups_list`, accepts only
full member/admin/founder roles (states 2/1/0), and returns the selected
guild's ID, display name and role. Pending invitations and join requests do
not count. The server loads this identity at sign-in and refreshes it
every 45 seconds; lookup failures clear the cached privileges. Guests do
not receive a guild. Guild IDs are **never read from client RPC parameters
or character save documents**. The ordinary account ID is still private.

Confirmed members of the **same guild cannot harm each other in PvP**, even
when in different parties. The server skips verified guildmates when
selecting melee/ranged hit targets, and repeats the same check at actual
damage application, so a direct damage call cannot bypass the protection.
Members of different guilds remain enemies in red/black zones; temporary
party-friendly fire protection still applies separately. A leave or kick
is reflected after the server's next guild refresh (up to 45 seconds),
and after reconnect immediately. The HUD displays the verified guild
name and number of guildmates nearby, while public nearby-player snapshots
contain only guild name and ID, not account IDs or member roles.

Tests: `tests/test_verified_guild_pvp.gd` covers identity validation,
enemy targeting, damage prevention, revocation, guest isolation and
private fields. `tests/test_nakama_backend.gd` additionally creates and
joins a real guild, verifies role membership and proves the privileged
identity RPC is inaccessible from normal player sessions.

**This is not yet persistent guild territory ownership.** Current outpost
control and declared sieges still use temporary parties; authenticated
guild tags and same-guild combat rules are a safe prerequisite for
introducing persistent Nakama guild claims and a durable war ledger.
All functionality uses existing Nakama and Cgame network APIs; no native
engine modification was necessary.


## Expedition field respite (live fire, food and nearby danger)

The existing **Z** rest action in the local game and multiplayer **Rest**
button also support field respite near an existing active campfire (5m).
This consumes **one clean water bottle** plus **one cooked fish T1–T4**
(lowest tier first), or **one canned ration** when no fish is available.
Field respite heals 12 HP and restores 30 stamina, 8 hunger and 10 thirst.
The safe hub keeps its more generous recovery and resource requirements.

Both actions share the persisted **90-second cooldown**. The server rejects
field rest if a fire has expired, a survivor is fighting, an infected is
within 13m, or a potential nonparty PvP opponent is within 10m in red/black
zones. Refused requests consume nothing. Infection and bleeding still
require real medical supplies; field resting cannot be used for immunity or
instant recovery during combat.

`tests/test_field_rest.gd` covers a real server-built fire, ingredient
transactions, T2 fish fallback, cooldown, nearby infected and PvP threats,
and expired fires. Existing Cgame APIs and RPCs support this game feature.


## UTC daily camp bounties — repeatable MMORPG survival loop

The existing four **one-time story contracts** remain unchanged. After
finishing them, or while progressing through them, every survivor also has
a **repeatable camp bounty** that rotates automatically at **00:00 UTC**.

The authoritative server chooses the task from the UTC day number
(`floor(unix_time / 86400) % 3`) — the client cannot choose a
preferred task, fake its progress, or submit a different timestamp.

| Rotation | Real-world objective | Reward |
|---|---|---|
| Infected sweep | Defeat 4 real infected | 24 silver, 1 bandage, 4 renown |
| Ruin reconnaissance | Open 2 distinct unopened ruin crates | 30 silver, 1 water, 5 renown |
| Camp resupply | Deliver 5 T1 wood and 4 T1 fiber | 28 silver, 1 canned food, 4 renown |

Confirmed infected deaths and real crate openings advance progress using the
**existing game server**, not a client counter. One crate cannot count twice
even if it refills. Daily material delivery is checked only when claiming the
reward at the camp workbench. Failed inventory capacity checks, missing
materials, and attempts to turn in away from camp have **no payout**.
Each character receives **at most one bounty payment per UTC day**, even
after logout/reconnection. A backwards-moving server clock never reopens
a previously claimed day.

To check progress, open the **I** inventory panel; a daily mission line
appears alongside the original camp contracts. Use **Turn in UTC daily
bounty** at the settlement workbench. In the local singleplayer preview,
the bounty is displayed in survival statistics and **Ctrl+P** turns it in
(ordinary `P` and `Shift+P` still operate the one-time contracts).

The separate `daily_bounty` record is saved alongside inventory, stash,
contracts, professions and renown in the existing **Nakama v1 character**
document. Older characters default safely to a new bounty. Malformed
progress, duplicate crate IDs, impossible day values and forged completion
states are rejected **before** any live character state is replaced.

`game/tests/test_daily_bounties.gd` is included in the main Godot
headless regression suite and covers all three rotations, one-time
payouts, atomic delivery, daily reset, server-authorized PvE/scavenging,
camp distance, account reconnect and save migration:

```sh
godot --headless --path game --script res://tests/run_all.gd
```

No new C++ engine feature was required: authoritative game events,
persistent Nakama character documents, server-side UTC timestamps and
atomic inventory transfers are already supported by Cgame.


## Frontier adrenaline shot: elite-sourced expedition recovery

The canonical `game/` adds a rare **Frontier Adrenaline Shot**, bridging
Days After survival supplies with Albion-style classless combat energy.
It requires T3 crafting mastery at the safe hub workbench and uses one real infected core,
one field antiseptic, and one clean water bottle. Elites and other
existing infected-core sources remain the only way to obtain the trophy;
neither the vendor nor a new debug spawn grants a free shot.

Using a carried dose while genuinely fatigued immediately restores
**50 stamina and 35 combat energy**, capped by existing player maxima,
but costs **12 thirst** and starts a **90-second personal cooldown**.
When both resources are almost full, the dose is rejected as wasteful;
survivors with less than 12 thirst cannot inject it. Failed use,
cooldown/replay attempts and missing inventory do not consume a dose.

The server computes the effect and deducts the actual item. The cooldown
is serialized in the existing version-1 character save, validated before
any live state is modified, and persists through death, respawn and
reconnection. Old saves without `stim_cooldown` remain compatible.
The existing `c_use` RPC and inventory action support the online client;
its HUD shows any remaining recharge. The local playable preview has
a dedicated **.** key and displays the same cooldown.

Files: `scripts/shared/frontier_stim.gd`, existing item and recipe
definitions, `scripts/server/game_server.gd`, and both clients.
Headless regression suite `game/tests/test_frontier_stim.gd` is
registered in `game/tests/run_all.gd`. Native engine changes are not
required for a fully server-owned, inventory-paid consumable.

## Ghillie cloaks T2-T4: classless stealth against infected

Craft **Ghillie Cloak T2–T4** at the workbench from tier-matched
cloth (4), fiber (6) and one plank. The cloaks use the existing armor slot,
crafting mastery, trading and full-loot system. They provide deliberately
less damage reduction than combat jackets or stormcoats. No native engine
API extension is required.

**While quiet**, a T2/T3/T4 cloak reduces *visual* acquisition range of
idle infected by 38%/45%/52%, before normal day/night adjustments.
Running or firing a noisy weapon interrupts concealment until its audible
effect expires. Blood scent from untreated wounds and pack/combat aggro
are not negated; an already engaged enemy keeps chasing. The server
derives the modifier strictly from still-carried equipped armor and its
own sound timer, never from client requests. Both the online HUD and
local 3D preview display concealment status; nearby enemies still use
normal safe-zone and sight/hearing rules.

Regressions: `game/tests/test_camouflage.gd` in the canonical suite.


## Hearty cooked meals — classless expedition recovery

Cooked coastal fish are now a meaningful **temporary combat provision** as
well as normal hunger-restoring food. This connects Days After cooking and
survival with Albion/Lineage-style preparation for expeditions, without
adding a fixed class or any client-authoritative stat changes.

- Eating a carried **cooked fish T1–T4** grants a single, non-stacking meal
  buff lasting **120 / 150 / 180 / 210 seconds**, respectively.
- During the buff, a nourished and hydrated survivor gains **+2.0 / +2.5 /
  +3.0 / +3.5 stamina per second** after the normal sprint/dodge recovery delay,
  and **+0.75 / +1.0 / +1.25 / +1.5 combat energy per second**. Existing
  stamina/energy maxima still apply. Starving or dehydrated characters
  get no additional recovery.
- Eating another cooked fish **replaces** the current tier and duration;
  it cannot stack the timers or inflate recovery. Berries and canned
  food remain food only, with no temporary combat bonus.
- The authoritative `GameServer.cmd_use` consumes one real cooked item.
  All recovery and expiry occur on the server tick, including partial
  final frames. The buff is **persisted with strict validation** through
  logouts and reconnects, and cleared on death/respawn. Older version-1
  characters with no buff fields load with an inactive effect.
- The multiplayer and local survivor HUDs display the meal tier, seconds
  remaining and recovery rates. No new networking endpoint is required;
  the owner snapshot contains `meal_tier` and `meal_seconds`.

Implementation: `scripts/shared/hearty_meal.gd` and
`scripts/server/game_server.gd`. Headless tests:
`tests/test_hearty_meal.gd`, registered by `tests/run_all.gd`.

Run `godot --headless --path game --script res://tests/run_all.gd` to
verify game food, stamina, combat energy, save safety and respawn regressions.
This uses existing Cgame server simulation and HUD primitives; no native
engine extension was needed.

## Acid spitters: telegraphed red/black-zone infected PvE

A new **spitter** enemy appears rarely among red-zone ruins and more
frequently in black zones, but never spawns in the protected green/yellow
wilderness. A spitter takes position 3–12 metres from its target and
winds up a corrosive area attack for **1.4 seconds**. A bright green
**2.4-metre-radius** ground marker shows the exact landing zone; players
can leave it or time a dodge. The server freezes the target point at
warning time, never follows a moving player, and resolves one impact
against nearby survivors only once. The infected's volley has a
**6-second cooldown**, deals 14 base damage and can add an infected wound.

The existing armor, dodge, guardian group protection, PvE wound ward and
safe-zone checks are respected. PvP attacks and ordinary zombie melee
remain unchanged; a dead spitter cannot land a pending projectile. The
online interest-filtered snapshots expose warning positions but do not
expose internal AI target IDs. Both the local playable scene and online
clients render the ground warning, and the multiplayer HUD announces
incoming acid. Normal spitter defeats award ordinary combat mastery and
renown; no client can spawn or control this enemy.

Regression checks are in `game/tests/test_acid_spitter.gd`, registered
in the canonical headless runner. This uses Cgame's current AI, materials
and networking APIs without requiring new C++-engine primitives.


## Herbal scent salve — craftable survival stealth versus bleeding detection

In the canonical `game/`, survivors can craft a **Herbal Scent Salve**
from **2× T1 fiber + 1× T1 cloth + 1× clean water bottle**, anywhere in
the field (no workbench required). A real carried salve can be applied
for **120 seconds** of temporary camouflage.

While active, the server suppresses *only the extra blood scent* that
otherwise lets infected locate a badly bleeding survivor from farther
away. Normal zombie visual range, gunshot/sprint hearing, existing
combat aggro and pursuit leashes all remain in effect. The paste does
not heal bleeding, stop infection, restore health or remove an existing
zombie chase; bandages and medical aid remain important.

The effect is strictly server-owned and inventory-paid. Repeated use
while active returns `already_masked` without deducting a second
salve. Its remaining duration is stored as `scent_mask_seconds` in the
existing version-1 survivor save and validated as a finite number in
the range 0–120 before any state mutation. Older character saves
default to zero. Timer decreases only with game simulation and is
cleared on character death and respawn.

Local preview: **/** applies a carried salve; HUD shows active time and
the actual post-mask blood detection radius. Online multiplayer:
click the carried salve in inventory (existing authenticated
`c_use` path); the owner's snapshot shows the remaining time and
adjusted blood-scent risk without broadcasting private wounds or
stealth duration to nearby clients.

Implementation: `scripts/shared/field_scent_mask.gd`,
`scripts/shared/blood_scent.gd`, `scripts/shared/survival.gd`,
`scripts/server/game_server.gd`, item definitions and both clients.
`game/tests/test_scent_mask.gd` is registered in the headless
regression suite and covers field crafting, scent-versus-sight,
paid-use replay, expiry, older saves, invalid durations and respawn.
No engine-native extensions are necessary; the existing Cgame AI,
crafting, character persistence and network primitives suffice.


## Verified guild banners for contested outposts

Outposts are now marked with a **live Nakama-verified guild banner** when
their current owning party contains at least two online members and **every
member** belongs to the *same* verified guild. Mixed parties, guests,
unverified memberships, missing party rosters and neutral flags never show
a guild banner. Guild IDs and names are derived on the server from trusted
player sessions; they cannot be set by an ENet request or loaded from an
untrusted character save. The outpost snapshot exposes only the public
guild name and ID, never a player's account ID or guild administration
rank. The closest-outpost HUD displays the clan name and shows *CLAN ALLY*
for fellow guild members who are in another temporary party.

During ownership, nearby guild members are counted on the owning party's
defensive side, so allied parties no longer falsely **contest** the flag.
Verified guildmates can also receive the existing small, 18-metre stamina
rally bonus even when not in the owner's temporary group. Guild members
cannot spend siege declaration materials to declare war on their clan's
outpost, or expend breaching materials against its fortifications.
Hostile parties and unaffiliated guests retain all existing PvP rules.

No guild advantages are permanently cached in world state: banners and
permissions are recomputed from the **current** online party roster on
each server update. Changing/leaving a guild, disbanding a party or
losing the point removes its banner and allied privileges. Since group
memberships are refreshed by the existing Nakama server integration,
changes are reflected after refresh (up to 45 seconds) or reconnect.
Capture and siege windows otherwise continue to use the established
party mechanics.

This is the integration layer toward **persistent guild-based ownership**,
not a claim that outposts or victories survive a server restart. Durable
Nakama ownership, distributed locks, guild treasury and crash-safe
siege results must be added before claiming persistent castle wars.
Implementation: `scripts/shared/guild_territory.gd` and
`territory_control.gd`; regression checks in
`tests/test_guild_territory.gd` through `tests/run_all.gd`.
No native Cgame engine change was needed.

## Lingering acid pools after spitter attacks

The **acid spitter** now leaves a shallow corrosive patch for **5 seconds**
after its original telegraphed impact. The initial hit remains the same;
survivors standing in the patch take **3 base damage each second** plus a
small infected wound. This forces parties to reposition instead of camping
on a fixed raid position. Armor, dodge immunity, guardian mitigation,
wound resistance and safe-zone rules still apply.

An authoritative server maximum of **64 active patches** prevents
unbounded world entities; two overlapping pools are globally limited
to **one periodic hit per survivor per second**, not multiplicative burst
damage. Skipped server frames never cause a backlog of damage, and expired
pools cannot apply damage later. Only the patch center, radius and
remaining lifetime are interest-filtered to clients; actor identifiers and
hit cooldowns stay private on the server.

Both playable clients render yellow-green shallow pools in-world and remove
them when they expire. These hazards are temporary gameplay state, not
persistent map edits, craftable resources or new PvP interactions. Headless
regressions in `tests/test_acid_pools.gd` cover initial splash, delayed
damage, immunity, overlapping pools, out-of-area movement, safe hubs,
expiry, network privacy and disconnect cleanup. Existing Cgame API
capabilities are sufficient.


## Shore fishing bait: resource-paid, server-owned extra catch

The playable `game/` now supports **optional baited fishing**. A survival
artisan can craft **2 Shore Fishing Bait** anywhere from **2 berries and 1
T1 fiber**. Normal shoreline fishing is unchanged. For an explicit baited
cast, the server verifies a real carried fishing rod, accessible coastal
water, sufficient inventory room, actual fishing profession and current
zone tier, plus at least one unit of bait.

A completed baited cast yields **one extra fish** above the ordinary
server-determined 1–2 fish catch (**2–3 total**) without ever increasing
fish tier. One real bait is charged **at catch completion** and only if
the inventory has space to deliver the entire base catch plus the extra
fish. Moving away, losing the shore, missing bait or a cramped backpack
never charges for a bonus not delivered. Only actually credited fish earn
fishing profession experience. Cast duration and the normal cooldown
stay unchanged. The client supplies only the optional bait-choice flag,
never a catch quantity or tier.

Offline preview: **T** casts normally, **Shift+T** requests baited fishing.
Online inventory: separate **Cast fishing rod** and **Baited cast**
buttons. Multiplayer routes the choice through authenticated `c_fish`
to `GameServer.cmd_fish`; clients cannot forge fish counts or skip
the existing rod, coastal access and profession limits.

Code: `scripts/shared/fishing_bait.gd`, `scripts/shared/fishing.gd`,
item/recipe definitions, canonical game server and online/local clients.
Tests: `game/tests/test_fishing_bait.gd`, included in `run_all.gd`,
for crafting, tier caps, inventory capacity, paid rewards, experience
and interrupted casts. No C++ engine change is needed for this
server-authoritative feature.


## Shared camp feast — classless party expedition preparation

A survivor party can now turn existing **fishing, prepared coastal dishes,
campfires and classless meal buffs** into a cooperative pre-raid meal.
In the online party/inventory panel select **Cooked Fish T1–T4** and press
**Share cooked meal**.

- The cook and at least **one other living, accepted party member** must
  stand within the same **lit field campfire** (5 m horizontally, 2.5 m
  vertically). Remote, dead, unrelated and former members are excluded.
- The cook must **carry one cooked fish per eligible recipient**, including
  themselves. The server counts recipients, verifies stock, and removes
  all portions atomically before changing anyone's hunger or buffs.
  If even one portion is missing, no item or character state changes.
- Each served party member gets normal cooked-fish nutrition and the
  established **120–210 second T1–T4 recovery effect**. A weaker dish
  cannot overwrite an ally's stronger active buff.
- There is a **20-second per-cook server cooldown**. The buff itself is
  persistent through relogs, expires on server ticks and is cleared by
  death, exactly as with individual cooked meals. The feast cooldown is
  session-only and resets on respawn.
- The multiplayer party panel shows the feast cooldown and privately
  notifies each recipient. No client may supply the fire position,
  party membership, amount of food, or magnitude/duration of the buff.

Code: `scripts/shared/party_feast.gd`, `scripts/server/game_server.gd`,
`scripts/shared/net.gd` and the online client/HUD. Tests:
`tests/test_party_feast.gd` in the shared
`godot --headless --path game --script res://tests/run_all.gd` runner.
The Cgame engine already supplies the necessary multiplayer and world
simulation APIs; no native engine changes were needed.

## Durable Nakama guild siege honor (server-only journal)

Victory history now survives a dedicated server restart in **Nakama**.
When a real `siege_contract_result` with `result = won` comes from
the authoritative territory simulation, the game checks that its attacker
still owns the outpost and has a homogeneous party of **verified Nakama
guild members**. Only then does it enqueue a guild victory. Guest players
and mixed-party victories remain valid gameplay wins, but do not increment
a persistent guild score.

The backend `guild_siege_commit` RPC requires the server runtime key and
writes both a private guild score and an **immutable 128-bit event receipt**
in a single version-checked storage batch. Retries reuse the same event ID,
so a timeout after a committed write cannot create a second win. Competing
writes retry on optimistic-version conflicts. Reusing an ID with changed
guild, world seed or site is rejected. The `guild_siege_score` RPC reads
the persisted total; connecting guild members retrieve it and the server
refreshes the cache periodically. The HUD shows **Historic clan siege wins**
in addition to session-specific party siege wins.

**Scope and recovery:** Guild scores and already committed receipts are
durable. The world server's queue of unsent events is still RAM-only;
an abrupt crash *before* Nakama confirms a write can lose that pending
achievement. This is not yet an exactly-once **end-to-end** event pipeline,
an offline guild treasury, or persistent castle ownership. Reliable
survival of pre-commit events will need a local durable outbox and recovery
at boot. Guild tags, outpost occupancy and siege authority remain
server-owned; clients never submit score events or guild IDs.

Tests: `tests/test_guild_siege_ledger.gd` checks event eligibility and
membership revocation. The Nakama integration suite
`tests/test_nakama_backend.gd` covers original writes, identical
replays, event collisions, independent victories, reload and server-key
permissions. No Cgame engine modifications were necessary.


## Survivor tripwire snares — tactical infected control in the wilderness

The canonical `game/` adds a **field-craftable Infected Tripwire Snare**.
Make one kit from **2 T1 wood, 2 T1 fiber, 1 scavenged scrap**, without
a workbench. Place it **1.5–4 metres** away on traversable ground outside
the safe settlement. The authoritative server rejects obstructed terrain,
water, overlapping traps, positions under living players/infected, and
nonfinite/out-of-range coordinates before consuming anything.

A placed trap lasts **150 seconds** or until the **first ordinary or elite
infected walks within 1.35 metres**. It is spent once, rooting ordinary
infected for **3 seconds** or elites for **1.5 seconds**, without dealing
damage, granting XP, changing PvP combat, or bypassing zombie aggro.
Raid bosses are immune and do not consume traps. Rooted enemies can still
attack if their existing target is within reach; the root only prevents
movement. The root cannot count as being stuck against a destructible wall.

Each survivor account may have at most **3 active snares**; the world cap
is **64**. Account-based ownership survives a peer-ID change within the
server session without exposing account identity to other players.
Trap positions are visible to nearby players through bounded public
snapshots, but ownership and absolute expiration clocks stay server-only.
Trap objects are session-limited world devices, not serialized as owned
gear or saved in the survivor's Nakama character.

Controls: local preview **backslash (\\)** plants a kit 2.8m ahead;
online **backslash** or the inventory's **Place infected tripwire**
button sends the desired point to the existing authenticated network
server. The multiplayer world renders low-profile tripwire meshes and
labels; traps disappear when triggered or expired.

The new shared `scripts/shared/infected_snare.gd` defines placement,
trigger, lifetime, public state and caps; `scripts/shared/zombie.gd`
implements temporary movement rooting; `GameServer` owns consumption,
triggers and expiry; network/client/HUD/entity view provide gameplay.
`game/tests/test_infected_snare.gd` is part of `tests/run_all.gd` and
covers paid craft/placement, spatial rejection, visibility/privacy,
normal/elite/boss interactions, wall-safe immobilization and expiry.
Existing Godot APIs support the mechanic without native-engine patches.

## Corrosive infected can damage player-built barricades

Lingering acid from a dangerous-zone spitter now **corrodes nearby
player-built defenses** at 8 raw durability damage per second while the
pool persists. This links ranged infected PvE with base defense and the
existing tiered construction/repair economy. T2–T4 reinforced walls use
their existing damage-reduction factors, so T4 only loses 4 HP per
corrosion tick. Corrosion never attacks procedural hub or decoration
objects and cannot create new resources or repair a damaged wall.

All pools share a **single hit cooldown per wall**, preventing multiple
overlapping puddles from multiplying siege damage. The same server
`damage_barricade` flow handles checkpoint revisions, destruction,
removal from collision and client snapshots. The corrosion tick does
not trust client-originated damage, coordinates or ownership; owner-only
repair and dismantling work as before. Destroyed/dismantled walls clear
their short-lived cooldown entries and any active pool expires within
5 seconds. Testing: `game/tests/test_acid_wall_corrosion.gd` in the
existing headless test suite.

## Crash-recoverable siege victory outbox (dedicated server)

Nakama guild siege victories are now written to a **local write-ahead
outbox** before the server sends a score/receipt RPC. The outbox saves each
event's original 128-bit ID, verified guild UUID, outpost ID and world seed
under `user://albion_after_siege_outbox_<seed>.json`. Each append and
acknowledgement uses a flushed temporary file followed by an atomic file
rename, replacing one validated complete checkpoint. Only after Nakama
confirms its idempotent receipt does the server remove an event from the
journal. Network errors and ambiguous responses retain the **same ID**.

When the dedicated server next starts with `--nakama`, it validates
and reloads the queue **before accepting player connections**, then
resubmits unacknowledged events. A confirmed-but-not-yet-deleted event
is safe to replay because the Nakama backend recognizes its immutable
receipt. Files with an invalid schema, duplicate IDs, impossible values,
oversized content, another world seed or an unsafe path cause startup
to fail instead of silently resetting guild history. Pending events for
different seeds cannot be mixed.

The outbox is enabled automatically when launching a dedicated Nakama
server; offline play is unchanged. Administrators can choose a dedicated
journal path with `--siege-outbox user://backups/siege_1337.json` alongside
`--nakama`. **Only one server process may write a given journal file**;
it is not a cross-shard consensus ledger. `--no-world-save` does not turn
off the siege outbox. Preserve both the Nakama database and the server's
`user://` volume across container restarts.

For a disk write failure, the server retains affected events in a
**RAM-only retry backlog and refuses to send them to Nakama until they have
been journaled**. Graceful shutdown reports failure while such events
remain unjournaled; a sudden crash during an unjournaled IO failure can
still lose those events. The small interval between calculating a world
capture and writing its outbox entry is also not a transactional boundary
with Nakama. Durable castle ownership and cross-shard exactly-once
transactions are separate future features.

Implementation: `scripts/server/siege_outbox.gd`,
`scripts/shared/net.gd`, `scripts/server/server_main.gd`.
The offline `tests/test_siege_outbox.gd` suite checks real file recovery,
record validation, append order, duplicate rejection, acknowledgement
restarts, seed isolation and corruption fail-closed behavior. Nakama
integration tests continue checking receipt idempotence. No native Cgame
engine API was missing.


## Field alkali kits: item-paid counterplay to spitter acid pools

`game/` now includes a **Field Alkali Kit**, craftable in the field from
**2 T1 stone, 1 clean water bottle and 1 T1 cloth**. The kit is available
through ordinary inventory use in online play; the inventory also has
a dedicated **Neutralize nearby acid pools** action. Local preview uses
**Shift+R** to activate a carried kit (plain R retains lake drinking).

An authorized survivor can clear **up to 3 nearest, still-active spitter
acid pools within 5.5 metres** using one real kit. Selection is wholly
server-controlled, ordered by distance and stable ID, without accepting
pool IDs, coordinates or claimed counts from the client. Expired pools,
hazards outside range, invalid positions, dead survivors and safe hubs
are not eligible. Repeated calls without an actual removable pool
report `no_acid_nearby` and **do not consume the kit**.

Neutralization removes lingering terrain corrosion/damage from the
shared server simulation and nearby network snapshots, protecting
party routes and fortifications from *future* acid ticks. It **does not**
heal existing damage or infection, cancel the spitter's warned initial
impact, defeat enemies, award combat XP, or affect PvP attacks.

Implementation uses `scripts/shared/acid_neutralizer.gd`, real
`defs.gd` crafting recipes, the authenticated existing `c_use` RPC,
server `GameServer.cmd_use`, local preview controls and online HUD.
`game/tests/test_acid_neutralizer.gd` is registered in the headless
`game/tests/run_all.gd` regression suite. Existing engine systems
already support the feature; no native Cgame modifications are needed.


## Expedition rally standard — crafted group combat recovery

A party leader can now craft an **Expedition Rally Standard** at a workbench
using **2 plank T1, 2 cloth T1 and 1 scavenged scrap**. Outside the protected
settlement, the leader can raise the standard using the **Raise standard**
button in the online party panel while at least one living ally is nearby.

- Deployment consumes exactly **one carried standard**, only after the
  server confirms accepted party leadership, dry land, nearby teammates,
  no active standard, and deployment cooldown. It cannot be placed for free
  or from an arbitrary client-supplied coordinate.
- For **90 seconds**, current group members within **11 m horizontally**
  and **3 m vertically** gain **+1.4 stamina/second** and **+0.8 combat
  energy/second** on top of existing regeneration. Hunger or thirst at
  20 or below blocks the additional recovery. Sprint/dodge stamina delay
  and fractures prevent additional standard stamina restoration.
  Recovery cannot exceed the normal stamina/combat-energy caps.
- The leader must wait **120 seconds** between standard placements.
  A dead or departed leader immediately cancels the standard.
  The effect disappears on expiry and when the party disbands; it is
  temporary session state, not a permanently persisted ability.
- Only actual party members receive the standard location in their
  authenticated snapshots. The online party HUD displays its remaining
  duration and the north-up tactical radar draws its position and radius;
  outsiders cannot see this private marker or receive its recovery.
- Server tick integration clamps recovery to the real active portion
  of each tick, avoiding overpayment when a temporary marker expires.

Gameplay is implemented in `scripts/shared/rally_standard.gd`,
`scripts/shared/party.gd` and the authoritative game server,
using existing crafting, network, party HUD and radar systems.
`tests/test_rally_standard.gd` is registered in `tests/run_all.gd`
and checks ingredient costs, consent, placement, XP-safe recovery,
cooldowns, stat caps, death cleanup, event privacy and visibility.

Run `godot --headless --path game --script res://tests/run_all.gd`.
No native Cgame engine additions were required for this mechanic.


## Reusable field canteen: coastal freshwater collection

The canonical `game/` now has a **Reusable Field Canteen** (T1 tool)
crafted anywhere from **2 T1 cloth, 3 T1 fiber and 1 T1 wood**.
The same carried canteen can refill indefinitely, but each clean
bottle requires **a real carried charcoal filter** and access to the
shore of a lake in the live world. Exactly one filter is exchanged
for **one ordinary clean water bottle**; the canteen remains in
inventory. Drinking bottled water later uses the existing safe
`water_bottle` behavior, whereas unfiltered direct lake drinking
continues to carry infection risk.

The server runs the refill as an **atomic inventory transaction**:
a temporary backpack copy pays one filter and receives one bottle,
and only a fully fitting result is committed. If the bag is full,
the action returns `no_space` and consumes nothing. The last
filter's emptied stack may free the slot used by the new water.
Missing tool/filter, invalid shoreline, death and spam cannot create
water. No client chooses an output amount, position or filtration
result, and no extra crafting or survival experience is minted.

Refilling shares the existing **12-second lake drink cooldown**.
It is ticked on the server and saved in version-one character
records, so alternating between direct drinking and bottled refills
or reconnecting cannot bypass the limit. Existing character saves
work without any schema migration. The tool and clean water are
ordinary inventory contents and persist with existing save and
death-loot rules.

**Local preview:** `R` drinks from a lake, `Shift+R` uses
an alkali kit, **`Ctrl+R` fills the carried canteen**.

**Multiplayer:** the inventory provides **Refill canteen at shore**
and connected clients also support `Ctrl+R`. New authenticated
`c_refill_canteen` RPC calls the server's
`cmd_refill_canteen`; responses are delivered privately through the
existing results path.

Source: `scripts/shared/field_canteen.gd`, item and crafting
definitions, `GameServer`, `Net`, local/online client, and HUD.
New `game/tests/test_field_canteen.gd`, registered in
`game/tests/run_all.gd`, covers crafting, atomic capacity checks,
freshwater access, the persisted shared cooldown, legacy saves
and replay-safe filter consumption. Existing Cgame engine APIs
are sufficient: no native modifications are needed.


## Raid party ready check (Lineage-style cooperation)

The multiplayer party panel now has **Start ready check**, **I'm ready** and
**Not ready** buttons. Only the group leader may start a 30-second check,
and **every current party member** (including the leader) must explicitly
confirm before the party is marked **all_ready**. One "Not ready" response
ends the check immediately; a finished result remains visible for 10 seconds.
The leader can start another check after an 8-second anti-spam cooldown.

The dedicated server owns the clock, group roster and response identities.
Clients cannot vote on behalf of another peer, reset an active deadline or
expose votes to unrelated players. Changes in membership (including kick,
leave, disconnection and accepting a new member) cancel old votes. Death also cancels readiness, and a check cannot start with a fallen teammate. These
session-only confirmations do not move characters, grant items or launch
combat; they are a coordination tool for voluntary raid starts.

Implementation: `scripts/shared/party.gd`, `scripts/server/game_server.gd`,
`scripts/shared/net.gd`, and the existing online client/HUD.
Headless regressions in `tests/test_party_ready.gd` cover authentication,
deadline behavior, privacy, anti-spam and roster changes. Run:

```sh
godot --headless --path game --script res://tests/run_all.gd
```

Godot's existing RPC, timer and UI APIs are sufficient. No engine patch is
needed for this feature.


## Ruin survey charts — crafted cartography for hostile expeditions

The canonical `game/` includes **Ruin Survey Charts**, a field-crafted
consumable made from **1 T1 cloth, 2 T1 fiber, and 1 scrap**.
Use a chart while alive, on foot, in the wilderness to discover the
**nearest still-unlooted red/black-zone ruin crate within 190 metres**.
The server searches only a bounded 7×7 neighborhood of actual
seed-generated world chunks and checks authoritative opened-crate
state. A successful search consumes **one real chart** and places a
**private 75-second waypoint**. Failed searches (no chart, safe
settlement, no eligible ruin, or an active waypoint) cost nothing.

The chart is **not a teleport, loot grant, threat detector, shared party
map or an automatic reward**: players must travel, survive the infected,
and actually open the found crate under the usual scavenging/loot
rules. Loot quality, rewards, PvP exposure and crate cooldowns are
unchanged. Repeated survey requests cannot farm charts or markers.
The waypoint disappears on expiration, crate opening or survivor
death. It is session-only, does not enter character saves and is never
replicated into other survivors' `you` snapshots—even if they stand
beside the chart owner. Owner packets expose only the marker
coordinates, zone and remaining time; internal crate IDs and
absolute expiry clocks stay server-only.

**Controls:** F3 surveys in both local preview and connected play,
with a dedicated **Survey dangerous ruins** button in the online
inventory. The online HUD shows waypoint coordinates, distance and
remaining lifetime. The tactical radar renders a violet destination
pin within 72 m or a violet edge arrow for distant targets, using
the owner-only marker in both single-player and multiplayer.

Implementation: `scripts/shared/ruin_survey.gd`, `defs.gd`,
`scripts/server/game_server.gd`, authenticated
`scripts/shared/net.gd`, both clients, HUD and radar.
`game/tests/test_ruin_survey.gd` is registered in
`tests/run_all.gd` for crafting cost, deterministic real crate
discovery, open-crate filtering, privacy, anti-replay, death and expiry.
Existing Godot world generation, RPC and UI APIs are sufficient;
no C++ engine changes are required for this mechanic.


## Expedition triage packs — item-paid group field medicine

A survivor group can now craft an **Expedition Triage Pack** at the
workbench with **2 bandages, 1 field antiseptic, 2 cloth T1 and 1
clean water bottle**. The multiplayer party panel has **Triage nearby
allies**, which consumes one actual pack to treat **up to 3 current,
injured party members** within **5.5 metres horizontally** and
**2.5 metres vertically**. This is a teamwork ability; the carrier
cannot treat themselves with the group action.

The dedicated server prioritizes the most urgent injuries (stable
peer-ID tie break) and heals **up to 18 HP** plus reduces bleeding
by **up to 24** for each selected recipient. It cannot cure infection,
remove fractures, revive the dead, or award experience. An **18-second
cooldown** shares the existing medical-aid timer, preventing rapid
stacking with the ordinary single-target bandage ability.

The server authorizes group membership, real positions, live injuries,
resource spending and targets. The client sends no target IDs or
effect values. If there is no eligible wounded companion, if the
medic has no pack, or if the cooldown is active, **nothing is spent**.
One command consumes one pack only after all preconditions pass.
Each treatment event reaches only the medic and recipient, never
strangers or other teammates. The inventory and character state
continue using existing server/Nakama save paths.

Implementation: `scripts/shared/party_triage.gd`, item and recipe
definitions, `GameServer.cmd_party_triage`, authenticated
`Net.c_party_triage` RPC and online client/HUD. The local offline
preview has no party members, so the ability is multiplayer-only.
`tests/test_party_triage.gd` verifies crafting costs, reach,
group privacy, recipient priority, no-duplication, death handling,
no-effect calls and cooldown. It is part of `tests/run_all.gd`:

```sh
godot --headless --path game --script res://tests/run_all.gd
```

Existing Cgame scripting, networking and UI APIs cover the mechanic;
no native engine extension was required.


## Tactical party focus: targeted infected coordination

The multiplayer party panel includes **Focus infected**. A living party
leader marks the **nearest living infected within 24 metres horizontally
and 4 metres vertically**, for **18 seconds**. The dedicated server
selects the target from its actual enemy state: the client cannot
submit an infected ID, position, expiry or damage amount.

- Current teammates see the target ID and remaining duration in their
  private party snapshots. Unrelated survivors never receive the marker.
- Party members within 24 metres and 4 metres vertically of the **exact
  marked infected** deal **8% additional damage to that infected only**.
  Enemy kills and mastery still use existing server-owned combat rules.
  Players, other infected, distant party members, solo survivors and
  expired marks receive **no damage increase**.
- A new focus has a **28-second leader cooldown**. No nearby living
  infected means no new focus or cooldown. An active focus cannot
  be replaced until it expires.
- The mark is removed when the infected is killed, when its timer expires,
  the leader dies, or the party gains/loses a member. Cooldown remains
  intact after early removal, preventing boss focus spam.

Implementation: `scripts/shared/party_focus.gd`,
`scripts/shared/party.gd`, `scripts/server/game_server.gd`,
`scripts/shared/net.gd`, `scripts/client/game_client.gd` and
`scripts/client/hud.gd`. Offline local preview cannot form a party;
this is a multiplayer combat coordination feature.

`tests/test_party_focus.gd` is registered in the headless suite and
covers leadership, temporal expiry, membership changes, server target
selection, private snapshots, range checks, and actual marked/unmarked
damage. Run:

```sh
godot --headless --path game --script res://tests/run_all.gd
```

Existing Godot/Cgame RPCs, RefCounted scripts and HUD widgets suffice;
no native engine modifications were required.


## Raid warlord armor recovery — tactical counterattack after a slam

The existing party raid boss now has a short, fully server-authoritative
**armor-exposure window after its telegraphed ground slam resolves**.
This connects the warning-and-dodge survival loop to a cooperative MMO
counterattack phase without introducing any client-powered ability.

- In the first phase, the living boss is exposed for **4 seconds** after
  the actual area attack resolves. Once enraged, exposure lasts only
  **2.5 seconds**. These are not pauses or stuns: the boss can still
  fight back, and avoiding the circle remains necessary.
- During that window, real server-confirmed player hits against the
  **one currently active raid boss** deal **15% more PvE damage**.
  Ordinary infected, unrelated bosses, player-versus-player damage,
  hits before the slam and attacks after expiry gain nothing.
  Existing party focus is checked independently; all real damage still
  passes through the normal combat, threat, XP and loot pipeline.
- The server resets the temporary exposure on boss death, retreat,
  missing boss cleanup and the next spawn. It is **session-only** and
  cannot be restored by save files, requested by an RPC or fabricated
  from client-supplied timestamps.
- Nearby clients see the precise remaining time in the boss snapshot
  as `raid_exposed_seconds`. The online HUD announces the counterattack
  after the existing `raid_slam` event and shows a short exposure
  countdown. The event remains interest-radius filtered: distant
  players do not receive the raid location.

Implementation: `scripts/shared/raid_recovery.gd`,
`scripts/server/game_server.gd`, `scripts/client/hud.gd`.
The new `tests/test_raid_recovery.gd` suite is registered in
`tests/run_all.gd` and covers phase durations, telegraphs, combat,
dead/normal infected, snapshot privacy, expiration, and death cleanup.

```sh
godot --headless --path game --script res://tests/run_all.gd
```

Existing Godot gameplay scripting and networking already support
this feature; no native engine patches were necessary.


## Telegraphed directional raid cleave — sidestep the warlord

The canonical multiplayer raid boss now periodically performs a
**directional frontal cleave** alongside its existing circle slam and
post-slam counterattack opportunity. Players must read the boss facing,
sidestep or circle behind it rather than simply running away.

- The raid server first selects a **living current target within 13 m**
  and fixes the boss's world position and a normalized attack direction
  for the entire **2.2-second telegraph**. Changing aggro during windup
  does **not** secretly rotate the attack toward another player.
- The sector extends **13 m**, **38 degrees to either side** of the
  locked direction, and at most **3.5 m vertically**. An ordinary-phase
  hit causes **24 base damage**; enrage increases it to **33**.
  Existing armor, guardian brace, timed dodge invulnerability, death
  handling and safe-zone rules remain authoritative.
- Directional attacks have a **22-second cooldown** normally, dropping
  to **15 seconds during enrage**. The server schedules either a
  circular slam or a directional cleave, never both telegraphs at the
  same time in normal play. The cone does **not** trigger the extra
  damage vulnerability reserved for completed slam attacks.
- Nearby multiplayer clients receive a bounded
  `raid_cone_telegraph` containing the fixed origin, direction,
  sector geometry and server deadline. The **tactical radar paints a
  red sector**, and the HUD displays the remaining warning and whether
  the local survivor stands inside it. Distant clients receive neither
  the attack position nor the full raid event.
- Pending strikes are session-only and are discarded if the boss dies,
  retreats or the encounter is reset. Clients cannot spawn a strike,
  select victims, alter damage or submit an aim direction.

Files: `scripts/shared/raid_cone.gd`,
`scripts/server/game_server.gd`, `scripts/shared/net.gd`,
`scripts/client/game_client.gd`, `scripts/client/hud.gd` and
`scripts/client/survival_radar.gd`. The new
`tests/test_raid_cone.gd` is included in `tests/run_all.gd`
and covers sector geometry, server authorization, locked aim, windup,
dodge, cooldowns, enrage, interest-limited snapshots, PvE hit
resolution and retreat cleanup.

```sh
godot --headless --path game --script res://tests/run_all.gd
```

The engine's existing scene drawing, RPC, and physics coordinate APIs
support this feature. No native engine changes were needed.


## Optional raid loot round robin — MMORPG group reward fairness

The party leader may toggle **Raid loot: Free / Round robin** in the
multiplayer party controls. **Free** is the default and preserves the
original single-bag, first-pickup raid flow. The setting affects only
**future** boss kills and is shared in the party's private state.

When the server confirms a raid boss death, it first freezes the real
eligible combat contributors using the existing 75-second loot
reservation. If at least two contributors belong to a party with
Round robin enabled, the server initializes a single rotation on the
**one actual shared loot bag**. Switching the leader's mode afterward
never rewrites an already-dropped bag.

- The initial turn rotates deterministically by boss identity instead
  of always granting the killing player first pick. Only contributors
  can collect while the 75-second boss reservation is active.
- A successful click grants **one item type**, with a quantity capped
  to **ceil(original stack size / number of contributors)**. Every
  awarded unit is subtracted from the original bag inventory;
  no parallel personal reward inventories or duplicate copies exist.
- A successful claim advances to the next contributor. If the
  inventory cannot hold any of the offered items, nothing is taken
  and the turn is **not** consumed. Unused turns expire after
  **12 seconds**, allowing active survivors to keep collecting.
- A private per-viewer snapshot shows whether it is your turn and
  how many seconds remain, without revealing participant account
  identifiers to strangers or other clients. The network RPC
  authorizes only the leader's future loot-mode choice.
- After the existing **75-second reservation expires**, any survivor
  can collect the remaining bag normally. Regular infected,
  ordinary containers, PvP full-loot bags, nonparticipating groups
  and solo boss kills retain their previous behavior.

Implementation: `scripts/shared/raid_round_robin.gd`,
`scripts/shared/party.gd`, `scripts/server/game_server.gd`,
`scripts/shared/net.gd`, `scripts/client/game_client.gd`,
`scripts/client/hud.gd`. The new
`tests/test_raid_round_robin.gd` covers leader permissions,
free-mode compatibility, shared bag deductions, turn switching,
replay protection, private visibility and public loot unlock.

```sh
godot --headless --path game --script res://tests/run_all.gd
```

The current Godot networking, inventory and UI APIs support the
mechanic without changes to the native engine.


## Raid trophy Need/Greed voting

The multiplayer party leader can cycle the future raid loot mode through
**Free → Round robin → Need/Greed**, without changing rewards that have
already dropped. Free remains the default for old solo and group gameplay.

For a raid boss killed by a party with at least **two actual combat
contributors**, Need/Greed opens a **25-second private ballot** for the
`infected_core` trophy stack in the **one existing shared reward bag**.
Other drops (silver, metal bars, bandages) remain collectable immediately
by the same eligible raid contributors.

- Eligible survivors who took part in the boss fight each choose
  **Need**, **Greed** or **Pass** once. Votes cannot be changed or replayed.
  The server validates the authenticated sender, their account/session
  identity, live position within 28 m, participation frozen at the
  boss kill, the bag ID, the deadline and the selected action.
- **Need** rolls win over all **Greed** rolls, even with a lower die
  value. Within the winning category, the server chooses the highest
  deterministic **d100** roll, with a stable identity tiebreaker.
  Unsubmitted votes become Pass after 25 seconds; all completed votes
  end the election immediately.
- The winner gets the exclusive right to pick up the **original
  Infected Core stack** before the normal 75-second raid entitlement
  expires. The winner does not receive an item remotely; they must
  reach the original bag and have sufficient backpack space.
  If everyone passes, eligible contributors can claim the cores under
  the existing raid reservation rules.
- The server never makes extra bags, personal copies, or new items.
  Only a normal successful pickup decrements the original bag inventory.
  The legacy 75-second reservation still protects the bag from
  outsiders; after it expires, all leftovers become public.
- Network snapshots show a player only their own choice, total votes,
  remaining duration, vote status, and whether **they** won.
  Account/session tokens, full ballots and other players' rolls
  remain server-only. Nearby eligible players see three vote buttons
  and their result in the group/inventory panel.

Implementation: `scripts/shared/raid_need_greed.gd`,
`scripts/shared/party.gd`, `scripts/server/game_server.gd`,
`scripts/shared/net.gd`, `scripts/client/game_client.gd`,
`scripts/client/hud.gd`. New
`tests/test_raid_need_greed.gd` covers authorization, Need > Greed,
replay safety, private snapshots, bag-item conservation, mode freezing,
all-pass release, deadline expiry and the existing free pickup mode.

```sh
godot --headless --path game --script res://tests/run_all.gd
```

This feature uses the project's current Godot scripts, RPCs and
inventory implementation; no native engine modifications are necessary.

## Salvaged Whetstone: classless melee preparation

At the workbench craft a **Salvaged Whetstone** from **2 Stone T1 + 1 Scrap**.
Equip any carried melee weapon and press **End** in the offline or
online client, outside combat. The next three **confirmed ordinary melee hits
against infected** deal 15% more damage. Misses and player-versus-player
attacks never receive or spend infected-only charges. Equipment active skills
remain unchanged. Reapplying with unused charges is rejected without spending
an item. Switching or losing the weapon, dying, or respawning cancels the
preparation. The server owns the cost, damage and charges; the client only
renders the remaining hit counter.

Strict validation persists remaining charges and the tied weapon in existing
version-1 character saves; older saves default to no preparation. A dedicated
`game/tests/test_field_whetstone.gd` suite is included in `run_all.gd`.
No native engine change is needed: this uses existing inventory, simulation
and RPC infrastructure.

## Field Armor Plate: defensive preparation for infected melee

At the workbench, craft a **Field Armor Plate** from 1 Metal Bar T1,
2 Cloth T1 and 2 Scrap. Equip owned body armor and press **Insert**
(in either the offline or online client) while out of combat. A plate is
consumed only on successful preparation. The next three confirmed ordinary
infected melee/claw attacks have their **health damage reduced by 20%** after
normal armor and parry mitigation. Dodges do not consume charges; PvP,
spitter acid, raid-boss attacks and environmental hazards are unaffected.
Existing infection, bleeding and fracture mechanics remain unchanged.

The server binds all charges to an owned equipped armor item. Reapplying while
prepared is rejected, and switching/loss of the armor, death or respawn clears
the remaining charges. The exact armor ID and remaining hits are validated
and saved with version-1 account data; older saves default to an empty plate.
`game/tests/test_field_armor_plate.gd` exercises those invariants.
No Godot/Cgame engine extension is needed.


## Raid threat awareness for party roles

During raid fights, the existing tank/guardian threat, healer threat
and infected hate-list mechanics now feed a **read-only, party-private
boss aggro advisory** on each nearby survivor's HUD.

- Only a living, currently active raid boss can produce this status.
  The receiving survivor must be a **living party member** in the
  same dangerous zone and within **42 metres** of the boss, with a
  vertical difference of at most **7 metres**. The group must have at
  least two members and have already engaged the boss.
- The HUD identifies the boss's current **actual target** if that
  target belongs to the survivor's party. Another party's target ID
  is never sent. When the guardian is the target, members see a
  **TAUNT LOCK** countdown taken from the server's real forced-target
  timer.
- **Your threat, % of party peak** compares personal threat with the
  highest actual party contribution to the boss's hate list.
  Non-tanks also see the percentage of the **aggro-switch threshold**
  required to pull the boss (the engine's existing 125% hysteresis).
  A warning appears close to that threshold. Tanking abilities and
  damage remain entirely server-authoritative.
- Only the requesting player's private `you.raid_aggro` snapshot
  contains this bounded advisory. Public `zombies` snapshots,
  outsider views, enemy player views and disconnected accounts never
  carry raw hate tables, account IDs or another group's targets.
  Stale targets, dead raid bosses, distant participants and invalid
  numerical threat values produce no misleading data.

Files: `scripts/shared/raid_aggro_view.gd`,
`scripts/server/game_server.gd`, `scripts/client/hud.gd`.
Tests in `tests/test_raid_aggro_view.gd` are registered in the main
`tests/run_all.gd` suite, covering private visibility, healer aggro,
guardian forced targeting, 125% swap threshold, danger-zone and
distance checks, corrupt values and boss-death cleanup.

```sh
godot --headless --path game --script res://tests/run_all.gd
```

No native Godot engine changes are required: existing server authority
and replicated private character state support this system.

## Soft-Sole Trail Wraps: tactical footstep muffling

Field-craft **Soft-Sole Trail Wraps** using 2 Cloth T1, 2 Fiber T1 and
1 Scrap. While on foot and out of combat, use **Shift+/** (ordinary
**/** still applies herbal scent salve) to consume one bundle for **90s**.
The server reduces the *new* sprint noise radius to 55% of its ordinary
value; it never silences an already audible sprint/gunshot, mounted bike
noise, attack noise, gathering, blood scent or line of sight. Sprinting
still breaks camouflage and costs stamina. The effect is private, saved
and time-decrements on the authoritative server, never refreshes by
relogging, and clears on death/respawn. Legacy saves remain compatible.

Test suite: `game/tests/test_soft_sole_wraps.gd`.
No Godot/Cgame engine changes are required.


## Guardian Intercept: protect a party ally from a melee strike

Frontline guardians now have a second cooperative ability alongside
infected Taunt/Brace. From the survivor party HUD, select a **real
nearby party ally** and press **Guard ally (one PvE hit)**. The server
verifies that the guardian is alive, not riding, in a dangerous zone,
wearing an **owned equipped melee weapon**, and within **4.5 metres**
and **3 metres vertically** of the living target in the same party.

- A successful cast spends **20 combat energy** and arms a **9-second
  defensive link** on the selected teammate, with a **28-second
  cooldown**. Failed requests spend no energy and do not start a
  cooldown. Only one active link can be held per guardian.
- On the **next genuine infected melee hit** that would land on the
  teammate, the server consumes one link, prevents that hit's health
  damage and its bleeding/infection/fracture injuries on the warded
  ally, and redirects **65% of the original hit's base damage**
  to the guardian. The guardian's real equipped armor, combat toughness
  and any active valid brace still reduce that redirected damage.
  The guardian can die saving their teammate: the full normal death,
  loot and respawn rules still apply.
- Normal dodge immunity takes priority, so an already-dodged hit
  does not consume a link. Ordinary melee parries proceed only if
  the hit was not intercepted. Acid pools, spitter projectiles,
  raid slam/cleave AoE, hunger, weather, and **player versus player**
  damage are deliberately **not** intercepted.
- At hit time the server **rechecks** that the guardian is still
  living, equipped, in the same actual party and within range.
  Switching weapons, mounting, leaving the group, death, timer
  expiry, or disconnection invalidates the link, including across
  peer ID reuse. Links are session-only and never persisted or
  copied into character saves.
- Private snapshots show remaining duration, cooldown, and the
  local player's protected/protecting status. A successful intercept
  emits a private event **only** to the guardian and warded ally;
  strangers do not receive this information.
- All hit positions and damage are computed by the real zombie
  simulation. Clients send only their requested ally ID, not a
  damage value, enemy ID, victim status or intercept outcome.

Implementation: `scripts/shared/guardian_intercept.gd`,
`scripts/server/game_server.gd`, `scripts/shared/net.gd`,
`scripts/client/game_client.gd`, and `scripts/client/hud.gd`.
`tests/test_guardian_intercept.gd` is registered in the canonical
`tests/run_all.gd` and tests actual zombie melee simulation,
replay protection, energy, safe-zone/range/height/weapon validation,
one-hit settlement, authoritative countdowns, private event routing,
party changes, death and respawn.

```sh
godot --headless --path game --script res://tests/run_all.gd
```

This mechanic uses existing GDScript, scene UI, multiplayer RPCs and
the server's current combat pipeline; no native engine extension
is needed.


## Guardian Retribution — shield interception into a counterstrike

Guardian Intercept now has a short, high-commitment **retaliatory
follow-up** that links party survival to MMORPG tank aggro control.
The guardian must first activate a legitimate ally guard link and
actually block an infected's melee strike. Neither the player nor a
client RPC can arm this follow-up directly.

- Once the server confirms the rescued ally's actual infected melee
  hit, **the same infected challenges the guardian for 1.5 seconds**.
  The challenge follows the existing bounded Zombie force-taunt logic
  and threat table; fleeing outside its leash or entering safety ends
  the forced focus normally.
- A living, still-equipped guardian earns **4 seconds** to land **one
  basic melee counterattack** against **that exact attacking infected**.
  The server applies **+25% PvE damage** after the ordinary weapon,
  mastery and combat bonuses. There is no extra free click: the player
  must aim and physically hit using the normal authoritative melee
  hit test and cooldown.
- The **first normal melee swing consumes the mark even on a miss,
  a wrong target or a PvP hit**, so timing and positioning matter.
  Ranged shots, area skill activations, phantom equipment and
  unrelated infected cannot claim this bonus.
- Changing or losing the original melee weapon, leaving the group,
  dying, riding, disconnecting, the marked infected dying or the
  4-second expiration removes the counter. The marked target and
  timer are **session-only**, never written to character saves.
- A private per-player `you.guardian_counter_seconds` and
  `you.guardian_counter_target` snapshot drives the tactical
  **GUARD COUNTER READY** HUD message. A successful retaliation emits
  one event visible only to the guardian. Public zombie snapshots
  never contain another player's mark.
- Ordinary PvP and the existing boss AoE, spitter acid and survival
  damage pipelines remain unchanged; only a confirmed basic infected
  melee hit can start this reaction.

Implementation: `scripts/shared/guardian_retribution.gd`,
`scripts/server/game_server.gd`, `scripts/shared/net.gd` and
`scripts/client/hud.gd`. Tests in
`tests/test_guardian_retribution.gd` cover a real zombie intercept,
short aggro transfer, one basic counter, misses, duplicate attempts,
weapon loss, party disbanding, expiry, death/respawn, invalid numbers
and private network visibility.

```sh
godot --headless --path game --script res://tests/run_all.gd
```

Current Godot combat, scene UI and multiplayer APIs are sufficient;
this requires no native engine modifications.


## Coordinated party flanking (engaged infected)

A new spatial party-combat rule rewards deliberately taking positions
around enemies, drawing from MMORPG tank/damage roles without removing
Days After's gear-based combat or Albion's open-world risk.

When a **living group tank holds a real infected target in CHASE or
ATTACK state**, a teammate using a physically equipped **melee weapon**
can move behind that infected and land an **ordinary basic melee
strike** with a positional damage bonus. Unlike the existing crouched
stealth ambush, this works **during active combat**, not on idle or
unaware enemies:

- **+18% damage** to ordinary infected and elites, and **+10%** to
  an active raid boss. Bonuses apply only to a server-confirmed basic
  melee collision against an actual zombie; not bows, guns, skills,
  area attacks, direct scripted damage or PvP.
- The infected must be **actively pursuing a different living member
  of the attacker's current group**, with that frontline player
  within **10 m** of the enemy. The flanker must be within **3.2 m**,
  on the opposite side of the zombie (direction dot ≤ −0.55).
  Both teammates must be within **3 m vertically** of the infected,
  in the same active danger zone, and not inside a safe hub.
- The server computes the actual enemy target, party membership,
  weapon ownership, positions, health and engagement state at the
  moment of the hit. Moving out of position, losing gear, mounting,
  switching the infected's aggro, or disbanding the group instantly
  disables the bonus. Players cannot supply a multiplier or enemy
  target ID over RPC.
- The private `you.party_flank_hint` snapshot shows a single nearby
  **FLANK OPEN** opportunity for the local survivor, including the
  expected 10%/18% bonus. The normal public zombie list does **not**
  expose private hate lists or allied targets.
- Each actual bonus hit emits a **party_flank** notification to
  the authenticated attacking player only. Standard combat, threat,
  loot ownership, combat training and survival injury rules remain
  unchanged. Existing stealth rear-openers cannot overlap with an
  enemy actively chasing a frontline party member.

Implementation: `scripts/shared/party_flank.gd`,
`scripts/server/game_server.gd`, `scripts/shared/net.gd`,
`scripts/client/hud.gd`. Registered regression suite
`tests/test_party_flank.gd` covers geometry, true target ownership,
live zombie AI state, ranges, invalid coordinates, gear, mounting,
privacy, actual melee-hit integration, damage paths, boss scaling and
party changes.

```sh
godot --headless --path game --script res://tests/run_all.gd
```

No native Godot engine modifications are necessary; the existing
authoritative combat simulation and private snapshots support it.


## Raid tempo: extra loot for a fast boss kill

A dangerous-zone party raid now has two **server-authoritative** finish
tiers: defeating the current boss within **90 seconds** grants gold tempo
(+2 infected cores and +25 silver per zone tier); within **150 seconds**
grants silver tempo (+1 infected core and +12 silver per zone tier).
A slower victory still receives the original boss loot. The reward is
placed into the **same shared boss bag**, so all existing reservation and
need/greed rules apply without a second claim path or new network RPC.
The existing nearby `raid_defeated` event carries an optional
`tempo_rank` field. The server rejects invalid clocks, unrelated brutes,
and bogus safe-zone tiers; kills cannot be replayed to generate more bags.

Regression suite: `game/tests/test_raid_tempo.gd`, included in
`game/tests/run_all.gd`. Tests require a Godot/Cgame runtime.


## Guardian Shield Wall (party damage mitigation)

Classless survivor guardians can now protect nearby teammates with a
brief, active **Shield Wall** formation. Use the new **Shield Wall
(party melee)** button beside Guardian Taunt and Guard Ally in the
inventory/party combat controls. The shield is always activated
through an authenticated RPC: clients never choose affected teammates,
damage values, distances, or shield durations.

- A living guardian on foot must belong to an actual party with
  **at least one nearby living ally** in a dangerous zone and have an
  **owned equipped melee weapon**. They spend **30 combat energy**
  to create a nonpersistent **6-second** protective stance with a
  **32-second** cooldown. Invalid attempts spend no energy.
- Living nearby party allies within **5.5 metres**, on the same
  danger-zone map and within **3 metres vertically**, take **22%
  less physical damage** from ordinary infected melee attacks. A
  raid boss's direct claw is mitigated by **12%** instead.
  The guardian themselves receive **no additional reduction**:
  existing personal Guardian Brace and single-hit Intercept continue
  to cover their own defensive roles.
- The shield is applied **after the existing equipped-gear mitigation,
  Guardian Brace, timed Parry, and any legitimate field armor plate**.
  It does not prevent infection, bleeding or fracture wounds by
  itself. Those remain governed by the existing armor and
  Warden Aura systems.
- The server validates current party membership, real equipment,
  living status, mounting, location, range, height and safety **at
  every melee hit**. Moving away, changing gear, entering safety,
  losing party membership or dying removes its benefit instantly.
  Multiple active guardians can protect the same ally, but **only one
  shield applies**: the nearest eligible guardian is selected, with
  a stable peer-ID tie break. No multiplicative stacking.
- This ability **never** runs from PvP damage, firearm damage, raid
  cone/slam AoE, spitter acid, weather, hunger or infection ticks.
  It produces no free healing, gear, rewards, or threat.
- Each survivor's private `you.shield_wall_seconds`,
  `you.shield_wall_cooldown`, `you.shield_wall_guarded_seconds`
  and `you.shield_wall_guarded_by` snapshot drives a personal HUD
  countdown. A real mitigated hit emits a
  `party_shield_wall_block` event visible **only** to the guardian
  and the protected ally. Nearby strangers receive no private
  group status or mitigation events.
- The live aura clears on death or respawn, but respawning does not
  reset a pending cooldown. The state is session-only, not saved
  to the character record.

Implementation: `scripts/shared/party_shield_wall.gd`,
`scripts/server/game_server.gd`, `scripts/shared/net.gd`,
`scripts/client/game_client.gd` and `scripts/client/hud.gd`.
Tests in `tests/test_party_shield_wall.gd` are registered in
`tests/run_all.gd` and exercise actual zombie hits, energy,
short cooldowns, nonstacking auras, safe zones, equipment, elevation,
team membership, private network events, death/respawn and the lower
raid reduction.

```sh
godot --headless --path game --script res://tests/run_all.gd
```

This uses the game's existing GDScript combat, multiplayer RPCs and
private state snapshots. It needs no native Godot engine changes.


## Medic Cover: emergency threat handoff to a party guardian

Healing can attract infected toward medics because the game has real
server-side healer hate generation. A classless **Medic Cover**
ability now gives a restoration-staff medic a tactical rescue option
when surrounded by infected. The medic presses **Medic Cover
(staff + guardian)** in the party/inventory combat controls.

- Requires a **physically equipped restoration staff**, a living
  nonmounted medic outside the safe hub, and an **equipped melee
  guardian** in the same real party within **8 metres** and no more
  than **3 metres elevation difference**. A second restoration staff
  does not qualify as a melee guardian. No targets, positions, hate
  values or damage are accepted from clients.
- A successful request spends **24 combat energy**, applies a
  **30-second** per-character server cooldown and redirects up to
  **3 already-engaged normal infected** to the closest eligible
  guardian (stable peer-ID tie-break). Each transferred infected
  focuses the guardian for **2 seconds** using the existing
  `Zombie.force_taunt` logic and its normal bounded hate entries.
- Only infected that are currently chasing/attacking the medic or
  have positive, real hate against that medic qualify. Enemies must
  be within **16 metres and their own pursuit leash** of both
  the medic and guardian, in the same dangerous zone and within
  **3 metres vertically**. Idle infected, unrelated players' mobs,
  raid bosses and enemies already focused by another guardian's
  forced taunt are unaffected.
- Upon real transfer, the medic's **existing** hate on that infected
  is reduced to **35%**, not wiped out, ensuring a careless healer
  can still pull aggro again. No heal, loot, XP, summon or free enemy
  spawn is created. The group still must survive the encounter.
- If there is no legitimate guardian or qualifying infected, the
  command refuses **without energy or cooldown charge**. Fast repeat
  requests are blocked by the server. The timer is session-only,
  advances in regular player ticks, and is displayed privately as
  `you.medic_cover_cooldown` on the medic's HUD.
- A **medic_cover** summary event is delivered only to the requesting
  medic and the actual guardian. Neither individual infected IDs
  nor raw threat dictionaries are sent to any client. Ordinary
  PvP damage, loot, gear, wounds and rewards are unchanged.

Implemented in `scripts/shared/medic_cover.gd`,
`scripts/server/game_server.gd`, `scripts/shared/net.gd`,
`scripts/client/game_client.gd`, and `scripts/client/hud.gd`.
Regression cases in `tests/test_medic_cover.gd` cover real Zombie
target selection, existing healer threat reductions, guardian equipment
and party roles, 3-enemy limit, idle/boss/third-party immunity, invalid
geometry, failed casts, rate-limiting, event privacy and death.

```sh
godot --headless --path game --script res://tests/run_all.gd
```

No native engine changes needed; this uses authoritative current
GDScript combat, group rosters and reliable multiplayer RPCs.


## Raid guard ward: team coordination during boss waves

The existing dangerous-zone boss receives temporary protection from **living
server-spawned raid reinforcements**. Every actual surviving raid guard reduces
incoming boss damage by **12%**, with a strict **24% cap**; killing guards
restores normal boss damage. The mechanic works during both one-time waves,
and any survivors from wave one still count after wave two begins. The server
derives guard identities and health itself; neither client actions nor normal
zombies can forge this protection. It is removed on boss victory or timeout.

Nearby online clients see the number of remaining guards and mitigation in the
existing raid HUD, derived from the authoritative enemy snapshot. The local
preview also shows this information when the boss is nearby. New
`raid_ward_changed` events announce real guard deaths only within the
existing interest radius. No new RPC, save migration, or engine-level API is
required. The combat, snapshot, event-filtering, and replay tests live in
`game/tests/test_raid_ward.gd`, included in `game/tests/run_all.gd`.

Run the test suite using:
```sh
godot --headless --path game --script res://tests/run_all.gd
```

## Native directional EQS tactical flanking

On Cgame builds with the optional `EnvironmentQuery3D` direction-dot filter,
regular infected rank flanking points on the sides or far side of a moving
survivor rather than choosing the nearest oncoming point. The test is
independent of the movement origin, uses the XZ plane, and is computed only on
an existing cached tactical replan. This is a server-owned position decision;
it does not add client commands or change attack validation. Legacy binaries
use their previous ring scoring; stock Godot still uses direct chase.

Regression: `game/tests/test_zombie_ai.gd` and
`tests/scene/test_environment_query_3d.cpp`.
