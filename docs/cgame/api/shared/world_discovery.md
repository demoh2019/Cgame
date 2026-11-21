# world_discovery.gd

> (no header comment)

`res://scripts/shared/world_discovery.gd`

## Constants

- `const WorldPoi = preload("res://scripts/shared/world_poi.gd")` - Server-verified once-per-POI exploration and seeded save recovery.
- `const SaveValidation = preload("res://scripts/shared/save_validation.gd")`
- `const MAX_DISCOVERIES := 384`
- `const MAX_REGION := 15`
- `const MAX_SITE_ID := 9999999`
- `const SCAN_EVERY_TICKS := 20`

## Functions

### `key_for`

```gdscript
static func key_for(site: Dictionary) -> Vector2i
```

### `reveal`

```gdscript
static func reveal(world, position: Vector3, journal: Dictionary) -> Dictionary
```

### `explorer_xp`

```gdscript
static func explorer_xp(zone: int) -> float
```

### `renown`

```gdscript
static func renown(zone: int) -> int
```

### `ids`

```gdscript
static func ids(journal: Dictionary) -> Array[int]
```

### `to_saved`

```gdscript
static func to_saved(journal: Dictionary) -> Array
```

### `from_saved`

```gdscript
static func from_saved(raw: Variant, world) -> Dictionary
```

Returns {"journal": Dictionary} on success, including empty legacy
journals. All records match real sites in the current world seed.

