# infected_sight.gd

> (no header comment)

`res://scripts/shared/infected_sight.gd`

## Constants

- `const RangedCover = preload("res://scripts/shared/ranged_cover.gd")` - First-sighting cover for infected. Reuses authoritative bullet geometry, including procedural solids and player-built barricades. Not a client RPC.
- `const CLOSE_CONTACT := 0.2`
- `const END_TOLERANCE := 0.08`

## Functions

### `clear_path`

```gdscript
static func clear_path(world, origin: Vector3, target: Vector3) -> bool
```

