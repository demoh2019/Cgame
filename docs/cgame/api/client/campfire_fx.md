# campfire_fx.gd

> (no header comment)

`res://scripts/client/campfire_fx.gd`

## Constants

- `const GraphicsAreaLights = preload("res://scripts/client/graphics_area_lights.gd")`
- `const VegetationWind = preload("res://scripts/client/vegetation_wind.gd")` - AAA-style campfire: animated HDR flame (bloom-driven), flickering warm light with soft shadows on high-end, rising ember particles and screen-space heat haze. Unreal/Unity fires combine exactly these four layers. Purely visual, client-only.
- `const FLAME_SHADER := preload("res://assets/shaders/campfire_flame.gdshader")`
- `const HAZE_SHADER := preload("res://assets/shaders/heat_haze.gdshader")`
- `const BASE_ENERGY := 1.6`

## Functions

### `flicker`

```gdscript
static func flicker(time: float, phase: float) -> float
```

Layered-sine flicker in ~[0.75, 1.15]: cheap, smooth, never strobes.

### `rich_effects`

```gdscript
static func rich_effects(level: int, rendering_method: String) -> bool
```

Heavy layers (haze needs the screen texture, embers are particles) only on High/Ultra Forward+.

### `build`

```gdscript
func build(level: int, rendering_method: String) -> void
```

### `add_torch_flame`

```gdscript
static func add_torch_flame(torch: Node3D, flame_height: float = 0.45) -> Node3D
```

Small animated flame (no light: torches already have budgeted lights) placed
on top of an already-instanced torch model, from its world-space mesh bounds.

### `smoke_drift`

```gdscript
static func smoke_drift(wind: Vector3) -> Vector3
```

Smoke drift from the shared weather wind (aa_vegetation_wind: xy direction,
z strength), refreshed twice a second; plumes lean further in a gale.

_5 private function(s) starting with `_` are not listed._
