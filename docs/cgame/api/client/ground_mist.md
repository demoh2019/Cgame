# ground_mist.gd

> (no header comment)

`res://scripts/client/ground_mist.gd`

## Constants

- `const SOURCE := "res://assets/shaders/ground_mist.gdshader"` - Artist-directed local froxel mist. The same shader works in offline/online; multiplayer state, water, collision, visibility and lighting are unchanged. Godot Forward+ FogVolume already uses the scene's shadowed volumetric pass.
- `const MIN_VISIBLE := 0.0005`
- `const UPDATE_INTERVAL := 0.20`
- `const ANCHOR_GRID := 8.0`

## Functions

### `settings`

```gdscript
static func settings(biome: String, daylight: float, sun_height: float, storm: float, quality: int, renderer: String, underground: bool = false) -> Dictionary
```

### `setup`

```gdscript
func setup() -> void
```

### `update_view`

```gdscript
func update_view(position: Vector3, biome: String, daylight: float, sun_height: float, storm: float, wind: Vector2, quality: int, delta: float, underground: bool = false) -> void
```

Called with the actual rendered survivor position and cached weather/biome.
World-cell snapping avoids moving the volume every frame, minimizing TAA ghosting.

