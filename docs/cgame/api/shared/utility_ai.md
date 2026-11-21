# utility_ai.gd

> Utility AI (Dave Mark's Infinite Axis Utility System, as used by the UE5 Utility AI plugins and Guild Wars 2): each option is scored by multiplying normalise...

`res://scripts/shared/utility_ai.gd`

## Overview

Utility AI (Dave Mark's Infinite Axis Utility System, as used by the UE5
Utility AI plugins and Guild Wars 2): each option is scored by multiplying
normalised considerations shaped by response curves, with a compensation
factor so options with many considerations are not unfairly punished.

## Constants

- `enum Response { LINEAR, QUADRATIC, INVERSE_QUADRATIC, LOGISTIC, STEP }`

## Functions

### `curve`

```gdscript
static func curve(kind: int, x: float, slope: float = 1.0, shift: float = 0.0) -> float
```

### `combine`

```gdscript
static func combine(scores: PackedFloat32Array) -> float
```

Product of considerations with IAUS compensation.

### `best`

```gdscript
static func best(scores: PackedFloat32Array) -> int
```

Index of the best scoring option (ties keep the earliest; -1 if all zero).

