# smart_objects.gd

> Smart Object registry: slots, exclusive claims with timeouts, query scoring, placement scoring / automatic placement and per-behavior interaction graphs.

`res://scripts/shared/smart_objects.gd`

## Overview

Smart Object registry: slots, exclusive claims with timeouts, query scoring,
placement scoring / automatic placement and per-behavior interaction graphs.
Original implementation inspired by the public concept of Unreal Engine's
Smart Objects; no third-party source code was copied.

Object: {id, position: Vector3, tags: Array, slots: [{offset: Vector3, behavior: String, tags: Array}]}
Positions are world Vector3; 2D areas (Rect2) map x -> world x, y -> world z.
Behavior graph: array of steps {anim: String, duration: float, effect: String}.

## Documented variables

- `var on_effect: Callable = Callable()` - (effect: String, user: Variant, object_id: String) -> void

## Functions

### `register_behavior`

```gdscript
func register_behavior(behavior: String, steps: Array) -> void
```

### `register_object`

```gdscript
func register_object(obj: Dictionary) -> bool
```

### `unregister_object`

```gdscript
func unregister_object(id: String) -> void
```

### `has_object`

```gdscript
func has_object(id: String) -> bool
```

### `object_count`

```gdscript
func object_count() -> int
```

### `slot_position`

```gdscript
func slot_position(obj: Dictionary, slot_index: int) -> Vector3
```

### `is_slot_free`

```gdscript
func is_slot_free(id: String, slot_index: int) -> bool
```

### `find`

```gdscript
func find(query: Dictionary) -> Array
```

query: {position: Vector3, radius: float, required_tags: Array, preferred_tags: Array,
behavior: String, include_claimed: bool}. Returns [{object, slot, position, distance, score}],
best score first (ties: object id, slot index).

### `claim`

```gdscript
func claim(object_id: String, slot_index: int, user: Variant, timeout: float = -1.0) -> int
```

Claims a slot exclusively. Returns a handle > 0, or 0 when unavailable.
timeout < 0 uses default_claim_timeout; timeout == 0 never expires.

### `release`

```gdscript
func release(handle: int) -> bool
```

### `is_claimed`

```gdscript
func is_claimed(handle: int) -> bool
```

### `claim_user`

```gdscript
func claim_user(handle: int) -> Variant
```

### `touch`

```gdscript
func touch(handle: int) -> void
```

Resets the idle timeout of a claim (user is still on its way).

### `start_interaction`

```gdscript
func start_interaction(handle: int) -> bool
```

### `interaction_state`

```gdscript
func interaction_state(handle: int) -> Dictionary
```

Returns {step, anim, t, duration, done} or {} when not interacting.

### `advance`

```gdscript
func advance(dt: float) -> Array
```

Advances interactions and claim timeouts. Returns handles of interactions finished this call.

### `placement_score`

```gdscript
func placement_score(candidate_pos: Vector3, nav_reachable: Callable, density: float, placed: Array = [], min_spacing: float = 0.0) -> float
```

Score in [0, 1] for putting a new object at candidate_pos. 0 when unreachable or closer than
min_spacing to an existing object / `placed` position. `density` is how many neighbours
within 2.5x min_spacing are tolerated before the score falls off.

### `auto_place`

```gdscript
func auto_place(area: Rect2, count: int, rules: Dictionary, rng_seed: int) -> Array
```

Deterministic automatic placement. rules: {min_spacing, density, nav_reachable: Callable,
candidates: int (samples per object)}. Returns up to `count` positions (Vector3, y = 0).

_5 private function(s) starting with `_` are not listed._
