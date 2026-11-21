# graphics_vram_budget.gd

> GPU memory budget (UE5 r.Streaming.PoolSize / texture budget, Unity memory budget): watches live video memory and, under sustained pressure, asks Auto qualit...

`res://scripts/client/graphics_vram_budget.gd`

## Overview

GPU memory budget (UE5 r.Streaming.PoolSize / texture budget, Unity
memory budget): watches live video memory and, under sustained
pressure, asks Auto quality to step down before the driver starts
paging/evicting (the source of multi-second hitches on 8 GB machines).

## Constants

- `const BUDGET_MB := [1536.0, 2560.0, 4096.0, 6144.0]`
- `const PRESSURE := 0.92 # Share of the budget that counts as pressure.`
- `const RELIEF := 0.75 # Upgrades are blocked above this share.`
- `const SUSTAIN := 2.0`

## Functions

### `budget_bytes`

```gdscript
static func budget_bytes(level: int) -> float
```

### `used_bytes`

```gdscript
static func used_bytes() -> float
```

### `upgrade_allowed`

```gdscript
static func upgrade_allowed(used: float, level: int) -> bool
```

### `sample`

```gdscript
func sample(used: float, level: int, delta: float) -> bool
```

True once memory has stayed above the pressure line for SUSTAIN seconds.

