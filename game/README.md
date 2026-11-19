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

## Protected settlement bank

The main online game now has an account-bound **48-slot protected stash** at
the Haven workbench near world coordinate (9, 0). Open the inventory with
**I** or **Tab**: right-click an item in the carried inventory to deposit
one, or click a stored stack in the stash area to withdraw one. The client
submits requests but **the server** verifies actual distance, valid item,
stack count, destination capacity and possession. Failed transfers are
non-mutating. Banking the last equipped weapon/armor unequips it.

Items left in the stash are **not dropped on death** in the PvP/loot zones;
carried inventory still drops normally. The server includes stash data in
private snapshots only when changed, never in nearby-player snapshots.
With a configured Nakama backend, the stash travels with the account's
existing version-1 character record and older records load an empty stash.
In offline server mode there is **no durable account storage** between
server restarts: this is not a new persistence service.

This uses existing Godot networking and inventory APIs; it does not
require changes in the Cgame C++ engine.

## Tests

```sh
godot --headless --path game --import                                     # once, builds the class cache
godot --headless --path game --script res://tests/run_all.gd              # rules, world, AI, server (no network)
game/tests/e2e/run_e2e.sh path/to/godot                                    # real server + 3 bot processes
game/tests/e2e/run_e2e_nakama.sh path/to/godot                             # needs Nakama: sign-in, save, return
godot --headless --path game --script res://tests/test_nakama_backend.gd   # Nakama RPC security and storage
```
