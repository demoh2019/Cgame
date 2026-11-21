# physics_world_fx.gd

> One client-only entry point for cosmetic physics and world interactivity: server events in, debris / blasts / plant shakes out, plus the per-frame player gra...

`res://scripts/client/physics_world_fx.gd`

## Overview

One client-only entry point for cosmetic physics and world interactivity: server events in, debris / blasts /
plant shakes out, plus the per-frame player grass bend. Owns physics_debris.gd and plant_interaction.gd.
It reads events and positions but never writes anything back to the simulation.
See docs/ENGINE_PARITY_FX.md ("Physics and world interactivity").

## Constants

- `const PhysicsDebris = preload("res://scripts/client/physics_debris.gd")`
- `const PlantInteraction = preload("res://scripts/client/plant_interaction.gd")`

## Functions

### `blast_for`

```gdscript
static func blast_for(event_type: String) -> Vector2
```

Blast field for an event type as Vector2(radius m, impulse m/s); ZERO when the event does not push things.

### `chunk_strength_for`

```gdscript
static func chunk_strength_for(event_type: String) -> float
```

Events that spawn chunk debris, with the strength of the burst.

### `setup`

```gdscript
func setup(world) -> void
```

### `on_event`

```gdscript
func on_event(event: Dictionary, at: Vector3) -> void
```

### `update`

```gdscript
func update(delta: float, player: Vector3) -> void
```

