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
