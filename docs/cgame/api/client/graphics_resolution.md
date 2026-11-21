# graphics_resolution.gd

> Pure renderer-aware upscale/antialiasing policy; mobile and GL Compatibility do not support Godot 4 Forward+ FSR2 or independent 3D resolution buffers.

`res://scripts/client/graphics_resolution.gd`

## Overview

Pure renderer-aware upscale/antialiasing policy; mobile and GL Compatibility
do not support Godot 4 Forward+ FSR2 or independent 3D resolution buffers.

## Functions

### `fsr_sharpness_for_scale`

```gdscript
static func fsr_sharpness_for_scale(render_scale: float) -> float
```

FSR2 already owns its RCAS sharpening stage. At lower internal resolutions
restore a little more microdetail without adding a second fullscreen pass.
Godot uses 0 = sharpest and 2 = softest; avoid ringing at low scales.

### `metalfx_min_scale`

```gdscript
static func metalfx_min_scale(method: String, driver: String, device: RenderingDevice) -> float
```

Read the native MetalFX hardware limit only on Metal. A zero/invalid
limit means this device must stay on FSR2 even if its driver is Metal.
RenderingDevice returns the limit scaled by 1,000,000.

### `runtime_metalfx_min_scale`

```gdscript
static func runtime_metalfx_min_scale() -> float
```

### `metalfx_budget_floor`

```gdscript
static func metalfx_budget_floor(device_minimum: float, tier_ceiling: float) -> float
```

A temporal scaler must not silently override a preset's render-pixel
ceiling. Performance with a MetalFX 0.7x minimum and 0.59x budget
must use FSR2 at 0.59x, not force 0.7x (~41% more shaded pixels).

### `plan`

```gdscript
static func plan(method: String, profile: Dictionary, requested_scale: float = -1.0, adaptive: bool = false, driver: String = "", metal_min_scale: float = 0.0) -> Dictionary
```

### `diagnostic_label`

```gdscript
static func diagnostic_label(mode: int, scale: float) -> String
```

Diagnostics expose the backend the viewport actually selected, rather
than a requested preset. Called only by the optional 4Hz FPS overlay.

### `apply`

```gdscript
static func apply(viewport: Viewport, settings: Dictionary) -> void
```

