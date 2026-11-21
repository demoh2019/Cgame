# corpse_burn.gd

> Corpse burn-away while a ragdoll sinks: a shared-shader overlay per corpse (progress is per corpse) chars the body and glows ember edges.

`res://scripts/client/corpse_burn.gd`

## Overview

Corpse burn-away while a ragdoll sinks: a shared-shader overlay per corpse
(progress is per corpse) chars the body and glows ember edges. Display-only.

## Constants

- `const SHADER := preload("res://assets/shaders/corpse_burn.gdshader")`

## Functions

### `progress`

```gdscript
static func progress(age: float, settle: float, sink: float) -> float
```

Burn progress 0..1 over the corpse's sink phase (settles first, then burns).

### `start`

```gdscript
static func start(model: Node) -> ShaderMaterial
```

