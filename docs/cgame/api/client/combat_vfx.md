# combat_vfx.gd

> Combat and interaction VFX layer (Niagara / VFX Graph style emitters, all pooled and capped by quality tier): ranged tracers, shell casings, muzzle light, me...

`res://scripts/client/combat_vfx.gd`

## Overview

Combat and interaction VFX layer (Niagara / VFX Graph style emitters, all pooled and capped by quality tier):
ranged tracers, shell casings, muzzle light, melee swing trails, material-aware impacts, directional blood spray,
water splash/ripples, landing dust, explosion shockwave with light, pickup sparkle.
Static helpers hold the budgets/maths so they can be unit tested without a scene.

## Constants

- `const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")`
- `const WATER_LEVEL := 0.0 # Mirrors Defs.WATER_LEVEL.`

## Functions

### `budget`

```gdscript
static func budget(kind: String, tier: int) -> int
```

Pool/cap sizes per feature and quality tier 0..3 (0 = nothing).

### `dir_xz`

```gdscript
static func dir_xz(value) -> Vector2
```

Horizontal unit direction from an event's `dir` value (Vector2/Vector3/Array/Dictionary); ZERO when unusable.

### `material_for`

```gdscript
static func material_for(biome: String, item: String = "") -> String
```

Surface material for impacts from the biome (and gathered item id when known).

### `impact_profile`

```gdscript
static func impact_profile(material: String) -> Dictionary
```

Particle recipe per material: metal = bright sparks, wood = chips, dirt/sand/mud = dust clods.

### `spray_direction`

```gdscript
static func spray_direction(from: Vector3, to: Vector3) -> Vector3
```

Blood/ichor sprays away from the attacker, slightly upward. Returns a unit vector.

### `tracer_span`

```gdscript
static func tracer_span(origin: Vector3, dir: Vector2, reach: float, target: Vector3 = Vector3.INF) -> PackedVector3Array
```

Tracer segment: starts a little ahead of the muzzle, ends `reach` meters on (or at `target`).

### `casing_velocity`

```gdscript
static func casing_velocity(dir: Vector2, seed_value: int) -> Vector3
```

Casing ejection velocity: out to the shooter's right and up, with deterministic jitter from `seed_value`.

### `swing_arc`

```gdscript
static func swing_arc(origin: Vector3, dir: Vector2, reach: float, half_angle: float, steps: int) -> PackedVector3Array
```

Points of a swing arc in front of the attacker (sweeping from -half_angle to +half_angle).

### `landing_strength`

```gdscript
static func landing_strength(fall_speed: float) -> float
```

0..1 landing dust strength for a fall speed in m/s (nothing below 3 m/s).

### `in_water`

```gdscript
static func in_water(ground_y: float) -> bool
```

### `flash_energy`

```gdscript
static func flash_energy(peak: float, t: float) -> float
```

Muzzle/explosion light energy over its life t in 0..1: instant peak then fast falloff.

### `sparkle_color`

```gdscript
static func sparkle_color(item: String) -> Color
```

Pickup sparkle colour per rarity-ish item hint.

### `tracer`

```gdscript
func tracer(origin: Vector3, dir: Vector2, reach: float = 28.0, color: Color = Color(1.0, 0.85, 0.5), target: Vector3 = Vector3.INF) -> void
```

Bullet/arrow streak from the shooter along `dir` (Vector2) to `reach` meters or `target`.

### `shell_casing`

```gdscript
func shell_casing(origin: Vector3, dir: Vector2, ground_y: float) -> void
```

Brass casing ejected sideways with simple ballistic motion and one bounce.

### `flash_light`

```gdscript
func flash_light(position: Vector3, color: Color = Color(1.0, 0.75, 0.4), peak: float = 4.0, life: float = 0.09, range_m: float = 7.0) -> void
```

Short-lived warm light at the muzzle / blast site; budgeted per tier.

### `swing_trail`

```gdscript
func swing_trail(origin: Vector3, dir: Vector2, reach: float = 1.9) -> void
```

Fading arc ribbon for a melee swing in front of `origin`.

### `spray`

```gdscript
func spray(position: Vector3, direction: Vector3, color: Color, count: int = 14, speed: float = 4.0) -> void
```

Directional particle spray (blood/ichor) along `direction`.

### `impact`

```gdscript
func impact(position: Vector3, material: String, normal: Vector3 = Vector3.UP) -> void
```

Material-aware impact (metal sparks / wood chips / dirt dust...). `normal` is the surface bounce direction.

### `shock_ring`

```gdscript
func shock_ring(position: Vector3, color: Color, radius: float, seconds: float) -> void
```

Expanding ring (shockwave / ripple); budgeted. `ripple` rings are thin and flat.

### `explosion`

```gdscript
func explosion(position: Vector3, radius: float, color: Color = Color(1.0, 0.85, 0.55)) -> void
```

Blast: shockwave ring, ground dust, and a bright light.

### `pickup_sparkle`

```gdscript
func pickup_sparkle(position: Vector3, color: Color = Color(1.0, 0.95, 0.7)) -> void
```

Sparkles rising from a pickup/crate.

### `run_dust_color`

```gdscript
static func run_dust_color(biome: String) -> Color
```

Per-frame: water splash/ripples when wading, and a landing dust puff after a fall. `ground_y` is terrain height.
Kick-up dust colour for running feet; alpha 0 = no dust (wet or soft ground).

### `update_player`

```gdscript
func update_player(position: Vector3, ground_y: float, speed: float, delta: float, biome: String = "") -> void
```

### `handle_event`

```gdscript
func handle_event(event: Dictionary, here: Vector3, at: Vector3, biome: String) -> void
```

Server event dispatcher: `here` is the local player's position, `at` the event position (feet + 1 m), `biome` under `at`.

_7 private function(s) starting with `_` are not listed._
