# field_threat_scanner.gd

> A paid, single-use recon sweep for high-risk PvE expeditions.

`res://scripts/shared/field_threat_scanner.gd`

## Overview

A paid, single-use recon sweep for high-risk PvE expeditions.
The server selects living targets. Players never submit coordinates or IDs.
Results and the follow-up moving pin belong only to the owner snapshot.

## Constants

- `const ITEM_ID := "field_threat_scanner"`
- `const SCAN_RADIUS := 145.0`
- `const TRACK_RADIUS := 170.0`
- `const MARK_SECONDS := 50.0`

## Functions

### `nearest`

```gdscript
static func nearest(at: Vector3, zombies: Dictionary) -> Dictionary
```

Raid encounters take precedence over elites; inside a category choose
the nearest survivor-visible threat, breaking ties by stable server ID.

### `public_mark`

```gdscript
static func public_mark(state: Dictionary, zombies: Dictionary, at: Vector3, now: float) -> Dictionary
```

The mark can follow its target briefly but cannot follow an infected
across the world, survive its death or outlive the original paid scan.

