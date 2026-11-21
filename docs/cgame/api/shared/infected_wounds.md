# infected_wounds.gd

> Low-health infected respond visibly and mechanically to actual server damage.

`res://scripts/shared/infected_wounds.gd`

## Overview

Low-health infected respond visibly and mechanically to actual server damage.
Ordinary walkers/spitters limp; runners make a dangerous last sprint.
Brutes and raid bosses keep their established combat timings.

## Constants

- `const WOUND_THRESHOLD := 0.35`
- `const LIMP_SPEED_FACTOR := 0.65`
- `const ELITE_LIMP_SPEED_FACTOR := 0.82`
- `const FRENZY_SPEED_FACTOR := 1.18`
- `const ELITE_FRENZY_SPEED_FACTOR := 1.09`

## Functions

### `phase`

```gdscript
static func phase(infected) -> String
```

### `speed_factor`

```gdscript
static func speed_factor(infected) -> float
```

