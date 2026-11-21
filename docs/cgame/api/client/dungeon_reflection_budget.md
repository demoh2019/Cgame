# dungeon_reflection_budget.gd

> Camera-local, GPU-bounded interior reflection captures for procedural dungeons.

`res://scripts/client/dungeon_reflection_budget.gd`

## Overview

Camera-local, GPU-bounded interior reflection captures for procedural dungeons.
Room markers are cheap Node3Ds, but only High/Ultra Forward+ create actual
ReflectionProbes. The small pool is reused as the player explores.
UPDATE_ONCE captures across several frames; NEVER recapture every frame.

## Constants

- `const Dungeon = preload("res://scripts/shared/dungeon.gd")`
- `const GROUP := "aa_dungeon_reflection_anchor"`
- `const CHECK_INTERVAL := 0.4`
- `const CAPTURE_COOLDOWN := 1.25`
- `const SWITCH_HYSTERESIS := 3.0`
- `const PRESETS := [`

## Functions

### `settings`

```gdscript
static func settings(level: int, method: String) -> Dictionary
```

### `configure`

```gdscript
static func configure(level: int) -> void
```

### `choose`

```gdscript
static func choose(candidates: Array, count: int, radius: float, retained: Array = []) -> Array
```

Pure selection function. Existing assignments have a 3 m preference to
prevent re-capturing on every step across adjacent room boundaries.

### `make_probe`

```gdscript
static func make_probe(profile: Dictionary) -> ReflectionProbe
```

_2 private function(s) starting with `_` are not listed._
