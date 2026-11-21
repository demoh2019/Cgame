# raid_aggro_view.gd

> (no header comment)

`res://scripts/shared/raid_aggro_view.gd`

## Constants

- `const Threat = preload("res://scripts/shared/threat.gd")` - Read-only per-survivor RAID threat awareness. This is NOT a shared hate table: clients cannot set, transmit, or use these values for targeting. All peer identifiers in this view belong to the viewer's own party.
- `const DISPLAY_RANGE := 42.0`
- `const DISPLAY_HEIGHT := 7.0`

## Functions

### `for_viewer`

```gdscript
static func for_viewer(boss, viewer, players: Dictionary, parties, world) -> Dictionary
```

Only members of an active party close to the boss get a summary.
Never serialize raw threat entries, outside-group IDs or session tokens.

_1 private function(s) starting with `_` are not listed._
