# outpost_watch.gd

> (no header comment)

`res://scripts/shared/outpost_watch.gd`

## Constants

- `const MIN_FORTIFICATION := 1` - Defenders' tier-one watchtower. Only a live owner with a fortified banner can receive a signal; no enemy IDs, counts or stealth state are exposed.
- `const ALERT_COOLDOWN := 90.0`

## Functions

### `ready`

```gdscript
static func ready(site: Dictionary, owner: int, now: float, occupants: Dictionary) -> bool
```

### `activate`

```gdscript
static func activate(site: Dictionary, now: float) -> Dictionary
```

