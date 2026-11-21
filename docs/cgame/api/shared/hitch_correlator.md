# hitch_correlator.gd

> Explains frame hitches: for each frame slower than a threshold, names the scopes that grew most versus the rolling median of preceding frames and the counter...

`res://scripts/shared/hitch_correlator.gd`

## Overview

Explains frame hitches: for each frame slower than a threshold, names the scopes that grew most
versus the rolling median of preceding frames and the counters that jumped.
Original implementation (median-baseline attribution as used by common frame profilers).

## Constants

- `const WINDOW := 60`
- `const TOP_SCOPES := 3`

## Functions

### `correlate`

```gdscript
static func correlate(frames: Array, threshold_ms: float) -> Array
```

frames: [{"ms": float, "scopes": {name: usec}, "counters": {name: value}}]
Returns [{"index", "ms", "baseline_ms", "culprits": [{"scope","usec","median_usec","growth_usec"}],
"counters": [{"name","value","median"}]}] in frame order.

_2 private function(s) starting with `_` are not listed._
