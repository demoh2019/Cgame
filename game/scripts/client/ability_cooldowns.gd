extends RefCounted
## Read-only client bridge for authoritative ability cooldowns.
## Never grants ability use: the server validates all requests.
const SLOT_TAGS := {
	"weapon": "Ability.Weapon",
	"ultimate": "Ability.Ultimate",
	"armor": "Ability.Armor",
	"head": "Ability.Head",
	"feet": "Ability.Feet",
}
const GROUP_TAG := "Ability.Global"


static func make_native() -> Object:
	if not ClassDB.class_exists("GameplayCooldownTracker"):
		return null
	return ClassDB.instantiate("GameplayCooldownTracker")


static func _safe_seconds(value: Variant) -> float:
	if not (value is int or value is float):
		return 0.0
	var seconds: float = float(value)
	if not is_finite(seconds) or seconds <= 0.0:
		return 0.0
	return minf(seconds, 604800.0)


static func raw_remaining(slot: String, you: Dictionary) -> float:
	match slot:
		"weapon":
			return _safe_seconds(you.get("skill_cd", 0.0))
		"ultimate":
			return _safe_seconds(you.get("ultimate_cd", 0.0))
		"armor", "head", "feet":
			var gear = you.get("gear_cd", {})
			return _safe_seconds(gear.get(slot, 0.0)) if gear is Dictionary else 0.0
	return 0.0


## The shared lock only exists when the server sends ability_global_cd.
static func snapshot(you: Dictionary) -> Dictionary:
	var active: Dictionary = {}
	for slot in SLOT_TAGS:
		var remaining: float = raw_remaining(slot, you)
		if remaining > 0.0:
			active[StringName(SLOT_TAGS[slot])] = remaining
	var group_seconds: float = _safe_seconds(you.get("ability_global_cd", 0.0))
	if group_seconds > 0.0:
		active[StringName(GROUP_TAG)] = group_seconds
	return active


static func format_remaining(seconds: float) -> String:
	if not is_finite(seconds) or seconds <= 0.05:
		return ""
	return ("  %.1fs" % seconds) if seconds < 1.0 else ("  %.0fs" % seconds)


static func display_remaining(slot: String, you: Dictionary, tracker: Object = null) -> float:
	if not SLOT_TAGS.has(slot):
		return 0.0
	if tracker != null and tracker.has_method("get_effective_remaining"):
		return maxf(0.0, float(tracker.call("get_effective_remaining",
			StringName(SLOT_TAGS[slot]), StringName(GROUP_TAG))))
	return maxf(raw_remaining(slot, you), _safe_seconds(you.get("ability_global_cd", 0.0)))

## Scoped reconciliation: server owns Ability.*, while Local.* may hold
## short client-side button feedback. Older forks use whole snapshots.
static func reconcile_native(tracker: Object, you: Dictionary) -> bool:
	if tracker == null:
		return false
	var authoritative: Dictionary = snapshot(you)
	if tracker.has_method("replace_cooldown_branch"):
		return bool(tracker.call("replace_cooldown_branch", &"Ability", authoritative))
	if tracker.has_method("replace_snapshot"):
		return bool(tracker.call("replace_snapshot", authoritative))
	return false


const FEEDBACK_SECONDS := 0.22
const FEEDBACK_PREFIX := "Local.UI.Activation."


## Records a short visual press, NOT an ability cooldown. The server still
## accepts or rejects the ability independently; the UI must not infer success.
static func record_activation_feedback(tracker: Object, slot: String) -> bool:
	if tracker == null or not SLOT_TAGS.has(slot) or \
			not tracker.has_method("replace_cooldown_branch") or \
			not tracker.has_method("set_remaining"):
		return false
	return bool(tracker.call("set_remaining", StringName(FEEDBACK_PREFIX + slot),
		FEEDBACK_SECONDS))


static func activation_feedback_active(tracker: Object, slot: String) -> bool:
	if tracker == null or not SLOT_TAGS.has(slot) or \
			not tracker.has_method("replace_cooldown_branch") or \
			not tracker.has_method("get_remaining"):
		return false
	return float(tracker.call("get_remaining",
		StringName(FEEDBACK_PREFIX + slot))) > 0.0

