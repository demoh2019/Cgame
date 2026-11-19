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
The workbench is near world coordinates x=9, z=0. Leave the safe hub
to collect resources; higher-tier nodes require higher-tier tools.

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

## Safe-hub vendor: loot, gather, trade, survive

The **canonical** `game/` online game now has a simple NPC trade service at
the existing **workbench** (near `x=9, z=0`). The trusted Godot simulation
verifies the actual player location before applying any trade. This is not a
player-driven marketplace yet.

- **Sell to vendor:** scavenged `scrap` (3 silver per unit), T1 wood/stone/fiber
  (2 silver), T1 ore (3 silver); sale prices for T2–T4 resources scale by tier.
- **Buy supplies:** water bottle (12 silver), canned food (18 silver),
  bandage (16 silver).
- The **offline local preview** supports **B** (buy one water bottle) and
  **V** (sell one scrap, otherwise one T1 wood) near the hub workbench.
- The **networked client** exposes buy/sell buttons on its **I** inventory
  panel (water, food, scrap and wood). The same server RPC handles both clients.
- Server rules require a living player near the hub, a listed item and
  an amount between 1 and 50. Prices are chosen server-side, never supplied
  by clients. There is no arbitrage loop between the buy and sell catalogs.
- Trades are **all-or-nothing**: a copy of the backpack is debited, checked
  for enough silver, items and free stack/slot capacity, then committed.
  Rejected operations cannot mint silver or consume the input items.
- Successful trades flag both inventory synchronization and persistent
  Nakama character state. Silver lives in the existing inventory, and the
  existing full-loot danger rules still apply outside protected storage.

The vendor is game logic, not a missing Cgame engine API; no C++ engine
modification was necessary. Later, extend this into player-created market
orders, regional fees and server-authoritative guild supply lines.

### Regression

```sh
godot --headless --path game --script res://tests/run_all.gd
```

`test_vendor.gd` covers price tables, invalid inputs, wallet and stack
rollback, repeat sales, location restrictions, death restrictions and
server-side inventory dirtiness. Run the dedicated GitHub Actions vendor
workflow plus the game build before considering the feature production-ready.
