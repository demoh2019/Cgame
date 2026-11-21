# graphics_tonemapping.gd

> One renderer-native filmic curve, shared by online and offline worlds.

`res://scripts/client/graphics_tonemapping.gd`

## Overview

One renderer-native filmic curve, shared by online and offline worlds.
AgX is native in this Cgame engine fork; ACES remains the low-cost fallback.
There is no LUT, extra postprocessing pass, or additional render target.

## Functions

### `settings`

```gdscript
static func settings(level: int, rendering_method: String) -> Dictionary
```

### `apply`

```gdscript
static func apply(env: Environment, level: int, rendering_method: String) -> void
```

