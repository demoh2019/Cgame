# vfx_graph.gd

> Niagara-style data-driven VFX graph runtime (CPU simulation, structure-of-arrays).

`res://scripts/client/vfx_graph.gd`

## Overview

```text
Niagara-style data-driven VFX graph runtime (CPU simulation, structure-of-arrays).

An emitter is a Dictionary asset:
  {"spawn": [modules], "update": [modules], "max_particles": int, "duration": float,
   "attributes": {custom_float_name: default}, "events": {"death": spec, "collision": spec}}
A system asset groups emitters: {"emitters": {name: emitter_asset, ...}}.
An event spec is {"emitter": name, "count": n, "inherit_velocity": 0..1} (or an Array of them);
it routes a death/collision to a spawn in another emitter of the same system, the CPU analogue
of Niagara GPU event routing. collide_plane also accepts "on_event" directly.

Spawn modules: spawn_rate, spawn_burst, initial_position_sphere/box/cone, initial_velocity,
lifetime_random, initial_color, initial_size, initial_attribute.
Update modules: gravity, drag, curl_noise, vortex, attractor, color_over_life, size_over_life,
collide_plane, kill_below_plane (the two plane modules run after integration).

Design inspired by Niagara's emitter/module/event-handler model (concepts only, no third-party
code ported; curl noise uses Godot's FastNoiseLite, MIT). Original implementation, project license.
```

## Constants

- `const POST_MODULES: PackedStringArray = ["collide_plane", "kill_below_plane"]`
- `const EMISSION_MODULES: PackedStringArray = ["spawn_rate", "spawn_burst"]`
- `const OFFSET_A := Vector3(0.0, 0.0, 0.0)`
- `const OFFSET_B := Vector3(31.4, 17.2, 5.9)`
- `const OFFSET_C := Vector3(-12.7, 44.1, 23.3)`

## Classes

- `class Attr extends RefCounted:`
- `class Emitter extends RefCounted:`

## Functions

### `create_system`

```gdscript
static func create_system(asset: Dictionary, seed_value: int) -> Dictionary
```

### `set_budget`

```gdscript
static func set_budget(system: Dictionary, particles_left: int) -> void
```

Total live-particle budget for the next tick (-1 = unlimited).

### `tick`

```gdscript
static func tick(system: Dictionary, delta: float) -> void
```

### `particle_count`

```gdscript
static func particle_count(system: Dictionary, emitter: String) -> int
```

### `total_particles`

```gdscript
static func total_particles(system: Dictionary) -> int
```

### `get_emitter`

```gdscript
static func get_emitter(system: Dictionary, emitter: String) -> Emitter
```

### `attribute`

```gdscript
static func attribute(system: Dictionary, emitter: String, attr_name: String) -> Variant
```

Copy of one attribute's live range: position, velocity, color, size, age, lifetime or a custom name.

### `is_finished`

```gdscript
static func is_finished(system: Dictionary) -> bool
```

