# ui_pause_menu.gd

> Esc / gamepad Menu settings window: gameplay toggles, key rebinding, accessibility and language.

`res://scripts/client/ui_pause_menu.gd`

## Overview

Esc / gamepad Menu settings window: gameplay toggles, key rebinding, accessibility and language. Built in code on
the parchment theme; the game keeps running behind it (the server is authoritative, so there is no true pause).
Every control writes straight into UiSettings / UiInputRebind and emits `changed` so the layer re-applies.

## Constants

- `const UiTheme = preload("res://scripts/client/ui_theme.gd")`
- `const UiSettings = preload("res://scripts/client/ui_settings.gd")`
- `const UiInputRebind = preload("res://scripts/client/ui_input_rebind.gd")`
- `const UiLocalization = preload("res://scripts/client/ui_localization.gd")`

## Signals

- `signal changed(key: String)`
- `signal closed`

## Functions

### `is_open`

```gdscript
func is_open() -> bool
```

### `open`

```gdscript
func open() -> void
```

### `close`

```gdscript
func close() -> void
```

### `handle_capture`

```gdscript
func handle_capture(event: InputEvent) -> bool
```

Captures the next key press while a binding button is armed. Returns true when the event was consumed.

_10 private function(s) starting with `_` are not listed._
