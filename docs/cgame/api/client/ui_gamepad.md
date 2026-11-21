# ui_gamepad.gd

> Gamepad support for the keyboard-first client: pad buttons are translated into the key presses the HUD already understands, and on-screen prompts follow the ...

`res://scripts/client/ui_gamepad.gd`

## Overview

Gamepad support for the keyboard-first client: pad buttons are translated into the key presses the HUD
already understands, and on-screen prompts follow the last device used (Unity Input System control schemes with
glyph switching, Unreal CommonUI input-type-aware action widgets). The left stick already drives
ui_left/right/up/down, which the movement code reads.

## Constants

- `const UiLocalization = preload("res://scripts/client/ui_localization.gd")`
- `const UiInputRebind = preload("res://scripts/client/ui_input_rebind.gd")`
- `enum Device { KEYBOARD, GAMEPAD }`
- `const BUTTON_KEYS := {` - Pad button -> [keycode the existing hotkey handler listens for, prompt caption key].
- `const PROMPT_ORDER := [JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_RIGHT_SHOULDER]`
- `const GLYPHS_XBOX := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",` - Glyph text per layout. Xbox-style names for generic pads, symbols for PlayStation-style ones.
- `const GLYPHS_PLAYSTATION := {JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle", JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle",`

## Functions

### `device_of`

```gdscript
static func device_of(event: InputEvent) -> int
```

Which device an input event came from, or -1 when it should not change the prompts (mouse motion is noise
on a pad, tiny stick drift likewise).

### `observe`

```gdscript
static func observe(event: InputEvent) -> bool
```

Updates `last_device` from an event; true when the device actually changed.

### `is_playstation`

```gdscript
static func is_playstation(joy_name: String) -> bool
```

### `glyph`

```gdscript
static func glyph(button: int, playstation: bool = false) -> String
```

### `key_event_for`

```gdscript
static func key_event_for(button: int, pressed: bool) -> InputEventKey
```

Synthesised key event for a pad button (null when unmapped) so existing hotkeys work from a controller.

### `prompt_line`

```gdscript
static func prompt_line(device: int, playstation: bool = false, locale: String = "") -> String
```

One-line prompt strip for the current device, e.g. "[E] Interact  [F] Attack" or "(A) Interact  (X) Attack".

