extends HBoxContainer
## Albion-style ability bar: what your gear lets you do, with live cooldowns.
## Slots: weapon skill (G), weapon ultimate (Alt+G), chest (Alt+H), helmet (Alt+J),
## boots (Alt+K). Buttons are clickable; the server validates every use.

const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const GearSkills = preload("res://scripts/shared/gear_skills.gd")
const AbilityCooldowns = preload("res://scripts/client/ability_cooldowns.gd")

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
var _cooldown_tracker: Object = null
var _last_snapshot_received: int = -1


## Text for one slot: ability name + cooldown, or the empty-slot hint.
static func slot_label(slot: String, inventory, you: Dictionary, cooldown_override: float = -1.0) -> String:
	match slot:
		"weapon", "ultimate":
			var skill: Dictionary = Combat.active_skill(inventory.weapon) if inventory.weapon != "" else {}
			if skill.is_empty():
				return "no weapon skill"
			var name: String = str(skill.get("id", "skill")).replace("_", " ")
			var mastery: int = int((you.get("weapon_mastery", {}) as Dictionary).get("level", 0))
			if slot == "weapon" and mastery > 0:
				name += " M%d" % mastery
			var cd: float = cooldown_override if cooldown_override >= 0.0 else AbilityCooldowns.raw_remaining(slot, you)
			return ("%s%s" % [name, " (ult)" if slot == "ultimate" else ""]) + AbilityCooldowns.format_remaining(cd)
		_:
			var item: String = GearSkills.equipped_in(inventory, slot)
			var gear_skill: Dictionary = GearSkills.skill_for(slot, item)
			if gear_skill.is_empty():
				return "equip %s" % {"armor": "chest", "head": "helmet", "feet": "boots"}[slot]
			var left: float = cooldown_override if cooldown_override >= 0.0 else AbilityCooldowns.raw_remaining(slot, you)
			return str(gear_skill["id"]).replace("_", " ") + AbilityCooldowns.format_remaining(left)


func _ready() -> void:
	_cooldown_tracker = AbilityCooldowns.make_native()
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
	# Client-only press pulse: never pretend the server accepted the action.
	AbilityCooldowns.record_activation_feedback(_cooldown_tracker, slot)
	match slot:
		"weapon":
			client.skill(dir)
		"ultimate":
			client.skill_ultimate(dir)
		_:
			client.gear_skill(slot)


func _process(delta: float) -> void:
	# A native explicit-tick clock tracks display timers between packets.
	if _cooldown_tracker != null and _cooldown_tracker.has_method("tick"):
		_cooldown_tracker.call("tick", delta)
	_refresh_left -= delta
	if _refresh_left > 0.0 or client == null or client.inventory == null:
		return
	_refresh_left = 0.1
	if _cooldown_tracker != null:
		# Only reconcile on a NEW authoritative packet; stale packets should
		# not repeatedly reset the native countdown on every UI refresh.
		if _last_snapshot_received != int(client.snapshots_received):
			if AbilityCooldowns.reconcile_native(_cooldown_tracker, client.you):
				_last_snapshot_received = int(client.snapshots_received)
	for i in SLOT_DEFS.size():
		var entry: Dictionary = SLOT_DEFS[i]
		var slot: String = str(entry["slot"])
		var remaining: float = AbilityCooldowns.display_remaining(slot, client.you, _cooldown_tracker)
		var label: String = slot_label(slot, client.inventory, client.you, remaining)
		if AbilityCooldowns.activation_feedback_active(_cooldown_tracker, slot):
			label += " •"
		_buttons[i].text = "%s\n%s" % [entry["key"], label]
		# Cosmetic/UI only; _use still sends to server-owned gameplay validation.
		_buttons[i].disabled = remaining > 0.05
