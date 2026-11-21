# perf_regression.gd

> Performance regression comparison between two runs (e.g.

`res://scripts/tools/perf_regression.gd`

## Overview

Performance regression comparison between two runs (e.g. two commits), with
noise-aware aggregation (median of N runs) and a soak-test leak detector.
Original code (MIT-compatible); statistics are textbook least squares.

## Constants

- `const METRICS: Array[String] = [`
- `const DEFAULT_THRESHOLD_PCT: float = 10.0`

## Functions

### `compare_runs`

```gdscript
static func compare_runs(baseline: Dictionary, current: Dictionary, thresholds: Dictionary) -> Dictionary
```

baseline/current: either a flat {metric: value} dict or {"runs": [flat dicts]}.
thresholds: {metric_or_"default": max allowed % increase}; optional key
"noise_factor" (default 0.5) widens the limit by that share of run spread.

### `load_json`

```gdscript
static func load_json(path: String) -> Dictionary
```

### `save_json`

```gdscript
static func save_json(path: String, data: Dictionary) -> bool
```

### `memory_leak_trend`

```gdscript
static func memory_leak_trend(samples: PackedFloat32Array, min_growth_pct: float = 5.0, min_r2: float = 0.8) -> Dictionary
```

Least-squares slope of memory samples over a soak run. Flags a leak when the
fit is strong (r2) and total growth exceeds min_growth_pct of the mean.

_3 private function(s) starting with `_` are not listed._
