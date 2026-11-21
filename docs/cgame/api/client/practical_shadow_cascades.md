# practical_shadow_cascades.gd

> PSSM quality policy for outdoor sun shadows.

`res://scripts/client/practical_shadow_cascades.gd`

## Overview

PSSM quality policy for outdoor sun shadows. This chooses only the depth
partition; it does not change shadow-map resolution, cascade count or
GPU sampling. High/Ultra use the native quantized logarithmic/uniform blend.
The existing Godot split properties stay the fallback for stock engines.

## Constants

- `const NEAR_PLANE := 0.35`

## Functions

### `plan`

```gdscript
static func plan(level: int, renderer: String, shadow_distance: float) -> Dictionary
```

### `try_apply`

```gdscript
static func try_apply(sun: DirectionalLight3D, level: int, renderer: String) -> bool
```

Return true if the new native API handled the plan. Repeated requests
are valid and idempotent; there is no fallback upload in that case.

