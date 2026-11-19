# Albion After — main game

**This is the canonical game project at `game/`.** All new gameplay
features belong here; demos under `demo/` and `games/` are prototypes.

An original post-apocalyptic survival sandbox RPG: infected enemies,
scavenging, hunger/thirst, safe hub and dangerous zones, tiered resource
gathering, crafting/refining, equipment-based combat, full-loot risks outside
the hub, and a server-authoritative simulation. Genre ideas are used without
copying proprietary assets or content from other titles.

## Run playable local preview

Open `game/project.godot` with a compiled Cgame editor or start:

```bash
godot --path game
```

This launches `scripts/client/client_main.tscn`. The local preview
reuses `GameServer` for the actual gameplay rules, so movement, crafting,
combat and survival do not have a separate client-side implementation.
The camera, environment, streaming terrain and entities use native Godot/Cgame
rendering. This **local preview is not multiplayer**; remote networking and
account persistence must be wired into this scene before claiming an MMO.

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
