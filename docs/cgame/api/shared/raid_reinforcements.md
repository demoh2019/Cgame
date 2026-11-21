# raid_reinforcements.gd

> (no header comment)

`res://scripts/shared/raid_reinforcements.gd`

## Constants

- `const Movement = preload("res://scripts/shared/movement.gd")` - Session-only reinforcements for the existing party boss, not a new boss. Only server-confirmed health and server-owned positions may trigger adds.
- `const FIRST_THRESHOLD := 0.65`
- `const SECOND_THRESHOLD := 0.30`
- `const MAX_PHASE := 2`
- `const MAX_WAVE := 2`
- `const MIN_PLAYER_DISTANCE := 7.0`
- `const MIN_INFECTED_DISTANCE := 3.5`
- `const MIN_BETWEEN_ADDS := 5.0`
- `const RADII := [9.0, 12.0, 15.0]`
- `const ANGLES := 16`
- `const CONE_RINGS := 2`
- `const CONE_RAYS := 9`
- `const CONE_DEGREES := 100.0 # Full aperture of the second raid phase.`
- `const MAX_THREAT_CONTEXTS := 32`
- `const MAX_EXCLUSION_CONTEXTS := 128`
- `const QUERY_MAX_DISTANCE := 64.0`
- `const MAX_RAID_HEIGHT_DIFFERENCE := 3.0 # Reject steep shelves above or below raid bosses.`

## Functions

### `rank_sites`

```gdscript
static func rank_sites(candidates: Array[Vector2], threats: Array[Vector2], center: Vector2, prefer_native: bool = true) -> Array[Vector2]
```

Rank already walkable, server-vetted sites by distance to the nearest
alive player. Native Cgame EnvironmentQuery3D uses exactly the same
score as this deterministic stock-Godot fallback. No client-supplied
candidate coordinates or RPCs enter this authoritative selection.

### `spread_sites`

```gdscript
static func spread_sites(candidates: Array[Vector2], threats: Array[Vector2], center: Vector2, count: int, min_separation: float, prefer_native: bool = true, exclusions: Array[Vector2] = [], min_exclusion_distance: float = 0.0, candidate_heights: Array[float] = [], center_height: float = 0.0, max_height_difference: float = 0.0) -> Array[Vector2]
```

Choose multiple safe locations without clustering. Only pre-vetted server
positions enter the native query. A deterministic GDScript path makes the
result identical on stock Godot and older Cgame binaries.

### `next_phase`

```gdscript
static func next_phase(hp: float, max_hp: float, completed: int) -> int
```

### `kinds`

```gdscript
static func kinds(phase: int) -> Array[String]
```

### `candidate_ring_points`

```gdscript
static func candidate_ring_points(center: Vector2, phase: int, prefer_native: bool = true) -> PackedVector2Array
```

Sample three encounter bands with the native EQS Donut generator when available.
Preserve the original source ordering (ring, then phase-rotated angle).
This only generates untrusted *candidate* geometry; sites() validates all
terrain, nav, water, player and infected occupancy guards independently.

### `candidate_cone_points`

```gdscript
static func candidate_cone_points(center: Vector2, direction: Vector2, prefer_native: bool = true) -> PackedVector2Array
```

Additional forward-sector positions in phase two, oriented at the closest
surviving player. Physics/nav validation remains in sites(), not here.

### `sites`

```gdscript
static func sites(world, players: Dictionary, zombies: Dictionary, center: Vector3, phase: int, count: int) -> Array[Vector2]
```

Bounded deterministic search on walkable terrain, same PvP risk zone.

