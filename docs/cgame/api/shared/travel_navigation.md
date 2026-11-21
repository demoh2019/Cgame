# travel_navigation.gd

> A north-up, purely visual compass for the user's own caravan and party rally.

`res://scripts/shared/travel_navigation.gd`

## Overview

A north-up, purely visual compass for the user's own caravan and party
rally. Never selects or accepts targets from other survivors' snapshots.

## Constants

- `const LABELS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]`

## Functions

### `target`

```gdscript
static func target(data: Variant, x_key: String, z_key: String) -> Vector2
```

### `distance_meters`

```gdscript
static func distance_meters(origin: Vector2, destination: Vector2) -> int
```

### `compass`

```gdscript
static func compass(origin: Vector2, destination: Vector2) -> String
```

### `valid_destination`

```gdscript
static func valid_destination(destination: Vector2, world_radius: float) -> bool
```

Convert a local pointer in the full-island map into a private waypoint.
Invalid/off-island clicks are rejected instead of producing a fake route.

### `world_from_map`

```gdscript
static func world_from_map(pointer: Vector2, bounds: Rect2, span: float, world_radius: float) -> Vector2
```

### `project`

```gdscript
static func project(origin: Vector2, destination: Vector2, map_size: Vector2, world_radius: float = 72.0, inset: float = 0.44) -> Dictionary
```

Projection returns one point inside a radar if the marker is near;
otherwise returns a clipped edge pointer in the direction of the marker.
No geometry is produced for missing/malformed private waypoint data.

