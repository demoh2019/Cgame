# dungeon.gd

> Dungeons under the bunkers: each bunker has a hatch that leads down into an underground complex of stone rooms joined by doorways, with infected in every roo...

`res://scripts/shared/dungeon.gd`

## Overview

Dungeons under the bunkers: each bunker has a hatch that leads down into an underground complex of stone rooms joined by
doorways, with infected in every room, a chest in each, and the strongest of them in the room farthest from the stairs.

The complexes live in their own part of the world's coordinates, far east of the island (UNDERGROUND_X and beyond), one
per 256 m region of the surface, so WorldGen answers for them like for any ground: a flat stone floor, walls as
blockers, spawns and crates in the chunks. Movement, combat, loot and prediction need nothing new. Everything here is
derived from the world seed and the region, so the server and every client see the same rooms.

## Constants

- `const UNDERGROUND_X := 6000.0 # Everything east of this is underground.`
- `const REGION_SIZE := 256.0 # The surface region a dungeon belongs to (WorldPoi regions).`
- `const SLOT := 160.0 # Room for one complex (at most 5 x 5 rooms of 12 m) in the underground grid.`
- `const REGION_OFFSET := 16 # Surface regions -16..15 map to underground slots 0..31.`
- `const TILE := 4.0 # One floor tile and one wall piece of the dungeon kit.`
- `const ROOM_TILES := 3`
- `const ROOM := TILE * ROOM_TILES # 12 m rooms.`
- `const FLOOR_Y := 2.0`
- `const GRID := 2 # Rooms lie on a grid from -GRID to GRID around the stairs room.`
- `const WALL_POST := 0.55 # Radius of the posts that make up a wall for collision.`
- `const HATCH_REACH := 2.6 # How close to the hatch or the stairs you must be to go down or up.`

## Functions

### `is_underground`

```gdscript
static func is_underground(x: float, _z: float = 0.0) -> bool
```

### `region_of`

```gdscript
static func region_of(x: float, z: float) -> Vector2i
```

The surface region whose bunker a point underground belongs to.

### `origin`

```gdscript
static func origin(region: Vector2i) -> Vector2
```

Centre of the stairs room of a region's complex.

### `layout`

```gdscript
static func layout(world_seed: int, region: Vector2i) -> Dictionary
```

The rooms of a region's complex: {"rooms": [Vector2i], "links": {"a|b": true}, "boss": Vector2i}. A random walk from
the stairs room (0, 0), six to nine rooms; every new room opens into the one it was reached from.

### `linked`

```gdscript
static func linked(layout_data: Dictionary, a: Vector2i, b: Vector2i) -> bool
```

### `room_center`

```gdscript
static func room_center(region: Vector2i, room: Vector2i) -> Vector2
```

### `inside_room`

```gdscript
static func inside_room(world_seed: int, x: float, z: float) -> bool
```

Whether a point lies inside one of the rooms of its complex.

### `walls`

```gdscript
static func walls(world_seed: int, region: Vector2i) -> Array
```

Wall pieces of a complex, one per 4 m tile edge: [{"a": Vector2, "b": Vector2, "door": bool}]. Every room is closed
all round; an edge into a linked room gets a doorway in its middle piece, an edge into an unlinked room is solid.

### `blockers_near`

```gdscript
static func blockers_near(world_seed: int, x: float, z: float, radius: float) -> Array
```

Collision posts of the walls near a point, as blockers (doorways keep only their side posts).

### `room_contents`

```gdscript
static func room_contents(world_seed: int, region: Vector2i, room: Vector2i, zone: int) -> Dictionary
```

What waits in a room: [{"type", "x", "z"}] infected and at most one chest. The stairs room is empty; the deepest room
holds a brute with its escort.

### `hatch`

```gdscript
static func hatch(world, site: Dictionary) -> Vector2
```

The hatch down into a bunker's complex: the first free spot on a ring round the bunker's centre.

### `bunker_at`

```gdscript
static func bunker_at(world, x: float, z: float) -> Dictionary
```

The bunker whose hatch is within reach of a surface point, or {}.

### `arrival`

```gdscript
static func arrival(region: Vector2i) -> Vector2
```

Where you arrive below: in the stairs room, a little off the stairs.

### `at_stairs`

```gdscript
static func at_stairs(x: float, z: float) -> bool
```

Whether an underground point is at the stairs up.

### `region_of_site`

```gdscript
static func region_of_site(site: Dictionary) -> Vector2i
```

Surface region of a site (the dungeon below it).

_1 private function(s) starting with `_` are not listed._
