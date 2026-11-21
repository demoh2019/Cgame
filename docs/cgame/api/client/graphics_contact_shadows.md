# graphics_contact_shadows.gd

> Cinematic screen-space contact shadows for the ONE existing sun/moon.

`res://scripts/client/graphics_contact_shadows.gd`

## Overview

Cinematic screen-space contact shadows for the ONE existing sun/moon.
The native Cgame renderer skips the depth prepass and SSCS GPU work when
all eligible lights disable contact shadows. Not a new light or shadow map.

Unreal and Unity HDRP use contact shadows to resolve small opaque objects
that cannot contribute meaningful silhouettes in distant shadow cascades.
This pass is expensive relative to a simple shadow lookup, so we reserve
it for high-end Forward+ and tune softness for foliage and small rocks.

## Functions

### `settings`

```gdscript
static func settings(level: int, rendering_method: String) -> Dictionary
```

### `apply`

```gdscript
static func apply(sun: DirectionalLight3D, level: int, rendering_method: String) -> void
```

Idempotent quality switch; leaves the existing cascades, PCSS, sun color
and dynamic shadow opacity untouched. Never run this once per frame.

