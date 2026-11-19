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

Controls: G build, H repair (outside hub); B opens the protected bank. WASD movement, Shift sprint, E gather, Q loot, F attack,
Tab choose recipe, C craft, 1 food, 2 water, 3 bandage,
4 equip club, 5 equip jacket, R drink from natural water.

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

## Settlement trader (server-authoritative fixed-price NPC)

At the workbench inside the safe hub, survivors can sell wood, stone,
ore, fiber and scrap for carried silver, or buy water, canned food and
bandages. Fixed offers are defined in `scripts/shared/market.gd`; the server
validates position, stock, quantity limits and inventory capacity. A failed
trade rolls back all item transfers. Carried silver is lost with full-loot
death, unless stored in the protected stash.

The test suite covers all offer rules, distance checks, buy/sell amounts,
capacity rollback and dead-player rejection using `tests/test_market.gd`.
This is an NPC vendor, not yet a player auction market.

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


