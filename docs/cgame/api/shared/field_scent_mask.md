# field_scent_mask.gd

> Scent camouflage is an inventory-paid, temporary stealth tool.

`res://scripts/shared/field_scent_mask.gd`

## Overview

Scent camouflage is an inventory-paid, temporary stealth tool.
It prevents only blood-scent acquisition: infected still see, hear,
remember, and pursue players using their normal rules.

## Constants

- `const ITEM_ID := "herbal_scent_mask"`
- `const DURATION_SECONDS := 120.0`

## Functions

### `can_apply`

```gdscript
static func can_apply(survival) -> bool
```

### `apply`

```gdscript
static func apply(survival) -> void
```

Called only by server after a successful item debit.

### `active`

```gdscript
static func active(survival) -> bool
```

