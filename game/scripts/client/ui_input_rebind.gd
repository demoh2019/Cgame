extends RefCounted
## Rebindable keyboard actions persisted in the shared user config (Unity Input System rebinding / Unreal Enhanced
## Input player mappable keys). The polled movement actions are rebindable; the many one-shot hotkeys stay
## keycode-matched in online_main and are listed read-only in the controls help (F2).

const UiSettings = preload("res://scripts/client/ui_settings.gd")
const SECTION := "bindings"

## id, English label key, default physical keycode, optional required modifier (0 = none).
const ACTIONS := [
	["access_up", "Move up", KEY_W],
	["access_down", "Move down", KEY_S],
	["access_left", "Move left", KEY_A],
	["access_right", "Move right", KEY_D],
	["access_sprint", "Sprint", KEY_SHIFT],
	["access_crouch", "Crouch", KEY_CTRL],
	["access_pause", "Pause menu", KEY_ESCAPE],
	["access_fps", "FPS overlay", KEY_BACKSLASH],
]

## Fixed gamepad buttons for the same actions (stick clicks sprint/crouch, Menu pauses).
const PAD_DEFAULTS := {
	"access_sprint": JOY_BUTTON_LEFT_STICK,
	"access_crouch": JOY_BUTTON_RIGHT_STICK,
	"access_pause": JOY_BUTTON_START,
}


static func action_ids() -> Array:
	var ids := []
	for entry in ACTIONS:
		ids.append(entry[0])
	return ids


static func label_for(action: String) -> String:
	for entry in ACTIONS:
		if entry[0] == action:
			return entry[1]
	return action


static func default_key(action: String) -> int:
	for entry in ACTIONS:
		if entry[0] == action:
			return entry[2]
	return KEY_NONE


static func make_key_event(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode as Key
	return event


## Registers every action with its default key (idempotent) and then applies saved overrides.
static func install(config_path: String = "") -> void:
	for entry in ACTIONS:
		if not InputMap.has_action(entry[0]):
			InputMap.add_action(entry[0], 0.2)
		if InputMap.action_get_events(entry[0]).is_empty():
			InputMap.action_add_event(entry[0], make_key_event(entry[2]))
	for action in PAD_DEFAULTS:
		var button := InputEventJoypadButton.new()
		button.button_index = PAD_DEFAULTS[action] as JoyButton
		var has_pad := false
		for event in InputMap.action_get_events(action):
			has_pad = has_pad or event is InputEventJoypadButton
		if not has_pad:
			InputMap.action_add_event(action, button)
	load_bindings(config_path)


## The physical keycode currently bound to `action`, or KEY_NONE.
static func key_of(action: String) -> int:
	if not InputMap.has_action(action):
		return KEY_NONE
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return (event as InputEventKey).physical_keycode
	return KEY_NONE


static func key_text(keycode: int) -> String:
	if keycode == KEY_NONE:
		return "-"
	return OS.get_keycode_string(keycode)


## Another action already holding `keycode` (excluding `action`), or "".
static func conflict(action: String, keycode: int) -> String:
	for id in action_ids():
		if id != action and key_of(id) == keycode:
			return id
	return ""


## Rebinds `action` to `keycode`. A key already used by another rebindable action swaps with it so no action
## is left unbound. Returns the id of the swapped action or "".
static func rebind(action: String, keycode: int, persist: bool = true, config_path: String = "") -> String:
	if not action_ids().has(action) or not InputMap.has_action(action) or \
			keycode == KEY_NONE or keycode < 0 or keycode > 16777215:
		return ""
	var swapped := conflict(action, keycode)
	var previous := key_of(action)
	_set_key(action, keycode)
	if swapped != "":
		_set_key(swapped, previous)
	if persist:
		save_bindings(config_path)
	return swapped


static func _set_key(action: String, keycode: int) -> void:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	if keycode != KEY_NONE:
		InputMap.action_add_event(action, make_key_event(keycode))


static func reset(persist: bool = true, config_path: String = "") -> void:
	for entry in ACTIONS:
		_set_key(entry[0], entry[2])
	if persist:
		save_bindings(config_path)


## Stores only bindings that differ from the defaults.
static func save_bindings(config_path: String = "") -> int:
	var file_path := config_path if config_path != "" else UiSettings.path
	var config := ConfigFile.new()
	config.load(file_path)
	if config.has_section(SECTION):
		config.erase_section(SECTION)
	for entry in ACTIONS:
		var code := key_of(entry[0])
		if code != entry[2]:
			config.set_value(SECTION, entry[0], code)
	return config.save(file_path)


## Decode a potentially hand-edited config into one unique, complete key map.
## Swapping an occupied default is essential: replacing a binding with another
## action's default must not leave that action bound to the same key.
static func resolved_saved(raw: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for entry in ACTIONS:
		result[entry[0]] = int(entry[2])
	for entry in ACTIONS:
		var action: String = str(entry[0])
		if not raw.has(action):
			continue
		var desired: Variant = raw[action]
		if not (desired is int):
			continue
		var code: int = int(desired)
		if code <= 0 or code > 16777215 or code == int(entry[2]):
			continue
		var old: int = int(result[action])
		if code == old:
			continue
		var owner: String = ""
		for other in ACTIONS:
			if int(result[other[0]]) == code:
				owner = str(other[0])
				break
		result[action] = code
		if not owner.is_empty():
			result[owner] = old
	return result


static func load_bindings(config_path: String = "") -> void:
	var file_path := config_path if config_path != "" else UiSettings.path
	var config := ConfigFile.new()
	if config.load(file_path) != OK or not config.has_section(SECTION):
		return
	var saved: Dictionary = {}
	for entry in ACTIONS:
		var action: String = str(entry[0])
		if config.has_section_key(SECTION, action):
			saved[action] = config.get_value(SECTION, action)
	var resolved: Dictionary = resolved_saved(saved)
	for entry in ACTIONS:
		_set_key(entry[0], int(resolved[entry[0]]))
