# frame_hitch_analyzer.gd

> Cross-system frame hitch analyzer (Unreal Insights hitch tracks, PIX "PSO compile" markers): every frame stores cheap engine counters; a frame much slower th...

`res://scripts/client/frame_hitch_analyzer.gd`

## Overview

Cross-system frame hitch analyzer (Unreal Insights hitch tracks, PIX
"PSO compile" markers): every frame stores cheap engine counters; a frame
much slower than the recent median is attributed to the counter that
jumped with it — pipeline compilation, world streaming or VRAM growth.

## Constants

- `const WINDOW := 120`
- `const MIN_HITCH := 0.05 # 50 ms is always a visible hitch.`
- `const HITCH_FACTOR := 2.5`
- `const VRAM_JUMP := 64.0 * 1024.0 * 1024.0`
- `const KEEP := 32`

## Functions

### `read_counters`

```gdscript
static func read_counters(loaded_cells: int = 0) -> Dictionary
```

### `median`

```gdscript
func median() -> float
```

### `cause`

```gdscript
static func cause(before: Dictionary, after: Dictionary) -> String
```

### `sample`

```gdscript
func sample(delta: float, counters: Dictionary, now: float = 0.0) -> Dictionary
```

Returns the hitch record when this frame was a hitch, else an empty dictionary.

### `describe`

```gdscript
func describe() -> String
```

