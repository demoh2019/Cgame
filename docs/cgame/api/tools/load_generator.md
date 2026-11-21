# load_generator.gd

> Deterministic multiplayer load generator for the authoritative GameServer.

`res://scripts/tools/load_generator.gd`

## Overview

Deterministic multiplayer load generator for the authoritative GameServer.

Drives N scripted bots (wanderer, pvp_brawler, pve_hunter, gatherer, trader) through the same
server API a network gateway uses (add_player / submit_input / cmd_* / tick) and measures:
per-tick server time percentiles, events per tick, alive players, zombie count, command
outcomes per reason, and static-memory samples for leak-trend detection.

Method notes (ideas only, no code taken): fixed-step simulated clients with seeded per-bot RNG
as in common game-server soak harnesses; leak detection by ordinary least-squares slope over
periodic memory samples. Original implementation, MIT-compatible, no third-party code.

Scenario: {bots, mix: {behaviour: weight}, duration_s, tick_rate, area: "pvp"|"pve"|"safe"|"mixed", seed}

## Constants

- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const GameServer = preload("res://scripts/server/game_server.gd")`
- `const BEHAVIOURS: Array[String] = ["wanderer", "pvp_brawler", "pve_hunter", "gatherer", "trader"]`
- `const DECISION_INTERVAL_S := 0.25`
- `const MEMORY_SAMPLE_INTERVAL_S := 1.0`
- `const FIRST_PEER_ID := 1000`

## Functions

### `preset`

```gdscript
static func preset(name: String, overrides: Dictionary = {}) -> Dictionary
```

Named scenario presets. Overrides are merged on top.

### `find_spot`

```gdscript
static func find_spot(world, want_pvp: bool, zone_exact: int, angle: float) -> Vector2
```

Finds a spot at the given world-zone class by scanning rings. pvp: zone >= 2, safe: zone 0.

### `run`

```gdscript
func run(scenario: Dictionary) -> Dictionary
```

### `memory_slope`

```gdscript
static func memory_slope(samples: Array) -> float
```

Ordinary least-squares slope (bytes per simulated second) of memory samples; 0 with < 2 samples.

_17 private function(s) starting with `_` are not listed._
