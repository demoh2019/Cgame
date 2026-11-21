# render_benchmark.gd

> Deterministic CPU frame pacing summaries for screenshot/demo GPU research.

`res://scripts/client/render_benchmark.gd`

## Overview

Deterministic CPU frame pacing summaries for screenshot/demo GPU research.
Frame samples are process-delta milliseconds; these are not GPU timer queries.
Discard invalid warmup/stall values explicitly instead of faking high FPS.

## Constants

- `const MAX_VALID_FRAME_MS := 1000.0`

## Functions

### `summarize`

```gdscript
static func summarize(samples: Array[float]) -> Dictionary
```

### `describe`

```gdscript
static func describe(result: Dictionary) -> String
```

### `describe_gpu`

```gdscript
static func describe_gpu(result: Dictionary) -> String
```

GPU duration comes from native viewport timestamps. It does not include
game CPU work, synchronization or display V-Sync time.

_1 private function(s) starting with `_` are not listed._
