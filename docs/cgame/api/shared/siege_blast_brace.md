# siege_blast_brace.gd

> (no header comment)

`res://scripts/shared/siege_blast_brace.gd`

## Constants

- `const Structures = preload("res://scripts/shared/structures.gd")` - Timed, single-use blast resistance for an authenticated owner's wall. No client-provided wall ID, position, shield percentage or timer.
- `const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")`
- `const ITEM_ID := "siege_blast_brace"`
- `const REACH := 3.0`
- `const DURATION := 180.0`
- `const BLOCK_FRACTION := 0.55`

## Functions

### `nearest`

```gdscript
static func nearest(world, player, walls: Dictionary, braces: Dictionary, charges: Dictionary, now: float) -> Dictionary
```

### `active`

```gdscript
static func active(braces: Dictionary, id: int, now: float) -> bool
```

### `absorb`

```gdscript
static func absorb(braces: Dictionary, id: int, damage: float, now: float) -> Dictionary
```

### `sweep`

```gdscript
static func sweep(braces: Dictionary, walls: Dictionary, now: float) -> void
```

