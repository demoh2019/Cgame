# graphics_stone_microdetail.gd

> Cached native PBR detail normals for masonry walls/ruins.

`res://scripts/client/graphics_stone_microdetail.gd`

## Overview

Cached native PBR detail normals for masonry walls/ruins.
Unreal DetailTexturing + Unity HDRP Detail Map idea, but using Godot's
existing Standard/ORM Material3D detail_normal stage, without mesh rebuilds.

Dynamic Auto quality only toggles existing material shader variants; the
two 128x128 textures are created lazily and shared by all eligible walls.

## Constants

- `const IMAGE_SIZE := 128`
- `const HIGH_AMOUNT := 0.22`
- `const ULTRA_AMOUNT := 0.40`
- `const PARALLAX_MIN_LAYERS := 4`
- `const PARALLAX_MAX_LAYERS := 8`
- `const PARALLAX_SCALE := 0.85`
- `const MASONRY_PARTS := ["wall", "pillar", "column", "rubble", "stairs", "stone"]`

## Functions

### `is_masonry_path`

```gdscript
static func is_masonry_path(path: String) -> bool
```

Exclude beds, torches, barrels, wood, leather and other imported art.
ModelCatalog uses this only on authored dungeon meshes, never on actors.

### `supported`

```gdscript
static func supported(material: BaseMaterial3D, has_tangents: bool) -> bool
```

### `tier_for`

```gdscript
static func tier_for(quality: int, method: String) -> int
```

### `height_at`

```gdscript
static func height_at(uv: Vector2) -> float
```

Tileable, zero-memory-height signal: integer spatial frequencies make
both wrap boundaries continuous. Derivatives become small bump normals.
No noise octaves or image work occur in the runtime shader.

### `normal_at`

```gdscript
static func normal_at(uv: Vector2, amount: float) -> Vector3
```

### `texture_for`

```gdscript
static func texture_for(tier: int) -> Texture2D
```

### `parallax_height_at`

```gdscript
static func parallax_height_at(uv: Vector2) -> float
```

Use the very same periodic height signal as the existing stone normals.
The 128x128 RGB map has a bounded 0..1 height response and mipmaps.
Both PBR effects remain registered and aligned under the source UV.

### `register`

```gdscript
static func register(material: BaseMaterial3D, valid_tangents: bool) -> bool
```

Called once for each *baked* copied masonry surface with valid UV tangents.
Uses WeakRef so the graphics manager never owns an unloaded world mesh.

### `configure`

```gdscript
static func configure(quality: int, method: String) -> void
```

Profile changes are rare. The no-change branch does not iterate objects,
and streamed in masonry inherits the latest profile upon registration.

### `clear_cache`

```gdscript
static func clear_cache() -> void
```

Called on game shutdown/test teardown; never deletes source glTF assets.

_5 private function(s) starting with `_` are not listed._
