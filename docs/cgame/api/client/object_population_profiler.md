# object_population_profiler.gd

> On-demand Unreal MemReport-style object population diagnostics.

`res://scripts/client/object_population_profiler.gd`

## Overview

On-demand Unreal MemReport-style object population diagnostics.
No per-frame work, no automatic polling, no retained scene objects, and
no native class dependency in regular release/stock Godot builds.

## Constants

- `const TRACKED_CLASSES := [`

## Functions

### `available`

```gdscript
func available() -> bool
```

### `sample`

```gdscript
func sample() -> Dictionary
```

Sample only when the user explicitly requests it. Each result contains
exact native-class counts (not subclass totals) and differences relative
to the previous explicit sample; growth does not by itself prove a leak.

### `format_report`

```gdscript
static func format_report(snapshot: Dictionary) -> String
```

### `reset_baseline`

```gdscript
func reset_baseline() -> void
```

_1 private function(s) starting with `_` are not listed._
