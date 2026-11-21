# physics_debris.gd

> Cosmetic rigid-body debris, spent casings and blast impulses (Unreal Chaos Destruction "lite" + Physics Fields, Unity PhysX rigidbodies + explosion force).

`res://scripts/client/physics_debris.gd`

## Overview

```text
Cosmetic rigid-body debris, spent casings and blast impulses (Unreal Chaos Destruction "lite" + Physics Fields,
Unity PhysX rigidbodies + explosion force). Everything lives on its own collision layer against one local
heightmap collider that follows the player, so nothing here can touch gameplay or server state.
 - barricade breaks burst into wood chunks that tumble, sleep, shrink away and are pooled
 - ranged shots eject brass casings
 - blasts push debris and ragdoll corpses (PhysicalBone3D on Ragdoll.LAYER) with a radial falloff field
 - bodies in water float and bob on a wave surface (buoyancy)
Per-tier budgets cap live bodies; the oldest are recycled first.
```

## Constants

- `const Ragdoll = preload("res://scripts/client/ragdoll.gd")`
- `const EngineFeatures = preload("res://scripts/client/engine_features.gd")`
- `const LAYER := 1 << 20`
- `const CHUNK_BUDGET := [0, 10, 24, 48] # Low, Medium, High, Ultra.`
- `const CASING_BUDGET := [0, 0, 10, 24]`
- `const LIFETIME := 9.0 # Hard cap per body.`
- `const SLEEP_RETIRE := 1.5 # Seconds asleep before shrinking away.`
- `const SHRINK := 0.8`
- `const GROUND_SIZE := 17 # Heightmap samples per side, 1 m apart.`
- `const RECENTER := 4.0`
- `const WATER_SURFACE := -0.35 # Matches the water plane in online_main (WATER_LEVEL - 0.35).`
- `const BLAST_WALL_MASK := 1 # World geometry (not cosmetic debris or ragdolls).`
- `const BLAST_WALL_ATTENUATION := 0.25 # Thick walls absorb 75% of the impulse.`
- `const BLAST_MAX_OCCLUSION_RAYS := 24 # One extra ray per body, bounded.`

## Functions

### `quality_level`

```gdscript
static func quality_level() -> int
```

Current graphics tier; loaded lazily so the pure helpers above stay unit-testable without the renderer stack.

### `chunk_budget`

```gdscript
static func chunk_budget(level: int) -> int
```

### `casing_budget`

```gdscript
static func casing_budget(level: int) -> int
```

### `total_budget`

```gdscript
static func total_budget(level: int) -> int
```

### `chunk_count`

```gdscript
static func chunk_count(level: int, strength: float = 1.0) -> int
```

How many chunks a break spawns, bounded by the tier.

### `chunk_size`

```gdscript
static func chunk_size(index: int) -> Vector3
```

Edge lengths of chunk number `index` from a deterministic hash (planks vs shards).

### `falloff`

```gdscript
static func falloff(distance: float, radius: float) -> float
```

Radial blast falloff: 1 at the centre, 0 at the radius, quadratic in between.

### `blast_shielding`

```gdscript
static func blast_shielding(blocked: bool, attenuation: float = BLAST_WALL_ATTENUATION) -> float
```

Factor for the energy of an explosion behind a wall. The same
calculation is in RadialForceField3D::occlusion_scale (native C++).

### `blast_impulse_magnitude`

```gdscript
static func blast_impulse_magnitude(strength: float, falloff_scale: float, mass: float) -> float
```

Mass-independent explosion: the impulse scales by mass, so the
resulting velocity change is independent of the body's weight.

### `buoyancy_force`

```gdscript
static func buoyancy_force(depth: float, mass: float, density_ratio: float, gravity: float = 9.8) -> float
```

Upward buoyancy force for a body whose centre is `depth` metres below the surface (<= 0 = above water).
`density_ratio` is body density over water density: wood (< 1) floats, brass (> 1) sinks.

### `surface_height`

```gdscript
static func surface_height(x: float, z: float, time: float) -> float
```

Water surface height with a gentle travelling swell, so floating props bob.

### `should_retire`

```gdscript
static func should_retire(age: float, asleep_for: float) -> bool
```

Retire when too old, or after sleeping for a while (it has stopped moving, so the eye no longer needs it).

### `shrink_scale`

```gdscript
static func shrink_scale(t: float) -> float
```

Scale (1 -> 0) of a body that has been retiring for `t` seconds.

### `ground_heights`

```gdscript
static func ground_heights(cx: float, cz: float, height_at: Callable) -> PackedFloat32Array
```

Heights of a GROUND_SIZE x GROUND_SIZE grid centred on (cx, cz), absolute y.

### `setup`

```gdscript
func setup(height_at: Callable, is_water: Callable) -> void
```

### `active_count`

```gdscript
func active_count() -> int
```

### `burst_chunks`

```gdscript
func burst_chunks(at: Vector3, strength: float = 1.0) -> int
```

A destroyed barricade/crate: wood chunks fly out and tumble.

### `eject_casing`

```gdscript
func eject_casing(at: Vector3, facing_yaw: float) -> bool
```

An ejected brass casing flying out to the right of `facing_yaw`.

### `blast`

```gdscript
func blast(center: Vector3, radius: float, impulse: float) -> void
```

Queue a radial impulse field; applied on the next physics step to debris and ragdoll bones in range.
The one place blasts push debris and ragdolls (physics_world_fx feeds it): the engine's
RadialForceField3D when compiled in, else the script sphere query below — never both.

_5 private function(s) starting with `_` are not listed._
