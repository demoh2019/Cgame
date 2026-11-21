# fx_scalability_policy.gd

> Native SignificanceBudgetPlanner parity and stock-Godot fallback for VFX.

`res://scripts/client/fx_scalability_policy.gd`

## Overview

Native SignificanceBudgetPlanner parity and stock-Godot fallback for VFX.
Never used for gameplay authority, hit validation, audio or networking.

## Constants

- `const MAX_DISTANCE := 140.0`
- `const FRAME_BUDGET := [8, 12, 18, 24]`
- `const POOL_RESIDENT_TARGET := [2, 4, 8, 12]` - Resident particle instances include live emitters, not only idle cache. Idle cache can shrink gradually after reducing the graphics quality.
- `const POOL_CHANGES_PER_FRAME := [1, 1, 2, 2]`
- `const POOL_WORK_USEC := [250, 400, 600, 900]` - Soft per-frame CPU microsecond time slice for idle VFX node maintenance.
- `const CAPS := [`
- `const CATEGORY_RANGES := [` - Type-specific cosmetic range (meters): dust, hits, combat, milestones. Long-range milestone feedback is preserved even at Performance quality.
- `const CATEGORY_MINIMUMS := [` - Soft per-category reservations for busy combat frames: foot dust is expendable, hit feedback and combat bursts keep a minimum share whenever eligible. Priority-3 boss/death/level-up events always bypass these minima.

## Functions

### `pool_resident_target`

```gdscript
static func pool_resident_target(quality: int) -> int
```

### `pool_changes_per_frame`

```gdscript
static func pool_changes_per_frame(quality: int) -> int
```

### `pool_work_usec`

```gdscript
static func pool_work_usec(quality: int) -> int
```

### `budget_for`

```gdscript
static func budget_for(quality: int) -> int
```

### `caps_for`

```gdscript
static func caps_for(quality: int) -> PackedInt32Array
```

### `select_indices`

```gdscript
static func select_indices(distances: PackedFloat64Array, priorities: PackedByteArray, categories: PackedByteArray, quality: int, native: Object = null) -> PackedInt32Array
```

### `select_visible_indices`

```gdscript
static func select_visible_indices(distances: PackedFloat64Array, priorities: PackedByteArray, categories: PackedByteArray, visible: PackedByteArray, quality: int, native: Object = null) -> PackedInt32Array
```

Frustum-biased admission: render on-screen VFX first within the same
urgency tier. Off-screen critical feedback still beats nearby low-priority
effects; no gameplay authority, event or audio is discarded.

### `ranges_for`

```gdscript
static func ranges_for(quality: int) -> PackedFloat64Array
```

### `select_visible_ranged_indices`

```gdscript
static func select_visible_ranged_indices(distances: PackedFloat64Array, priorities: PackedByteArray, categories: PackedByteArray, visible: PackedByteArray, quality: int, native: Object = null) -> PackedInt32Array
```

Opt-in per-category Niagara-style range admission for the real burst queue.
Existing select_visible_indices callers keep their global-range behavior.
Older native Cgame engines use the exact stock-Godot fallback.

### `minimums_for`

```gdscript
static func minimums_for(quality: int) -> PackedInt32Array
```

### `select_visible_fair_indices`

```gdscript
static func select_visible_fair_indices(distances: PackedFloat64Array, priorities: PackedByteArray, categories: PackedByteArray, visible: PackedByteArray, quality: int, native: Object = null) -> PackedInt32Array
```

Three-stage Niagara-inspired VFX plan: first all priority-3 events,
then soft category minimums, then top-significance fill. This *does not*
exceed the frame total, caps or distance ranges. Stock Godot uses the same
deterministic selection and older Cgame engines remain compatible.

