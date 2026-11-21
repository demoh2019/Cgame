# soak_test.gd

> Soak test CLI for the authoritative server.

`res://scripts/tools/soak_test.gd`

## Overview

```text
Soak test CLI for the authoritative server.
  godot --headless --path game --script res://scripts/tools/soak_test.gd -- \
      --bots 40 --seconds 10 --scenario mixed --out /tmp/soak.json [--tick-rate 20] [--seed 1337] [--budget-ms X]
Exit code 1 if p95 tick time exceeds the budget (default 1000/tick_rate * 0.5 ms) or a memory
leak trend is detected (OLS slope above LEAK_SLOPE_BYTES_PER_S, over >= 5 samples).
```

## Constants

- `const LoadGenerator = preload("res://scripts/tools/load_generator.gd")`
- `const LEAK_SLOPE_BYTES_PER_S := 2.0 * 1024.0 * 1024.0`
- `const MIN_LEAK_SAMPLES := 5`

_2 private function(s) starting with `_` are not listed._
