# survival_radar.gd

> Live north-up radar for the canonical survival game.

`res://scripts/client/survival_radar.gd`

## Overview

Live north-up radar for the canonical survival game. World entities are
read from either the authoritative offline simulation or network snapshots.
This Control never owns gameplay state or invents unobserved enemies.

## Constants

- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const RuinSurvey = preload("res://scripts/shared/ruin_survey.gd")`
- `const ProspectingChart = preload("res://scripts/shared/prospecting_chart.gd")`
- `const ThreatScan = preload("res://scripts/shared/field_threat_scanner.gd")`
- `const DeathRecovery = preload("res://scripts/shared/death_recovery.gd")`
- `const PartyCorpseRescue = preload("res://scripts/shared/party_corpse_rescue.gd")`
- `const TravelNavigation = preload("res://scripts/shared/travel_navigation.gd")`
- `const RaidCone = preload("res://scripts/shared/raid_cone.gd")`
- `const StormLightning = preload("res://scripts/shared/storm_lightning.gd")`
- `const METERS_RADIUS := 72.0`
- `const REFRESH_INTERVAL := 0.2`
- `const MAP_INSET := 0.44`

## Functions

### `map_point`

```gdscript
static func map_point(origin: Vector2, target: Vector2, map_size: Vector2, meters: float = METERS_RADIUS) -> Vector2
```

Ground coordinates: -Z points north, +X east.

### `in_range`

```gdscript
static func in_range(origin: Vector2, target: Vector2, meters: float = METERS_RADIUS) -> bool
```

### `set_personal_waypoint`

```gdscript
func set_personal_waypoint(point: Vector2) -> void
```

Strictly local, unreplicated map click destination.

### `current_position`

```gdscript
func current_position() -> Vector2
```

Query is shared with tests; the same authoritative positions drive drawing.

### `current_yaw`

```gdscript
func current_yaw() -> float
```

### `current_caravan`

```gdscript
func current_caravan() -> Dictionary
```

Only a local actor or the local private network snapshot may supply
waypoint coordinates. Other players' snapshots never carry these fields.

### `current_escort_caravan`

```gdscript
func current_escort_caravan() -> Dictionary
```

### `current_prospect_mark`

```gdscript
func current_prospect_mark() -> Dictionary
```

A scanner pin exists only in the current player's private snapshot.
A consumed chart only reveals the owner's current server-confirmed vein.

### `current_threat_scan`

```gdscript
func current_threat_scan() -> Dictionary
```

### `current_death_recovery`

```gdscript
func current_death_recovery() -> Dictionary
```

The remote server includes this destination only in the owner's "you"
snapshot. Offline mode resolves the same real tagged bag locally.

### `current_rally`

```gdscript
func current_rally() -> Dictionary
```

### `current_party_corpse_rescue`

```gdscript
func current_party_corpse_rescue() -> Dictionary
```

Authenticated party ping, with the same isolation as leader rally.

### `current_party_ping`

```gdscript
func current_party_ping() -> Dictionary
```

_7 private function(s) starting with `_` are not listed._
