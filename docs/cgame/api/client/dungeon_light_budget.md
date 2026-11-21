# dungeon_light_budget.gd

> Global, render-only budget for room torches across all streamed dungeon chunks.

`res://scripts/client/dungeon_light_budget.gd`

## Overview

Global, render-only budget for room torches across all streamed dungeon chunks.
Forward+/Compatibility both have limits for many overlapping OmniLight3D nodes.
One manager selects the nearest lights instead of each chunk spending its own budget.

## Constants

- `const GROUP := "aa_dungeon_torches"`
- `const UPDATE_INTERVAL := 0.13`
- `const FADE_DISTANCE := 7.0`
- `const DungeonTorchCookie = preload("res://scripts/client/dungeon_torch_cookie.gd")`
- `const PRESETS := [`

## Functions

### `settings`

```gdscript
static func settings(quality: int) -> Dictionary
```

### `configure`

```gdscript
static func configure(quality: int) -> void
```

### `effective_max`

```gdscript
static func effective_max(quality: int, backend: String) -> int
```

OpenGL Compatibility has a smaller simultaneous light budget than Forward+.

### `nearest`

```gdscript
static func nearest(candidates: Array, maximum: int, radius: float) -> Array
```

Pure selector; "node" is intentionally opaque so unit tests need no GPU or scene.
Equal-distance ties are stable within a session to avoid flickering light selection.

### `stable_nearest`

```gdscript
static func stable_nearest(candidates: Array, maximum: int, radius: float, retained: Array = [], hysteresis: float = 4.0, native: Object = null) -> Array
```

Unreal-style significance retention: keep a currently active torch until a
challenger is meaningfully closer, but never past the hard radius.
All choices are render-only; gameplay and AI lights remain unchanged.

### `stable_world`

```gdscript
static func stable_world(candidates: Array, observers: PackedVector3Array, maximum: int, radius: float, retained: Array = [], hysteresis: float = 4.0, native: Object = null) -> Array
```

Camera/split-screen aware significance: bounded native world selection with
stable IDs, while stock Godot follows the same nearest-observer scoring.
This only changes cosmetic torch activation, never damage or enemy vision.

### `intensity`

```gdscript
static func intensity(distance: float, radius: float, time: float, seed: float, flicker_amount: float) -> float
```

Soft fading keeps the room light from popping at the budget range.

_2 private function(s) starting with `_` are not listed._
