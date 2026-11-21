# moon_visuals.gd

> Render-only lunar cycle.

`res://scripts/client/moon_visuals.gd`

## Overview

Render-only lunar cycle. Authoritative server time is the sole clock:
joining halfway through a night gives the same moon on every client.
Keep it independent from combat, visibility and survival simulation.

## Constants

- `const WorldCycle = preload("res://scripts/shared/world_cycle.gd")`
- `const SYNODIC_DAYS := 29.530588`

## Functions

### `phase_at`

```gdscript
static func phase_at(world_seconds: float) -> float
```

0 = new, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter.
A new world begins with a full moon for a readable first night.

### `illuminated_fraction`

```gdscript
static func illuminated_fraction(phase: float) -> float
```

### `directional_fill`

```gdscript
static func directional_fill(phase: float) -> float
```

Never extinguish existing moonlit gameplay scenery: the moon phase
modulates only the artistic directional fill, not ambient night lighting.

