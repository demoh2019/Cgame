# ui_access.gd

> Runtime glue the game loop calls every frame: rebindable movement polling with hold/toggle latching, UI scale and the high-contrast interface theme.

`res://scripts/client/ui_access.gd`

## Overview

Runtime glue the game loop calls every frame: rebindable movement polling with hold/toggle latching, UI scale and
the high-contrast interface theme. Static so online_main only needs one-line calls.

## Constants

- `const UiSettings = preload("res://scripts/client/ui_settings.gd")`
- `const UiInputRebind = preload("res://scripts/client/ui_input_rebind.gd")`
- `const UiTheme = preload("res://scripts/client/ui_theme.gd")`

## Functions

### `read_move`

```gdscript
static func read_move() -> Dictionary
```

Movement, sprint and crouch from the (rebindable) actions. Call once per physics frame.

### `clear_latches`

```gdscript
static func clear_latches() -> void
```

### `apply_ui_scale`

```gdscript
static func apply_ui_scale(window: Window) -> void
```

### `apply_high_contrast`

```gdscript
static func apply_high_contrast(enabled: bool) -> void
```

Pure-white outlined text on the over-world theme and black ink on parchment, thicker outlines.
Edits the shared Theme resources in place so every live Label updates immediately; `false` restores them.

### `high_contrast_active`

```gdscript
static func high_contrast_active() -> bool
```

