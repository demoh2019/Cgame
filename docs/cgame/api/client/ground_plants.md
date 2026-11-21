# ground_plants.gd

> Photoscanned ground plants (Poly Haven, CC0) scattered among the procedural grass near the camera: grass clumps, dandelions, celandine, nettles, weeds, periw...

`res://scripts/client/ground_plants.gd`

## Overview

Photoscanned ground plants (Poly Haven, CC0) scattered among the procedural grass near the
camera: grass clumps, dandelions, celandine, nettles, weeds, periwinkle, ferns, shrubs, moss
and wildflowers. Baked one mesh per variant by tools/bake_polyhaven.gd -- --plants.
Each 16 m grass tile gets one MultiMesh per species (one variant per tile, so neighbouring
tiles differ), drawn only up close; the procedural grass carries the carpet beyond.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const PointSpacing = preload("res://scripts/client/point_spacing.gd")`
- `const FOLDER := "res://assets/models/polyhaven/baked/plants/"`
- `const DRAW_DISTANCE := 34.0`
- `const TILE := 16.0`
- `const SPECIES := {`
- `const CARD_ATLAS := "res://assets/models/polyhaven/grass_medium_01/textures/grass_tufts_atlas.png"` - Pixel regions (x, y, w, h) of dense grass tufts in the 1024 px grass_medium_01 atlas.
- `const CARD_REGIONS := [Rect2(210, 790, 290, 112), Rect2(620, 784, 220, 106), Rect2(30, 900, 170, 124),`
- `const CARD_HEIGHT := 0.5`

## Documented variables

- `static var density_scale: float = 1.0` - Quality multiplier on counts: Low 0 (off), Medium 0.55, High 1, Ultra 1.35.

## Functions

### `variants`

```gdscript
static func variants(species: String) -> Array
```

### `card_material`

```gdscript
static func card_material() -> StandardMaterial3D
```

### `card_mesh`

```gdscript
static func card_mesh(region_index: int) -> Mesh
```

One tuft: five photo cards fanned around the root (random angles) and leaning outward,
with roots darkened by vertex colour, so it reads as a round, deep tuft from any side.
Normals lean up so the cards light like a soft mass instead of showing flat faces.

### `mesh`

```gdscript
static func mesh(file: String, dry: bool = false) -> Mesh
```

### `quality_scale`

```gdscript
static func quality_scale(level: int) -> float
```

### `build_tile`

```gdscript
static func build_tile(origin: Vector2, tile: int, tiles_per_side: int, sample: Callable) -> Array
```

The plants of one 16 m tile of a chunk, given the grass source sampler.
`sample(lx, lz)` returns {"ok": bool, "h": float, "biome": String} for chunk-local coordinates.

_3 private function(s) starting with `_` are not listed._
