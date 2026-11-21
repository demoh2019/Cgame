# graphics_texture_streaming.gd

> Predictive mip prefetch for the native TextureStreaming engine module.

`res://scripts/client/graphics_texture_streaming.gd`

## Overview

Predictive mip prefetch for the native TextureStreaming engine module.
GPU material feedback still selects the visible textures; the streaming
memory-budget fitter may drop the prefetch during VRAM pressure.
Only streamed textures are affected; ordinary textures cost nothing extra.

## Constants

- `const PREFETCH_MIPS := [0, 0, 1, 2]`
- `const PROFILER_METRICS := {` - Native equivalent of Unreal STAT STREAMING, exposed as real Godot Performance monitors. These values are cheap atomic gauges published by the texture feedback worker; no object-list traversal on each monitor poll. 0 for "TextureStreamingBudgetBytes" means budget fitting is disabled. "Pending" counts textures not yet at the fitted mip, not active I/O jobs.

## Functions

### `prefetch_mips`

```gdscript
static func prefetch_mips(level: int, method: String) -> int
```

### `adaptive_prefetch_enabled`

```gdscript
static func adaptive_prefetch_enabled(level: int, method: String) -> bool
```

Adaptive prefetch is useful only when Forward+ has speculative detail
residency. Low tiers and Compatibility keep their previous predictable use.
The native worker changes only speculative mip prefetch, not visible mip
feedback or the budget fitter's approved target.

### `apply`

```gdscript
static func apply(level: int, method: String) -> void
```

### `register_profiler_monitors`

```gdscript
static func register_profiler_monitors() -> Array[StringName]
```

