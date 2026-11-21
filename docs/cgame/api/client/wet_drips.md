# wet_drips.gd

> After-rain drips (RDR2 detail): when you leave a downpour, water keeps dripping from clothes and hair for about a minute, thinning out as you dry.

`res://scripts/client/wet_drips.gd`

## Overview

After-rain drips (RDR2 detail): when you leave a downpour, water keeps
dripping from clothes and hair for about a minute, thinning out as you dry.
CPU particles on the local character only; off on Performance.

## Constants

- `const DRY_SECONDS := 60.0`

## Functions

### `next_soak`

```gdscript
static func next_soak(soak: float, storm: float, sheltered: bool, delta: float) -> float
```

Soak timer update: rain (storm > 0.3, not sheltered) refills it, dry air drains it.

### `drip_rate`

```gdscript
static func drip_rate(soak: float, storm: float, sheltered: bool) -> float
```

Drips only once the rain has stopped (or you are under cover) and you are still wet.

### `update_view`

```gdscript
func update_view(storm: float, sheltered: bool, level: int, delta: float) -> void
```

_1 private function(s) starting with `_` are not listed._
