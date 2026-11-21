# solo_character_store.gd

> One offline solo world's survivor.

`res://scripts/server/solo_character_store.gd`

## Overview

One offline solo world's survivor. Never enabled for public guest ENet
servers: only the loopback solo launcher supplies this save path.
The same GameServer.character_data/apply_character validation as Nakama
prevents accepting fabricated item stacks, invalid positions or counters.

## Constants

- `const WorldPersistence = preload("res://scripts/server/world_persistence.gd")`
- `const SaveValidation = preload("res://scripts/shared/save_validation.gd")`
- `const VERSION := 1`
- `const MAX_BYTES := 262144`

## Functions

### `load_character`

```gdscript
static func load_character(sim, path: String) -> Dictionary
```

### `save_character`

```gdscript
static func save_character(sim, path: String, character: Dictionary) -> bool
```

Write to a temporary file, flush, then atomically rename. The old
committed character is never truncated before the new one is complete.

