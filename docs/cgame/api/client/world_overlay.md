# world_overlay.gd

> Things drawn over the 3D view at the place they belong: health bars over the infected (colour by kind, gold for elites, magenta for raid bosses, with STUN an...

`res://scripts/client/world_overlay.gd`

## Overview

Things drawn over the 3D view at the place they belong: health bars over the infected (colour by kind, gold for elites,
magenta for raid bosses, with STUN and PIN tags), damage numbers that pop up where a hit lands, and markers at the edge of
the screen for the nearest places worth walking to (name, kind colour, distance; undiscovered ones marked with "?").
It reads the client's state and the camera; it never changes the game.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const KIND_COLORS := {`
- `const MARKER_RANGE := 650.0`
- `const MARKER_COUNT := 3`
- `const ZOMBIE_BAR_BUDGET := 32 # Cosmetic HUD only; never cull 3D characters or combat.`

## Functions

### `select_zombie_bar_indices`

```gdscript
static func select_zombie_bar_indices(distances: PackedFloat64Array, priorities: PackedByteArray, budget: int = ZOMBIE_BAR_BUDGET, allow_native: bool = true) -> PackedInt32Array
```

Pure bounded choice used by the actual zombie HUD. The native engine handles
large crowds; stock Godot uses the same deterministic priority ordering.

### `select_zombie_bar_indices_stable`

```gdscript
static func select_zombie_bar_indices_stable(distances: PackedFloat64Array, priorities: PackedByteArray, ids: PackedInt64Array, retained_ids: PackedInt64Array, budget: int = ZOMBIE_BAR_BUDGET, max_distance: float = 45.0, hysteresis: float = 1.5, allow_native: bool = true) -> PackedInt32Array
```

Strict-priority HUD significance with temporal retention. A previous
ordinary zombie can only displace another ordinary zombie, not a boss.
The caller supplies stable server zombie IDs, not ephemeral array indices.

### `select_world_marker_indices`

```gdscript
static func select_world_marker_indices(positions: PackedVector3Array, viewers: PackedVector3Array, priorities: PackedByteArray, ids: PackedInt64Array, retained_ids: PackedInt64Array, budget: int = MARKER_COUNT, max_distance: float = MARKER_RANGE, hysteresis: float = 8.0, allow_native: bool = true) -> PackedInt32Array
```

Pure cosmetic POI relevance: native multi-viewer selector with stock-Godot parity.

### `select_zombie_bar_world_stable`

```gdscript
static func select_zombie_bar_world_stable(positions: PackedVector3Array, viewers: PackedVector3Array, priorities: PackedByteArray, ids: PackedInt64Array, retained_ids: PackedInt64Array, budget: int = ZOMBIE_BAR_BUDGET, max_distance: float = 45.0, hysteresis: float = 1.5, allow_native: bool = true) -> PackedInt32Array
```

Shared native world-significance planning for infected health bars.
Reuse the exact multi-viewer selector already used for POI markers.

### `setup`

```gdscript
func setup(p_client, p_camera: Camera3D) -> void
```

_8 private function(s) starting with `_` are not listed._
