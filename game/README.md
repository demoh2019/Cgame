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
4 equip club, 5 equip jacket, R drink from natural water,
**B** build barricade and **H** repair the one in front of you.
The workbench is near world coordinates x=9, z=0. Leave the safe hub
to collect resources; higher-tier nodes require higher-tier tools.

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
