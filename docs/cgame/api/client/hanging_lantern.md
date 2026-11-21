# hanging_lantern.gd

> (no header comment)

`res://scripts/client/hanging_lantern.gd`

## Constants

- `const VegetationWind = preload("res://scripts/client/vegetation_wind.gd")` - A lantern on a chain that swings in the weather wind and when bumped — a verlet chain pinned at the top, the same idea as Unity's chain of HingeJoints or an Unreal Physics Constraint chain, but integrated analytically (no physics bodies, no collision) so dozens of them cost nothing. Pure cosmetics, client only. Also: `rope_points` / `build_rope_mesh` give a sagging cable (catenary-like parabola) between two anchors.
- `const LINKS := [0, 3, 5, 8] # Chain links per quality tier; Low shows none.`
- `const LINK_LENGTH := 0.18`
- `const GRAVITY := 9.0`
- `const DAMPING := 0.985`
- `const WIND_FORCE := 6.0`

## Functions

### `link_count`

```gdscript
static func link_count(level: int) -> int
```

### `step`

```gdscript
static func step(points: PackedVector3Array, previous: PackedVector3Array, link_length: float, wind: Vector3, dt: float) -> void
```

One verlet step for a pinned chain. Returns nothing; `points`/`previous` are updated in place.

### `swing_angle`

```gdscript
static func swing_angle(points: PackedVector3Array) -> float
```

Angle of the chain's free end from vertical, radians (for tests and lamp tilt).

### `rope_points`

```gdscript
static func rope_points(a: Vector3, b: Vector3, sag: float, count: int) -> PackedVector3Array
```

`count + 1` points of a cable hanging between a and b: a parabola dipping `sag` metres at the middle.

### `rope_length`

```gdscript
static func rope_length(points: PackedVector3Array) -> float
```

### `build_rope_mesh`

```gdscript
static func build_rope_mesh(points: PackedVector3Array, radius: float) -> ArrayMesh
```

A thin square-section tube along the points (one surface, no per-frame cost).

### `setup`

```gdscript
func setup(level: int, glow: Color) -> void
```

_2 private function(s) starting with `_` are not listed._
