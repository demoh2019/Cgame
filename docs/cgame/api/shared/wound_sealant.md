# wound_sealant.gd

> Paid, nonstacking field dressing against physical zombie melee infection.

`res://scripts/shared/wound_sealant.gd`

## Overview

Paid, nonstacking field dressing against physical zombie melee infection.
Acid, ambient spores, injury damage, bleeding and PvP remain unchanged.

## Constants

- `const ITEM_ID := "wound_sealant"`
- `const DURATION_SECONDS := 90.0`
- `const INFECTION_FACTOR := 0.55`

## Functions

### `mitigate`

```gdscript
static func mitigate(infection: float, remaining: float) -> float
```

