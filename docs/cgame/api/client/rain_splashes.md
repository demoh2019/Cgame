# rain_splashes.gd

> Raindrop splashes on the ground around the player (RDR2 / Ghost of Tsushima): in a downpour the ground "boils" with tiny bouncing droplets.

`res://scripts/client/rain_splashes.gd`

## Overview

Raindrop splashes on the ground around the player (RDR2 / Ghost of Tsushima):
in a downpour the ground "boils" with tiny bouncing droplets. One camera-local
GPU emitter on a flat box at the player's ground height; density follows rain.

## Constants

- `const AMOUNTS := [0, 120, 260, 420]`

## Functions

### `density`

```gdscript
static func density(storm: float, sheltered: bool) -> float
```

Splash density (0..1) for rain intensity; drizzle barely splashes.

### `update_view`

```gdscript
func update_view(ground_center: Vector3, storm: float, sheltered: bool, level: int) -> void
```

_1 private function(s) starting with `_` are not listed._
