# smart_provisions.gd

> (no header comment)

`res://scripts/shared/smart_provisions.gd`

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")` - Pure, deterministic server-side selection for safe survival provisions. This module never consumes items: the authoritative cmd_use does that.
- `const MIN_NEED := 15.0`
- `const SECONDARY_BENEFIT := 0.85`
- `const VALUE_PENALTY := 0.12`
- `const TIER_PENALTY := 2.5`
- `const PRESERVE_DUAL_MEAL := 12.0`

## Functions

### `pick`

```gdscript
static func pick(inventory, survivor, intent: String) -> String
```

