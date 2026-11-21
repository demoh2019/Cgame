# trace_capture.gd

> Unreal-Insights-style trace capture with Chrome / Perfetto trace export and frame-regression comparison.

`res://scripts/shared/trace_capture.gd`

## Overview

```text
Unreal-Insights-style trace capture with Chrome / Perfetto trace export and frame-regression comparison.

Format reference: "Trace Event Format" (Chrome / catapult project, BSD-3-Clause documentation),
consumed by chrome://tracing, ui.perfetto.dev (Apache-2.0) and speedscope (MIT).
Design inspired by the scope/counter/frame-marker model of Tracy (BSD-3-Clause) and
Unreal Insights (concepts only; no code copied). Implementation is original.

Usage:
  var tr := TraceCapture.new(); tr.enabled = true
  tr.begin("physics"); ...; tr.end()          # nested scopes per thread
  tr.measure("ai", func(): return think())    # scope around a callable
  tr.frame_marker(Engine.get_process_frames())
  tr.save("user://trace.json")                # open in ui.perfetto.dev
  TraceCapture.compare(baseline_stats, tr.frame_stats(), 10.0)

Scopes are stored as complete ("X") events written when the scope ends, so a ring buffer that
overwrites old events can never leave an orphaned begin/end pair.
```

## Documented variables

- `var enabled: bool = false` - Master switch. When false every recording call returns immediately.
- `var max_events: int = 65536` - Ring buffer capacity in events; the oldest events are overwritten.
- `var max_frames: int = 4096` - Number of per-frame records kept for frame_stats().

## Functions

### `begin`

```gdscript
func begin(name: String, category: String = "game") -> void
```

Opens a scope on the calling thread.

### `end`

```gdscript
func end() -> void
```

Closes the innermost open scope on the calling thread (no-op if none).

### `measure`

```gdscript
func measure(name: String, callable: Callable, category: String = "game") -> Variant
```

Runs `callable` inside a scope and returns its result.

### `counter`

```gdscript
func counter(name: String, value: float) -> void
```

### `instant`

```gdscript
func instant(name: String, args: Dictionary = {}) -> void
```

### `frame_marker`

```gdscript
func frame_marker(frame_index: int) -> void
```

Marks a frame boundary and closes the per-frame aggregates used by frame_stats().

### `flow_start`

```gdscript
func flow_start(id: int, name: String) -> void
```

Starts a flow arrow (task hand-off); pair with flow_end(id, name) on the consuming thread.

### `flow_end`

```gdscript
func flow_end(id: int, name: String) -> void
```

### `set_thread_name`

```gdscript
func set_thread_name(name: String) -> void
```

### `event_count`

```gdscript
func event_count() -> int
```

### `clear`

```gdscript
func clear() -> void
```

### `frames`

```gdscript
func frames() -> Array
```

Frames as consumed by HitchCorrelator.correlate(): [{"ms", "scopes", "counters", "index"}].

### `export_chrome_json`

```gdscript
func export_chrome_json() -> String
```

Chrome Trace Event Format JSON (open in chrome://tracing or ui.perfetto.dev).

### `save`

```gdscript
func save(path: String) -> bool
```

### `frame_stats`

```gdscript
func frame_stats() -> Dictionary
```

Per-scope totals over captured frames: {"frames": n, "scopes": {name: {"total", "avg", "max"}}} in usec.

### `save_stats_json`

```gdscript
func save_stats_json(path: String) -> bool
```

### `load_stats_json`

```gdscript
static func load_stats_json(path: String) -> Dictionary
```

Returns {} when the file is missing or malformed.

### `compare`

```gdscript
static func compare(baseline: Dictionary, current: Dictionary, threshold_pct: float = 10.0) -> Array
```

Scopes whose average frame cost grew by more than threshold_pct versus the baseline,
worst first: [{"scope", "baseline_avg", "current_avg", "pct"}]. New/zero-baseline scopes are skipped.

_2 private function(s) starting with `_` are not listed._
