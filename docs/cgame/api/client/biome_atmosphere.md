# biome_atmosphere.gd

> (no header comment)

`res://scripts/client/biome_atmosphere.gd`

## Constants

- `const MIN_HEIGHT_FACTOR := 0.55` - Renderer-independent, bounded visual rules for each existing world biome. Uses the same Godot environment fog; never allocates a secondary fog pass.
- `const MAX_HEIGHT_FACTOR := 1.45`
- `const MIN_VOLUME_FACTOR := 0.65`
- `const MAX_VOLUME_FACTOR := 1.25`
- `const MAX_TINT_AMOUNT := 0.22`
- `const TRANSITION_SPEED := 0.7`

## Functions

### `settings`

```gdscript
static func settings(biome: String) -> Dictionary
```

### `advance`

```gdscript
static func advance(previous: Dictionary, biome: String, delta: float) -> Dictionary
```

Returns new state without mutating presets or authoring GPU resources.
One smooth lerp avoids a sudden fog-color step at biome cell boundaries.

