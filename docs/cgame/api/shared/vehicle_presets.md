# vehicle_presets.gd

> Vehicle config presets and an editor-style validator for vehicle_dynamics.gd.

`res://scripts/shared/vehicle_presets.gd`

## Overview

Vehicle config presets and an editor-style validator for vehicle_dynamics.gd.

Numbers are plausible engineering magnitudes tuned for gameplay (not from any licensed
dataset). Tire coefficients follow typical magic-formula magnitudes from Pacejka's
public literature; structure follows Marco Monster's "Car Physics for Games".

## Constants

- `const DIFF_TYPES: Array[String] = ["open", "locked", "limited_slip"]`

## Functions

### `salvage_bike`

```gdscript
static func salvage_bike() -> Dictionary
```

Light salvage motorcycle: two wheels, self-balancing torque, leans into corners.

### `pickup_truck`

```gdscript
static func pickup_truck() -> Dictionary
```

Heavy rear-drive pickup: open diff, anti-roll bars, long gearing.

### `dune_buggy`

```gdscript
static func dune_buggy() -> Dictionary
```

Light long-travel dune buggy: limited-slip rear diff, soft suspension.

### `validate`

```gdscript
static func validate(config: Dictionary) -> Array[String]
```

Editor-style checker: returns human-readable problems, empty when the config is sound.

_1 private function(s) starting with `_` are not listed._
