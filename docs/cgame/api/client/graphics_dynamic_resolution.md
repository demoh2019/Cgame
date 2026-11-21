# graphics_dynamic_resolution.gd

> (no header comment)

`res://scripts/client/graphics_dynamic_resolution.gd`

## Constants

- `const FLOORS := [0.52, 0.65, 0.82, 0.90]` - 3D pixel-budget scaler; hysteresis and warmup avoid per-frame GPU buffer resizes. Valid GPU timer queries keep CPU-bound frames from unnecessarily lowering the 3D pixel budget. Quality presets remain the outer fallback.
- `const CEILINGS := [0.59, 0.77, 1.0, 1.0]`
- `const SLOW_FRAME := 1.0 / 48.0`
- `const FAST_FRAME := 1.0 / 56.0`
- `const LOWER_AFTER := 2.2`
- `const RAISE_AFTER := 6.0`
- `const WARMUP := 1.0`
- `const MAX_VALID_GPU_MS := 80.0`

## Functions

### `configure`

```gdscript
func configure(value: int, device_min_scale: float = 0.0) -> void
```

### `at_floor`

```gdscript
func at_floor() -> bool
```

### `at_ceiling`

```gdscript
func at_ceiling() -> bool
```

### `render_frame_seconds`

```gdscript
static func render_frame_seconds(delta: float, measured_gpu_ms: float = 0.0) -> float
```

GPU timer queries are in milliseconds, while process deltas are seconds.
Zero is the Godot signal for disabled/unavailable GPU measurements.
Fallback preserves Compatibility/headless behavior and deterministic tests.

### `sample_frame`

```gdscript
func sample_frame(delta: float, measured_gpu_ms: float = 0.0) -> bool
```

