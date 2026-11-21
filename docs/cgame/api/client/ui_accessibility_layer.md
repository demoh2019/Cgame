# ui_accessibility_layer.gd

> One node that owns every interface/accessibility feature that needs the scene tree: the Esc settings menu, colour-blind filter, FPS overlay, closed captions,...

`res://scripts/client/ui_accessibility_layer.gd`

## Overview

One node that owns every interface/accessibility feature that needs the scene tree: the Esc settings menu,
colour-blind filter, FPS overlay, closed captions, device-aware prompt strip, gamepad-to-hotkey translation,
UI scale and high contrast. online_main adds it once; the logic lives in the static ui_* helpers.

## Constants

- `const UiSettings = preload("res://scripts/client/ui_settings.gd")`
- `const UiLocalization = preload("res://scripts/client/ui_localization.gd")`
- `const UiInputRebind = preload("res://scripts/client/ui_input_rebind.gd")`
- `const UiColorblind = preload("res://scripts/client/ui_colorblind.gd")`
- `const UiCaptions = preload("res://scripts/client/ui_captions.gd")`
- `const UiGamepad = preload("res://scripts/client/ui_gamepad.gd")`
- `const UiAccess = preload("res://scripts/client/ui_access.gd")`
- `const GraphicsResolution = preload("res://scripts/client/graphics_resolution.gd")`
- `const PauseMenu = preload("res://scripts/client/ui_pause_menu.gd")`

## Functions

### `set_world_streamer`

```gdscript
func set_world_streamer(streamer: WorldStreamer) -> void
```

Assign the native streamer after it is created; diagnostic counts are
polled at 4 Hz only while the optional FPS overlay is visible.

### `setup`

```gdscript
func setup(client, camera: Camera3D, blocked: Callable = Callable()) -> void
```

`client` supplies event_received/peer_id/predicted; `camera` the listener orientation; `blocked` is optional.

### `apply_all`

```gdscript
func apply_all() -> void
```

Re-reads UiSettings and pushes them into the scene.

### `is_open`

```gdscript
func is_open() -> bool
```

### `toggle_menu`

```gdscript
func toggle_menu() -> void
```

_7 private function(s) starting with `_` are not listed._
