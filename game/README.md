# Albion After

One game from two: Albion Online's tiers, zones, gathering, crafting and full loot, and Days After's
scavenging, hunger/thirst and zombies. Isometric 3D, persistent world, dedicated server.

## What is ready-made and what is ours

| Concern | Used |
|---|---|
| Accounts, sessions, character storage, leaderboard, (chat, guilds, friends, market to come) | **Nakama** (Heroic Labs, Docker, Lua module `backend/modules/albion.lua`) with the official `nakama-godot` client in `addons/` |
| Transport, RPC, ENet | Godot high-level multiplayer |
| Terrain, streaming, LOD | the engine's own `HeightmapTerrain3D`, `WorldStreamer` (+ `chunk_generator`) from this fork |
| Real-time world: movement, zombies, loot | headless Godot server (`scripts/server/`), because a 20 Hz 3D world with AI does not belong in a Lua match handler |

## Run

```sh
docker compose -f game/backend/docker-compose.yml up -d        # Nakama on :7350 (console :7351)
godot --headless --path game --script res://scripts/server/server_main.gd -- --nakama 127.0.0.1:7350
godot --path game -- --connect --server 127.0.0.1:24565 --name You
```

Without `--nakama` the server runs offline (no accounts, nothing saved), which is what the tests use.

## Tests

```sh
godot --headless --path game --import                                     # once, builds the class cache
godot --headless --path game --script res://tests/run_all.gd              # rules, world, AI, server (no network)
game/tests/e2e/run_e2e.sh path/to/godot                                    # real server + 3 bot processes
game/tests/e2e/run_e2e_nakama.sh path/to/godot                             # needs Nakama: sign-in, save, return
godot --headless --path game --script res://tests/test_nakama_backend.gd   # Nakama RPC security and storage
```

## Infected wounds and field medicine (original gameplay rules)

The authoritative headless server now applies fictional infection severity on
zombie melee hits: walkers +14, runners +12, brutes +25, capped at 100.
At 50 or more, infection causes 1.25 health damage per second. It naturally
decays by 0.02 per second. While symptomatic, passive health recovery stops.

Craft an **antiseptic** with **one cloth T1 + one water bottle** (no workbench);
using it removes 55 infection points. The server rejects consumption if already
healthy. Infection is included in the player's authoritative snapshot (the HUD
shows a fourth bar) and persists in the existing version-1 character data.
Older records without this field load with zero infection, while invalid
values are rejected before any player state is mutated.

Run `godot --headless --path game --script res://tests/run_all.gd` to execute
the shared infection and server transaction regression tests. The condition
is a fictional game mechanic, not a model of real infectious diseases.
