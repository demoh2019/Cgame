# graphics_hdr_output.gd

> HDR10 / EDR display output (UE5 r.HDR.EnableHDROutput, Unity HDR Output).

`res://scripts/client/graphics_hdr_output.gd`

## Overview

HDR10 / EDR display output (UE5 r.HDR.EnableHDROutput, Unity HDR Output).
Uses the engine's native DisplayServer HDR swapchain when the monitor
reports support; SDR screens and low presets keep the 8-bit path.

## Constants

- `const PAPER_WHITE_NITS := 200.0`

## Functions

### `wanted`

```gdscript
static func wanted(level: int, rendering_method: String, supported: bool) -> bool
```

### `supported`

```gdscript
static func supported() -> bool
```

### `apply`

```gdscript
static func apply(level: int, rendering_method: String) -> bool
```

