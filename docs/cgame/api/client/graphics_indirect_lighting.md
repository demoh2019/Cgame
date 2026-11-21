# graphics_indirect_lighting.gd

> (no header comment)

`res://scripts/client/graphics_indirect_lighting.gd`

## Constants

- `const GraphicsOcclusionQuality = preload("res://scripts/client/graphics_occlusion_quality.gd")`

## Functions

### `settings`

```gdscript
static func settings(level: int, method: String) -> Dictionary
```

### `apply`

```gdscript
static func apply(environment: Environment, level: int, method: String) -> void
```

Apply only when graphics quality changes; never animate screen-space
buffer settings at 60 Hz or allocate a second fullscreen pass.

### `apply_ssil`

```gdscript
static func apply_ssil(environment: Environment, p: Dictionary) -> void
```

Native Cgame batches all SSIL fields into one renderer update. Stock Godot
uses the same Environment API without requiring a patched engine build.

### `apply_sdfgi`

```gdscript
static func apply_sdfgi(environment: Environment, p: Dictionary) -> void
```

The local dynamic GI budget is applied only when the graphics preset or
rendering backend changes, never on a weather/day-night tick.
Native Cgame coalesces this into one RendererServer update per tier switch.

### `visibility_settings`

```gdscript
static func visibility_settings(level: int, method: String, underground: bool) -> Dictionary
```

SDFGI occlusion is deliberately INDOOR-ONLY. Godot's extra visibility
rays eliminate leaks through thick dungeon walls, but introduce dark
blotches outdoors and cost GPU time. Normal/probe bias is lowered a little
indoors to reduce leaks; the native engine applies all four fields at once.
No new GI volumes, SDF cascades, or ray tracing system are created.

### `update_visibility`

```gdscript
static func update_visibility(environment: Environment, level: int, method: String, underground: bool) -> void
```

Called in the same existing environment/weather tick as the dungeon
visibility culler. Purely static player-region policy; never re-voxelizes
the terrain or changes these settings if the player stays put.

