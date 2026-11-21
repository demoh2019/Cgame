# snapshot_delta.gd

> Snapshot baseline delta compression.

`res://scripts/shared/snapshot_delta.gd`

## Overview

```text
Snapshot baseline delta compression.
Inspired by Quake 3 (delta against the last acknowledged snapshot), Overwatch
netcode talks (only changed fields on the wire) and Unreal Iris (per-property dirty tracking).
State is Dictionary id(int) -> Dictionary field -> Variant. A delta holds
  "changed": {id: {field: value}}  only fields that differ from the baseline
  "added":   {id: full entity}     entities absent from the baseline
  "removed": PackedInt64Array      entity ids gone since the baseline
  "dropped": {id: Array}           (only when needed) fields deleted from a kept entity
```

## Functions

### `diff`

```gdscript
static func diff(baseline: Dictionary, current: Dictionary, tolerances: Dictionary = {}) -> Dictionary
```

`tolerances` maps field name -> float epsilon; float values (and Vector2/3) within it are not resent.

### `apply`

```gdscript
static func apply(baseline: Dictionary, delta: Dictionary) -> Dictionary
```

Returns a new state; the baseline is never mutated or aliased.

_2 private function(s) starting with `_` are not listed._
