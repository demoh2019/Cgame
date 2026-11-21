# stormproof_briquette.gd

> (no header comment)

`res://scripts/shared/stormproof_briquette.gd`

## Constants

- `const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")` - One paid, shared storm-resistant fuel upgrade for temporary field fires.
- `const ITEM_ID := "stormproof_briquette"`
- `const FUEL_SECONDS := 120.0`
- `const SHIELD_SECONDS := 90.0`

## Functions

### `nearest`

```gdscript
static func nearest(campfires: Dictionary, position: Vector3, now: float) -> Dictionary
```

The server chooses a nearby living fire; no arbitrary client IDs.

### `exposed_seconds`

```gdscript
static func exposed_seconds(delta: float, now: float, fire: Dictionary) -> float
```

Exact unshielded fraction of a tick. Normal time already elapses once.
Protection is not retroactive when a tick straddles the shield deadline.

