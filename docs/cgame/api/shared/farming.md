# farming.gd

> Homestead farming (Albion Online island farming, adapted to the open world).

`res://scripts/shared/farming.gd`

## Overview

Homestead farming (Albion Online island farming, adapted to the open world).
Survivors plant seeds on up to 9 personal plots in the green zone. Crops grow in
real server time, persist with the world and can only be harvested by their owner.
Harvests yield food (or wheat for bread) and sometimes seeds back.

## Constants

- `const CROPS := {`
- `const MAX_PLOTS := 9`
- `const MAX_PLOTS_TOTAL := 600`
- `const MIN_SPACING := 1.4`
- `const PLANT_REACH := 3.0`
- `const SEED_RETURN_CHANCE := 0.35`

## Functions

### `crop_for_seed`

```gdscript
static func crop_for_seed(seed_id: String) -> String
```

### `progress`

```gdscript
static func progress(plot: Dictionary, now: float) -> float
```

Growth 0..1 at server time `now`.

### `is_ripe`

```gdscript
static func is_ripe(plot: Dictionary, now: float) -> bool
```

### `placement_refusal`

```gdscript
static func placement_refusal(zone: int, water: bool, spot: Vector2, plots: Dictionary, own_count: int) -> String
```

Why a plot cannot be placed here ("" when it can).

### `harvest_yield`

```gdscript
static func harvest_yield(crop: String, rng: RandomNumberGenerator) -> Dictionary
```

Harvest: {crop: n} plus maybe seeds back.

