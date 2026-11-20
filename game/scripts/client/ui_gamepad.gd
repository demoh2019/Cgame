extends RefCounted
## Gamepad support for the keyboard-first client: pad buttons are translated into the key presses the HUD
## already understands, and on-screen prompts follow the last device used (Unity Input System control schemes with
## glyph switching, Unreal CommonUI input-type-aware action widgets). The left stick already drives
## ui_left/right/up/down, which the movement code reads.

const UiLocalization = preload("res://scripts/client/ui_localization.gd")
const UiInputRebind = preload("res://scripts/client/ui_input_rebind.gd")

enum Device { KEYBOARD, GAMEPAD }

## Pad button -> [keycode the existing hotkey handler listens for, prompt caption key].
const BUTTON_KEYS := {
	JOY_BUTTON_A: [KEY_E, "Interact"],
	JOY_BUTTON_B: [KEY_Q, "Loot"],
	JOY_BUTTON_X: [KEY_F, "Attack"],
	JOY_BUTTON_Y: [KEY_I, "Inventory"],
	JOY_BUTTON_LEFT_SHOULDER: [KEY_G, "Skill"],
	JOY_BUTTON_RIGHT_SHOULDER: [KEY_SPACE, "Dodge"],
	JOY_BUTTON_DPAD_UP: [KEY_C, "Craft"],
	JOY_BUTTON_DPAD_LEFT: [KEY_K, "Skills"],
	JOY_BUTTON_DPAD_RIGHT: [KEY_J, "Map"],
	JOY_BUTTON_BACK: [KEY_F2, "Controls"],
}
const PROMPT_ORDER := [JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_RIGHT_SHOULDER]

## Glyph text per layout. Xbox-style names for generic pads, symbols for PlayStation-style ones.
const GLYPHS_XBOX := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_DPAD_UP: "D-Up",
	JOY_BUTTON_DPAD_LEFT: "D-Left", JOY_BUTTON_DPAD_RIGHT: "D-Right", JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu"}
const GLYPHS_PLAYSTATION := {JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle", JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle",
	JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1", JOY_BUTTON_DPAD_UP: "D-Up",
	JOY_BUTTON_DPAD_LEFT: "D-Left", JOY_BUTTON_DPAD_RIGHT: "D-Right", JOY_BUTTON_BACK: "Share", JOY_BUTTON_START: "Options"}

static var last_device: int = Device.KEYBOARD


## Which device an input event came from, or -1 when it should not change the prompts (mouse motion is noise
## on a pad, tiny stick drift likewise).
static func device_of(event: InputEvent) -> int:
	if event is InputEventKey:
		return Device.KEYBOARD
	if event is InputEventMouseButton:
		return Device.KEYBOARD
	if event is InputEventMouseMotion:
		return Device.KEYBOARD if (event as InputEventMouseMotion).relative.length() > 2.0 else -1
	if event is InputEventJoypadButton:
		return Device.GAMEPAD
	if event is InputEventJoypadMotion:
		return Device.GAMEPAD if absf((event as InputEventJoypadMotion).axis_value) > 0.5 else -1
	return -1


## Updates `last_device` from an event; true when the device actually changed.
static func observe(event: InputEvent) -> bool:
	var device := device_of(event)
	if device == -1 or device == last_device:
		return false
	last_device = device
	return true


static func is_playstation(joy_name: String) -> bool:
	var lowered := joy_name.to_lower()
	return lowered.contains("ps4") or lowered.contains("ps5") or lowered.contains("playstation") \
		or lowered.contains("dualshock") or lowered.contains("dualsense")


static func glyph(button: int, playstation: bool = false) -> String:
	var table: Dictionary = GLYPHS_PLAYSTATION if playstation else GLYPHS_XBOX
	return str(table.get(button, "?"))


## Synthesised key event for a pad button (null when unmapped) so existing hotkeys work from a controller.
static func key_event_for(button: int, pressed: bool) -> InputEventKey:
	if not BUTTON_KEYS.has(button):
		return null
	var event := InputEventKey.new()
	var code: int = BUTTON_KEYS[button][0]
	event.keycode = code as Key
	event.physical_keycode = code as Key
	event.pressed = pressed
	return event


## One-line prompt strip for the current device, e.g. "[E] Interact  [F] Attack" or "(A) Interact  (X) Attack".
static func prompt_line(device: int, playstation: bool = false, locale: String = "") -> String:
	var parts := []
	for button in PROMPT_ORDER:
		var entry: Array = BUTTON_KEYS[button]
		var caption := UiLocalization.t(entry[1], locale)
		if device == Device.GAMEPAD:
			parts.append("(%s) %s" % [glyph(button, playstation), caption])
		else:
			parts.append("[%s] %s" % [OS.get_keycode_string(entry[0] as Key), caption])
	if device == Device.GAMEPAD:
		parts.append("(%s) %s" % [glyph(JOY_BUTTON_START, playstation), UiLocalization.t("Pause menu", locale)])
	else:
		parts.append("[%s] %s" % [UiInputRebind.key_text(UiInputRebind.key_of("access_pause")), UiLocalization.t("Pause menu", locale)])
	return "  ".join(parts)
