# native_infected_senses.gd

> Optional native AI stimulus memory used by server-authoritative infected.

`res://scripts/shared/native_infected_senses.gd`

## Overview

Optional native AI stimulus memory used by server-authoritative infected.
The existing sight, hearing, wind, cover, safe-zone, and threat rules decide
whether a stimulus is valid. This adapter records only accepted signals.
It also works on stock Godot, which lacks the custom Cgame native classes.

## Constants

- `const DEFAULT_SIGHT_MEMORY := 6.0`
- `const DEFAULT_SOUND_MEMORY := 3.5`

## Functions

### `has_native_vision`

```gdscript
func has_native_vision() -> bool
```

### `has_native_hearing`

```gdscript
func has_native_hearing() -> bool
```

### `has_ranked_hearing`

```gdscript
func has_ranked_hearing() -> bool
```

### `has_native_history`

```gdscript
func has_native_history() -> bool
```

### `record_confirmed_sight`

```gdscript
func record_confirmed_sight(observer: Vector2, position: Vector2, radius: float, visible: bool, delta: float, source_id: int = -1) -> void
```

### `record_confirmed_sound`

```gdscript
func record_confirmed_sound(listener: Vector2, source: Vector2, radius: float, source_id: int = -1) -> bool
```

### `advance_time`

```gdscript
func advance_time(delta: float) -> void
```

### `remembers_sight`

```gdscript
func remembers_sight() -> bool
```

### `last_seen_position`

```gdscript
func last_seen_position() -> Vector2
```

### `remembers_sound`

```gdscript
func remembers_sound() -> bool
```

### `last_heard_position`

```gdscript
func last_heard_position() -> Vector2
```

### `best_confirmed_stimulus`

```gdscript
func best_confirmed_stimulus(sense: int) -> Dictionary
```

### `best_confirmed_stimulus_in_radius`

```gdscript
func best_confirmed_stimulus_in_radius(sense: int, center: Vector2, radius: float) -> Dictionary
```

Unreal-style perception range query over *previously approved* stimuli.
This filters stale remote locations during chase recovery without sensing
any new player, changing target selection, or exposing server-only memory.

### `best_confirmed_stimulus_for_source_in_radius`

```gdscript
func best_confirmed_stimulus_for_source_in_radius(sense: int, source_id: int, center: Vector2, radius: float) -> Dictionary
```

Actor-scoped read of a previously authorized sound/sight, bounded to our
present pursuit leash. It neither senses a new event nor sets a target.
On older forks use the source-aware, bounded history snapshot; on stock
Godot there is no extra memory to query.

### `forget_confirmed_source`

```gdscript
func forget_confirmed_source(source_id: int, sense: int = -1) -> int
```

A server-authoritative source became invalid (disconnect, death, safe hub).
Only forget its identified history entries; do not reset other survivors'
perceptions or fabricate fresh events. Older binaries safely do nothing.

### `get_recent_confirmed_stimuli`

```gdscript
func get_recent_confirmed_stimuli(limit: int = 8) -> Array
```

### `get_debug_snapshot`

```gdscript
func get_debug_snapshot() -> Dictionary
```

### `reset`

```gdscript
func reset() -> void
```

_1 private function(s) starting with `_` are not listed._
