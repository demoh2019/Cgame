# house_pieces.gd

> House building: floors, walls, doorways, windows, roofs and pillars that snap to a 3 m grid so pieces line up into real houses.

`res://scripts/shared/house_pieces.gd`

## Overview

House building: floors, walls, doorways, windows, roofs and pillars that snap to a 3 m grid so
pieces line up into real houses. Shared by the server (validation, collision) and the client
(ghost preview, rendering). A placed piece is an ordinary player structure (barricades), so
repair, upgrade, upkeep, decay and dismantling work exactly as for the old walls.

Grid: cells are GRID metres square. Floors and roofs sit on a cell centre; walls, doorways and
windows on the middle of a cell edge; pillars on a cell corner. A wall's line runs along
(sin(yaw), cos(yaw)): yaw 0 for edges facing +-X, PI/2 for edges facing +-Z.

## Constants

- `const GRID := 3.0`
- `const WALL_HEIGHT := 3.0`
- `const BUILD_RANGE := 7.0`
- `const PIECES := ["wall", "door", "window", "floor", "roof", "pillar", "bed", "lamp", "chest", "workbench"]`
- `const NAMES := {"wall": "Wall", "door": "Door", "window": "Window wall", "floor": "Floor", "roof": "Roof", "pillar": "Pillar",`
- `const STATION_RANGE := 3.0 # How close a chest or workbench must be to use it.`
- `const DOOR_REACH := 3.0`
- `const BED_RESPAWN_RANGE := 2.5`
- `const COST := {`

## Functions

### `valid`

```gdscript
static func valid(piece: String) -> bool
```

### `slot`

```gdscript
static func slot(piece: String) -> String
```

Which pieces compete for the same spot: one wall-type per edge, one floor, one roof, one pillar.

### `elevation`

```gdscript
static func elevation(piece: String) -> float
```

### `blocks`

```gdscript
static func blocks(piece: String) -> bool
```

### `snap`

```gdscript
static func snap(piece: String, point: Vector2, facing: float = 0.0) -> Vector3
```

The snapped position and facing for a piece aimed at `point` (x, z, yaw).
`facing` (the builder's facing yaw) turns roofs and furniture in quarter turns, so two roofs
placed facing each other form a gable.

### `blockers`

```gdscript
static func blockers(piece: String, x: float, z: float, yaw: float, closed: bool = false) -> Array
```

Movement blockers (x, z, radius) of a placed piece. Doorways leave the middle open.

### `placement_reason`

```gdscript
static func placement_reason(world, piece: String, snapped: Vector3, from: Vector2) -> String
```

"" when the piece may go there (terrain, range, hub), otherwise the reason. Overlap with other
pieces, people and materials are checked by the server.

### `blockers_of`

```gdscript
static func blockers_of(item: Dictionary) -> Array
```

Movement blockers of a stored piece record (doors use their open state).

