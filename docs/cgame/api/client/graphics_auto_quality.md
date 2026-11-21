# graphics_auto_quality.gd

> Adaptive visual detail reacts to sustained frame time, not isolated stalls or loading spikes.

`res://scripts/client/graphics_auto_quality.gd`

## Overview

Adaptive visual detail reacts to sustained frame time, not isolated stalls or loading spikes.
The controller is deterministic and does not require a GPU to test.

## Constants

- `const GraphicsDynamicResolution = preload("res://scripts/client/graphics_dynamic_resolution.gd")`
- `const GRASS_FADE_END := [40.0, 60.0, 80.0]`
- `const SLOW_FRAME := 1.0 / 45.0`
- `const FAST_FRAME := 1.0 / 55.0`
- `const DOWNGRADE_AFTER := 3.5`
- `const UPGRADE_AFTER := 9.0`

## Functions

### `preset`

```gdscript
func preset() -> Dictionary
```

### `set_mode`

```gdscript
func set_mode(value: String) -> bool
```

### `at_resolution_limit`

```gdscript
static func at_resolution_limit(rd: bool, at_floor: bool, at_ceiling: bool, delta: float, measured_gpu_ms: float = 0.0) -> bool
```

The first tier of adaptive quality changes the actual 3D pixel budget.
Change expensive world detail only at a resolution limit AND only if the
GPU (not a CPU scripting/physics stall) has the corresponding demand.

### `sample_frame`

```gdscript
func sample_frame(delta: float, measured_gpu_ms: float = 0.0) -> bool
```

GPU timestamps are optional; Compatibility/headless falls back to frame
delta. Accumulate wall-clock delta to avoid unstable quality on slow GPUs.
Frames above 200 ms are normally loading stalls, never adjust on them.

