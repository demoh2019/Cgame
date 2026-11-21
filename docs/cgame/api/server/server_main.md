# server_main.gd

> Dedicated server.

`res://scripts/server/server_main.gd`

## Overview

```text
Dedicated server. Run headless:
  godot --headless --path game --script res://scripts/server/server_main.gd -- --port 24565 --seed 1337
Add --debug-commands to allow the test hooks.
```

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const NetTimeouts = preload("res://scripts/shared/net_timeouts.gd")`
- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const GameServer = preload("res://scripts/server/game_server.gd")`
- `const ServerTickGovernor = preload("res://scripts/server/server_tick_governor.gd")`
- `const WorldPersistence = preload("res://scripts/server/world_persistence.gd")`
- `const SoloCharacterStore = preload("res://scripts/server/solo_character_store.gd")`
- `const Net = preload("res://scripts/shared/net.gd")`
- `const GATEWAY_PATH := "res://scripts/server/nakama_gateway.gd"`
- `const DataLayers = preload("res://scripts/shared/data_layers.gd")`
- `const SOLO_SAVE_INTERVAL := 20.0`
- `const WORLD_SAVE_INTERVAL := 45.0`

_3 private function(s) starting with `_` are not listed._
