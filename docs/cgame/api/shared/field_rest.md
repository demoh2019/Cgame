# field_rest.gd

> (no header comment)

`res://scripts/shared/field_rest.gd`

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")` - Paid expedition respite. Server checks live fire, combat, enemy proximity, inventory and the existing persistent 90-second rest cooldown.
- `const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")`
- `const CampRest = preload("res://scripts/shared/camp_rest.gd")`
- `const INFECTED_RADIUS := 13.0`
- `const HOSTILE_RADIUS := 10.0`
- `const HEALTH := 12.0`
- `const STAMINA := 30.0`
- `const HUNGER := 8.0`
- `const THIRST := 10.0`

## Functions

### `ration`

```gdscript
static func ration(inventory) -> String
```

### `has_supplies`

```gdscript
static func has_supplies(inventory) -> bool
```

### `danger`

```gdscript
static func danger(world, player, players: Dictionary, parties, zombies: Dictionary) -> String
```

Nearby zombies block all field healing. PvP opponents also block it where
both characters are in legal full-loot combat zones. Real party members
are not considered hostile, even while using the same field campfire.

### `recover`

```gdscript
static func recover(inventory, vitals) -> bool
```

Atomic material debit. Hub rest remains more efficient than field rest.

