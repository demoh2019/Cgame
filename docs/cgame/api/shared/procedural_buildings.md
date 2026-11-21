# procedural_buildings.gd

> Shape-grammar style buildings and Poisson-disk settlements.

`res://scripts/shared/procedural_buildings.gd`

## Overview

```text
Shape-grammar style buildings and Poisson-disk settlements.

Techniques (algorithms re-implemented from descriptions, no code copied):
- BSP rectangle subdivision for room layout (classic roguelike/dungeon
  technique, RogueBasin "Basic BSP Dungeon generation",
  https://www.roguebasin.com/index.php/Basic_BSP_Dungeon_generation).
- Door graph = randomised Kruskal spanning tree over shared room walls plus
  a few extra edges for loops.
- Poisson-disk sampling: Robert Bridson, "Fast Poisson Disk Sampling in
  Arbitrary Dimensions", SIGGRAPH 2007 sketch
  (https://www.cs.ubc.ca/~rbridson/docs/bridson-siggraph07-poissondisk.pdf).
License: published algorithms/papers only.
```

## Constants

- `const MIN_ROOM := 3`
- `const MIN_LOT := 4`
- `const MIN_LOT_SPACING := 6.0`
- `const LOOP_CHANCE := 0.25`
- `const BRIDSON_TRIES := 30`

## Functions

### `building`

```gdscript
static func building(seed: int, footprint: Vector2i, floors: int) -> Dictionary
```

```text
Returns {"footprint": Vector2i, "floors": int,
 "rooms":   [{"id", "floor", "rect": Rect2i}]  (per floor the rects tile the footprint),
 "doors":   [{"floor", "a", "b", "cell_a": Vector2i, "cell_b": Vector2i}] (a/b room ids),
 "stairs":  [{"from_floor", "to_floor", "cell": Vector2i, "room_from", "room_to"}],
 "windows": [{"floor", "room", "cell": Vector2i, "normal": Vector2i}],
 "entrance": {"room", "cell": Vector2i, "normal": Vector2i}}
```

### `settlement`

```gdscript
static func settlement(seed: int, center: Vector2, radius: float, count: int) -> Array
```

```text
Building lots around a plaza. Returns an Array of Dictionaries; entry 0 is
{"kind": "plaza", "center": Vector2, "radius": float}, the rest are
{"kind": "lot", "center": Vector2, "rect": Rect2, "footprint": Vector2i,
 "floors": int, "seed": int}. Lots never overlap each other or the plaza and
lie completely inside the settlement circle. At most `count` lots.
```

_6 private function(s) starting with `_` are not listed._
