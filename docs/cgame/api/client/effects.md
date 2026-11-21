# effects.gd

> (no header comment)

`res://scripts/client/effects.gd`

## Constants

- `const RainVfx = preload("res://scripts/client/rain_vfx.gd")`
- `const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")`
- `const SnowVfx = preload("res://scripts/client/snow_vfx.gd")`
- `const PoolScript = preload("res://addons/runtime_pool/node_pool.gd")`
- `const BurstScene = preload("res://scripts/client/pooled_burst.tscn")`
- `const FxPolicy = preload("res://scripts/client/fx_scalability_policy.gd")`
- `const MAX_PENDING_BURSTS := 256`
- `const BUTTERFLY_SHADER := """`

## Functions

### `update_ambience`

```gdscript
func update_ambience(ground: Vector3, daylight: float, storm: float, biome: String) -> void
```

The life around the player: `ground` is where they stand, `daylight` 0..1, `storm` 0..1, `biome` where they are.

### `update_rain`

```gdscript
func update_rain(center: Vector3, intensity: float, snow_fraction: float = 0.0) -> void
```

Rain around `center` while `intensity` > 0.

### `ring`

```gdscript
func ring(position: Vector3, color: Color, radius: float = 4.0, seconds: float = 0.7) -> void
```

A flat ring on the ground that widens and fades: a pulse of healing, a shock wave, a flash.

### `get_pool_maintenance_work_usec`

```gdscript
func get_pool_maintenance_work_usec() -> int
```

Profiling exposes the actual main-thread residency work and remaining
idle cache actions, not particle simulation or GPU rendering time.

### `get_pool_maintenance_pending_count`

```gdscript
func get_pool_maintenance_pending_count() -> int
```

### `pending_burst_count`

```gdscript
func pending_burst_count() -> int
```

### `flush_bursts`

```gdscript
func flush_bursts() -> void
```

### `burst`

```gdscript
func burst(position: Vector3, color: Color, count: int = 14, speed: float = 3.0, lifetime: float = 0.6, size: float = 0.14, gravity: float = 7.0, up: float = 0.6, priority: int = 1, group: int = 1) -> void
```

A puff of particles: `color` fades out, `speed` is the initial speed, `size` the particle size in meters.

### `hit_zombie`

```gdscript
func hit_zombie(position: Vector3) -> void
```

### `zombie_died`

```gdscript
func zombie_died(position: Vector3) -> void
```

### `hit_player`

```gdscript
func hit_player(position: Vector3) -> void
```

### `muzzle_flash`

```gdscript
func muzzle_flash(position: Vector3) -> void
```

### `gathered`

```gdscript
func gathered(position: Vector3, color: Color) -> void
```

### `level_up`

```gdscript
func level_up(position: Vector3) -> void
```

### `loot`

```gdscript
func loot(position: Vector3) -> void
```

### `footsteps`

```gdscript
func footsteps(position: Vector3, speed: float, delta: float) -> void
```

Dust kicked up by a runner; call every frame with the measured speed.

_9 private function(s) starting with `_` are not listed._
