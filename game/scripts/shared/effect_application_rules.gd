extends RefCounted
## Native Unreal-style Gameplay Effect application gates for server-owned PvE statuses.
## Static, validated rule cache. Stock Godot uses identical fail-closed rules.
const CROWD := "Effect.CrowdControl"
const STAGGER := "Effect.CrowdControl.Stagger"
const SNARE := "Effect.CrowdControl.Snare"
const SUNDER := "Effect.Debuff.Sunder"

static var _gate: Object = null
static var _checked := false


static func _native_gate() -> Object:
	if _checked:
		return _gate
	_checked = true
	if not ClassDB.class_exists("GameplayEffectApplicationGate"):
		return null
	var gate: Object = ClassDB.instantiate("GameplayEffectApplicationGate")
	if gate == null:
		return null
	# Shared parent requirements apply to *every* CrowdControl descendant.
	if not bool(gate.call("set_rule", StringName(CROWD),
			PackedStringArray(["Life.Alive"]),
			PackedStringArray(["Rank.RaidBoss", "Immunity.CrowdControl"]))):
		return null
	if not bool(gate.call("set_rule", StringName(SUNDER),
			PackedStringArray(["Life.Alive"]),
			PackedStringArray(["Immunity.Sunder"]))):
		return null
	_gate = gate
	return _gate


## Only the server calls this for actual gameplay. The additional tag array
## permits future buffs/gear to grant scoped immunity without engine edits.
static func can_apply(effect: String, alive: bool, raid_boss: bool,
		extra_tags: PackedStringArray = PackedStringArray()) -> bool:
	var tags := PackedStringArray()
	tags.append("Life.Alive" if alive else "Life.Dead")
	if raid_boss:
		tags.append("Rank.RaidBoss")
	tags.append_array(extra_tags)
	var native: Object = _native_gate()
	if native != null and native.has_method("can_apply"):
		return bool(native.call("can_apply", StringName(effect), tags))
	# Same allowlisted checks are enforced when the custom engine is absent.
	if not alive:
		return false
	if effect.begins_with(CROWD + "."):
		if raid_boss or _has(extra_tags, "Immunity.CrowdControl"):
			return false
		return true
	if effect == SUNDER:
		return not _has(extra_tags, "Immunity.Sunder")
	return false


static func _has(tags: PackedStringArray, required: String) -> bool:
	for tag in tags:
		if tag == required or tag.begins_with(required + "."):
			return true
	return false


static func native_reason(effect: String, alive: bool, raid_boss: bool,
		extra_tags: PackedStringArray = PackedStringArray()) -> String:
	var native: Object = _native_gate()
	if native == null:
		return "unavailable"
	var tags := PackedStringArray(["Life.Alive" if alive else "Life.Dead"])
	if raid_boss:
		tags.append("Rank.RaidBoss")
	tags.append_array(extra_tags)
	return str(native.call("get_failure_reason", StringName(effect), tags))
