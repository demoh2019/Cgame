extends HBoxContainer
## Albion-style ability bar: what your gear lets you do, with live cooldowns.
## Slots: weapon skill (G), weapon ultimate (Alt+G), chest (Alt+H), helmet (Alt+J),
## boots (Alt+K). Buttons are clickable; the server validates every use.

const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const GearSkills = preload("res://scripts/shared/gear_skills.gd")

const SLOT_DEFS := [
	{"key": "G", "slot": "weapon"},
	{"key": "Alt+G", "slot": "ultimate"},
	{"key": "Alt+H", "slot": "armor"},
	{"key": "Alt+J", "slot": "head"},
	{"key": "Alt+K", "slot": "feet"},
]

var client
var aim: Callable # Returns the current aim direction (Vector2).
var _buttons: Array[Button] = []
var _refresh_left := 0.0


## Text for one slot: ability name + cooldown, or the empty-slot hint.
static func slot_label(slot: String, inventory, you: Dictionary) -> String:
	match slot:
		"weapon", "ultimate":
			var skill: Dictionary = Combat.active_skill(inventory.weapon) if inventory.weapon != "" else {}
			if skill.is_empty():
				return "no weapon skill"
			var name: String = str(skill.get("id", "skill")).replace("_", " ")
			var cd: float = float(you.get("skill_cd" if slot == "weapon" else "ultimate_cd", 0.0))
			return ("%s%s" % [name, " (ult)" if slot == "ultimate" else ""]) + ("  %.0fs" % cd if cd > 0.05 else "")
		_:
			var item: String = GearSkills.equipped_in(inventory, slot)
			var gear_skill: Dictionary = GearSkills.skill_for(slot, item)
			if gear_skill.is_empty():
				return "equip %s" % {"armor": "chest", "head": "helmet", "feet": "boots"}[slot]
			var left: float = float((you.get("gear_cd", {}) as Dictionary).get(slot, 0.0))
			return str(gear_skill["id"]).replace("_", " ") + ("  %.0fs" % left if left > 0.05 else "")


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_PASS
	for entry in SLOT_DEFS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(118, 44)
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.tooltip_text = "%s - %s" % [entry["key"], entry["slot"]]
		var slot: String = entry["slot"]
		b.pressed.connect(func() -> void: _use(slot))
		add_child(b)
		_buttons.append(b)


func _use(slot: String) -> void:
	if client == null:
		return
	var dir: Vector2 = aim.call() if aim.is_valid() else Vector2.ZERO
	if dir == Vector2.ZERO:
		dir = Vector2(sin(client.yaw), cos(client.yaw))
	match slot:
		"weapon":
			client.skill(dir)
		"ultimate":
			client.skill_ultimate(dir)
		_:
			client.gear_skill(slot)


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left > 0.0 or client == null or client.inventory == null:
		return
	_refresh_left = 0.1
	for i in SLOT_DEFS.size():
		var entry: Dictionary = SLOT_DEFS[i]
		var label: String = slot_label(entry["slot"], client.inventory, client.you)
		_buttons[i].text = "%s\n%s" % [entry["key"], label]
		_buttons[i].disabled = label.ends_with("s") and label.contains("  ") # On cooldown.
