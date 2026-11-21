# road_travel.gd

> (no header comment)

`res://scripts/shared/road_travel.gd`

## Constants

- `const FOOT_BONUS := 0.08` - Shared server/client rules: seeded dirt roads change travel grip.
- `const ROAD_BIKE_GRIP := 1.04`

## Functions

### `coverage`

```gdscript
static func coverage(world, pos: Vector3) -> float
```

### `foot_factor`

```gdscript
static func foot_factor(world, pos: Vector3, crouched: bool) -> float
```

### `bike_surface`

```gdscript
static func bike_surface(base: float, road: float) -> float
```

### `on_road`

```gdscript
static func on_road(world, pos: Vector3) -> bool
```

