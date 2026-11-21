# ui_input_rebind.gd

> Rebindable keyboard actions persisted in the shared user config (Unity Input System rebinding / Unreal Enhanced Input player mappable keys).

`res://scripts/client/ui_input_rebind.gd`

## Overview

Rebindable keyboard actions persisted in the shared user config (Unity Input System rebinding / Unreal Enhanced
Input player mappable keys). The polled movement actions are rebindable; the many one-shot hotkeys stay
keycode-matched in online_main and are listed read-only in the controls help (F2).

## Constants

- `const UiSettings = preload("res://scripts/client/ui_settings.gd")`
- `const SECTION := "bindings"`
- `const ACTIONS := [` - id, English label key, default physical keycode, optional required modifier (0 = none).
- `const PAD_DEFAULTS := {` - Fixed gamepad buttons for the same actions (stick clicks sprint/crouch, Menu pauses).

## Functions

### `action_ids`

```gdscript
static func action_ids() -> Array
```

### `label_for`

```gdscript
static func label_for(action: String) -> String
```

### `default_key`

```gdscript
static func default_key(action: String) -> int
```

### `make_key_event`

```gdscript
static func make_key_event(keycode: int) -> InputEventKey
```

### `install`

```gdscript
static func install(config_path: String = "") -> void
```

Registers every action with its default key (idempotent) and then applies saved overrides.

### `key_of`

```gdscript
static func key_of(action: String) -> int
```

The physical keycode currently bound to `action`, or KEY_NONE.

### `key_text`

```gdscript
static func key_text(keycode: int) -> String
```

### `conflict`

```gdscript
static func conflict(action: String, keycode: int) -> String
```

Another action already holding `keycode` (excluding `action`), or "".

### `rebind`

```gdscript
static func rebind(action: String, keycode: int, persist: bool = true, config_path: String = "") -> String
```

Rebinds `action` to `keycode`. A key already used by another rebindable action swaps with it so no action
is left unbound. Returns the id of the swapped action or "".

### `reset`

```gdscript
static func reset(persist: bool = true, config_path: String = "") -> void
```

### `save_bindings`

```gdscript
static func save_bindings(config_path: String = "") -> int
```

Stores only bindings that differ from the defaults.

### `load_bindings`

```gdscript
static func load_bindings(config_path: String = "") -> void
```

_1 private function(s) starting with `_` are not listed._
