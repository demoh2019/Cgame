# ui_settings.gd

> Client-only accessibility and interface preferences.

`res://scripts/client/ui_settings.gd`

## Overview

Client-only accessibility and interface preferences. They live in the same ConfigFile as the graphics
quality (Unity PlayerPrefs / UE GameUserSettings equivalent), in their own sections, and never touch the
authoritative simulation. All helpers are static so they can be unit-tested without a scene.

## Constants

- `const DEFAULT_PATH := "user://albion_after_graphics.cfg"`
- `const SECTION := "interface"`
- `const COLORBLIND_NAMES := ["Off", "Protanopia", "Deuteranopia", "Tritanopia"]`
- `const UI_SCALE_MIN := 0.75`
- `const UI_SCALE_MAX := 1.75`
- `const CAPTION_SIZES := [14, 18, 24]`
- `const LOCALES := ["en", "ru"]`
- `const DEFAULTS := {`

## Functions

### `reset_defaults`

```gdscript
static func reset_defaults() -> void
```

### `load_all`

```gdscript
static func load_all() -> void
```

### `save_all`

```gdscript
static func save_all() -> int
```

### `get_value`

```gdscript
static func get_value(key: String)
```

### `set_value`

```gdscript
static func set_value(key: String, value, persist: bool = true) -> void
```

### `sanitize`

```gdscript
static func sanitize(key: String, value)
```

Coerces a stored value to the type and range of its default, so a hand-edited file cannot break the UI.

### `shake_scale`

```gdscript
static func shake_scale() -> float
```

Multiplier for camera shake (Unreal "Camera Shake Scale", Cinemachine impulse gain).

### `flash_scale`

```gdscript
static func flash_scale() -> float
```

Multiplier for full-screen flashes; reduced mode removes them rather than dimming a strobe.

### `resolve_hold`

```gdscript
static func resolve_hold(toggle: bool, pressed: bool, previous: bool, state: bool) -> Array
```

Hold-to-toggle for sprint and crouch. `toggle` selects the mode; `pressed` is the raw key state this frame,
`previous` last frame's, `state` the latched value. Returns [active, new_state].

### `cycle_scale`

```gdscript
static func cycle_scale(current: float, step: float) -> float
```

