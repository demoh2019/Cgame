# graphics_frame_pacing.gd

> Frame pacing like UE5 r.VSync / t.MaxFPS and Unity's targetFrameRate: steady frame delivery beats a higher but jittery average in an action RPG.

`res://scripts/client/graphics_frame_pacing.gd`

## Overview

Frame pacing like UE5 r.VSync / t.MaxFPS and Unity's targetFrameRate:
steady frame delivery beats a higher but jittery average in an action RPG.
Performance caps to the display refresh to save battery; Ultra uses
mailbox (low-latency, tear-free) where the driver supports it.

## Constants

- `const FALLBACK_REFRESH := 60.0`

## Functions

### `display_refresh`

```gdscript
static func display_refresh() -> float
```

### `settings`

```gdscript
static func settings(level: int, refresh_hz: float) -> Dictionary
```

### `apply`

```gdscript
static func apply(level: int) -> Dictionary
```

