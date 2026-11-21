# perf_overlay.gd

> Unified in-game performance panel: frame/GPU/process/physics time, draw calls, VRAM, static memory, object/node counts, pipeline compilations and custom sour...

`res://scripts/client/perf_overlay.gd`

## Overview

```text
Unified in-game performance panel: frame/GPU/process/physics time, draw calls, VRAM, static
memory, object/node counts, pipeline compilations and custom sources (streaming queues, ...),
with rolling graphs, p50/p95/p99 stats, budget lines and hitch markers labelled with their cause.

Design references (ideas only, no code copied): Unreal `stat unit` / Insights live view and the
Unity Profiler overlay. Percentile math is the standard linear-interpolation definition.
Original implementation for this project.

Cost model: every frame pushes ~10 floats into fixed ring buffers (no allocation); the panel
only redraws at REDRAW_HZ and only while visible.

  var perf := preload("res://scripts/client/perf_overlay.gd").new()
  add_child(perf); perf.add_source("stream_queue", func() -> float: return float(q.size()))
  perf.toggle()  # F3        perf.cycle_mode()  # Shift+F3
```

## Constants

- `enum Mode { COMPACT, FULL, GRAPHS }`
- `const FrameHitchAnalyzer = preload("res://scripts/client/frame_hitch_analyzer.gd")`
- `const HitchCorrelator = preload("res://scripts/shared/hitch_correlator.gd")`
- `const HISTORY := 300 # frames kept per series`
- `const STATS_WINDOW := 300 # frames used for percentiles`
- `const REDRAW_HZ := 10.0`
- `const BUDGET_60 := 16.6`
- `const BUDGET_30 := 33.3`
- `const MAX_MARKERS := 32`
- `const GRAPH_W := 240.0`
- `const GRAPH_H := 38.0`
- `const PAD := 8.0`
- `const BUILTIN: Array = [` - Built-in series: name -> [label, unit, is_time_ms]

## Classes

- `class Ring extends RefCounted:` - Fixed-capacity ring of floats.
- `class PerfStats extends RefCounted:` - Headless-testable rolling statistics keyed by series name.
- `class Canvas extends Control:` - Draws the panel; the overlay owns all state.

## Documented variables

- `var trace: RefCounted` - Optional TraceCapture for per-scope hitch culprits in snapshot().
- `var loaded_cells_source: Callable` - Optional Callable -> int feeding hitch cause "streaming".

## Functions

### `add_source`

```gdscript
func add_source(source_name: String, source: Callable) -> void
```

Registers a custom monitor (e.g. streaming queue size). The Callable must return a number.

### `remove_source`

```gdscript
func remove_source(source_name: String) -> void
```

### `toggle`

```gdscript
func toggle() -> void
```

### `cycle_mode`

```gdscript
func cycle_mode() -> int
```

### `mode_name`

```gdscript
func mode_name() -> String
```

### `record_hitch`

```gdscript
func record_hitch(hitch: Dictionary) -> void
```

Feeds a hitch record from an external FrameHitchAnalyzer ({"ms","cause","time",...}).

### `sample`

```gdscript
func sample(delta: float) -> void
```

Samples every monitor once. Public so tests and headless tools can drive it.

### `snapshot`

```gdscript
func snapshot() -> Dictionary
```

Machine-readable state for bug reports.

### `hitch_summary`

```gdscript
func hitch_summary() -> String
```

_8 private function(s) starting with `_` are not listed._
