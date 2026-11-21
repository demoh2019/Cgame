# return_rate.gd

> Albion Online-style Focus: crafting or refining "with focus" at a safe settlement workbench spends focus points and returns part of the materials (the city r...

`res://scripts/shared/return_rate.gd`

## Overview

Albion Online-style Focus: crafting or refining "with focus" at a safe
settlement workbench spends focus points and returns part of the materials
(the city resource return rate). Focus regenerates over a day, so it is a
daily budget that rewards dedicated crafters. Ordinary crafting is unchanged.

## Constants

- `const MAX_FOCUS := 10000.0`
- `const REGEN_PER_SECOND := MAX_FOCUS / 86400.0 # Full pool in 24 h.`
- `const FOCUS_RATE := 0.35 # Materials returned when crafting with focus.`
- `const REFINED_OUTPUTS := ["plank_", "bar_", "cloth_"]`

## Functions

### `focus_cost`

```gdscript
static func focus_cost(output: String, tier: int, times: int) -> int
```

Focus cost for `times` batches of a recipe producing a tier-`tier` item.

### `returned`

```gdscript
static func returned(inputs: Dictionary, rate: float, rng: RandomNumberGenerator) -> Dictionary
```

Materials returned for `inputs` (already multiplied by batches) at `rate`.
Whole part is guaranteed; the fraction is a fair roll, so the average is exact.

