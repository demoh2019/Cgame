# visual_script_library.gd

> Safe default function library for visual-script call nodes (Albion After gameplay hooks).

`res://scripts/shared/visual_script_library.gd`

## Overview

Safe default function library for visual-script call nodes (Albion After gameplay hooks).
Original code; the whitelist idea (scripts only reach host-registered callables, never
arbitrary Object.call) is a standard sandboxing pattern. No third-party code ported.

Every function takes Variant arguments and validates them, so a bad graph yields a
recorded error and a neutral return value instead of a script error.

## Constants

- `const FUNCTION_NAMES: Array[String] = ["random_range", "distance", "format", "spawn_effect", "clamp01", "lerp_f"]`

## Documented variables

- `var effects: Array[Dictionary] = []` - spawn_effect requests: {"effect": String, "position": Variant}. The host consumes these.

## Functions

### `install`

```gdscript
func install(graph: RefCounted) -> Array[String]
```

Registers the default functions on a graph. Returns registration errors (empty on success).

### `register_host`

```gdscript
static func register_host(graph: RefCounted, fn_name: String, callable: Callable, argc: int) -> String
```

Registers a host function with name and argument-count checking. Returns "" or an error.

### `random_range`

```gdscript
func random_range(lo: Variant, hi: Variant) -> float
```

### `distance`

```gdscript
func distance(a: Variant, b: Variant) -> float
```

### `format`

```gdscript
func format(template: Variant, value: Variant) -> String
```

Replaces the first "{}" in the template with the value.

### `spawn_effect`

```gdscript
func spawn_effect(effect_name: Variant, position: Variant) -> bool
```

### `clamp01`

```gdscript
func clamp01(v: Variant) -> float
```

### `lerp_f`

```gdscript
func lerp_f(a: Variant, b: Variant, t: Variant) -> float
```

_3 private function(s) starting with `_` are not listed._
