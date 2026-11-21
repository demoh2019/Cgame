extends RefCounted
## Presentation-only Unreal-style Gameplay Cues bridge.
## The server owns statuses, damage and network replication; cues only trigger VFX.
const STATUS_TAGS := {
	"stagger_seconds": "GameplayCue.Status.Staggered",
	"snared_seconds": "GameplayCue.Status.Snared",
	"sunder_seconds": "GameplayCue.Status.Sundered",
	"resolve_seconds": "GameplayCue.Status.Resolve",
}
const PULSE_TAGS := {
	"Runtime.Status.Sundered": "GameplayCue.Status.Sundered",
	"Runtime.Status.Resolve": "GameplayCue.Status.Resolve",
}
## Niagara-style effect priority: visible Resolve stacks beat ambient debuff
## pulses during cue queue saturation; no combat or status value changes.
const PULSE_PRIORITY := {
	"Runtime.Status.Sundered": 4,
	"Runtime.Status.Resolve": 6,
}


static func attach(node: Node) -> void:
	if node != null and ClassDB.class_exists("GameplayCueQueue"):
		node.set_meta("gameplay_cues", ClassDB.instantiate("GameplayCueQueue"))


## Source of truth is the replicated actor's current status, not an invented timer.
static func active_snapshot(kind: String, state: Dictionary) -> Dictionary:
	var active: Dictionary = {}
	if kind != "zombie":
		return active
	for source in STATUS_TAGS:
		var raw = state.get(source, 0.0)
		if not (raw is int or raw is float):
			continue
		var seconds: float = float(raw)
		if not is_finite(seconds) or seconds <= 0.0:
			continue
		var stacks: int = 1
		if source == "resolve_seconds":
			stacks = int(state.get("resolve_stacks", 0))
			if stacks < 2:
				continue
		active[StringName(STATUS_TAGS[source])] = clampi(stacks, 1, 65535)
	return active


static func sync(node: Node, kind: String, state: Dictionary) -> void:
	if node == null:
		return
	var cues: Object = node.get_meta("gameplay_cues", null) as Object
	if cues != null and cues.has_method("replace_active"):
		var server_status: Dictionary = active_snapshot(kind, state)
		# Only server-owned Status.* may be replaced from replication.
		# Persistent Local.* / FX.* cues have independent lifetimes.
		if cues.has_method("replace_active_branch"):
			cues.call("replace_active_branch", &"GameplayCue.Status", server_status, 2)
		else:
			# Older Cgame binaries retain the original whole-snapshot path.
			cues.call("replace_active", server_status, 2)


## Bridge repeated native EffectTimeline pulse counts to one cue per tag.
## Stock Godot keeps periodic VFX through a compatibility event array.
static func frame_events(node: Node, periodic: Dictionary) -> Array:
	var cues: Object = null
	if node != null:
		cues = node.get_meta("gameplay_cues", null) as Object
	if cues != null and cues.has_method("emit_cue") and cues.has_method("take_events"):
		# Build one bounded cosmetic batch from the native effect timeline.
		# Server-authoritative statuses are not changed by cue admission.
		var batch: Array[Dictionary] = []
		for status in periodic:
			var cue_tag: String = str(PULSE_TAGS.get(str(status), ""))
			if cue_tag.is_empty():
				continue
			var raw = periodic[status]
			if not (raw is int or raw is float) or not is_finite(float(raw)) or float(raw) <= 0.0:
				continue
			batch.append({
				"tag": StringName(cue_tag),
				"magnitude": clampf(float(raw), 0.0, 32.0),
				"priority": int(PULSE_PRIORITY.get(str(status), 4))
			})
		if not batch.is_empty():
			if cues.has_method("emit_cues_batch"):
				# Atomic admission: do not fall back to partial individual submits
				# if a validated batch cannot fit the existing visual queue.
				cues.call("emit_cues_batch", batch)
			else:
				for pulse in batch:
					cues.call("emit_cue", pulse["tag"], pulse["magnitude"], pulse["priority"])
		if cues.has_method("get_pending_count") and int(cues.call("get_pending_count")) == 0:
			return []
		return cues.call("take_events", 8) as Array
	var events: Array = []
	for status in periodic:
		var cue_tag: String = str(PULSE_TAGS.get(str(status), ""))
		if cue_tag.is_empty():
			continue
		var raw = periodic[status]
		if not (raw is int or raw is float) or not is_finite(float(raw)) or float(raw) <= 0.0:
			continue
		events.append({
			"tag": StringName(cue_tag), "event": "executed",
			"stacks": 0, "magnitude": float(periodic[status]),
			"priority": int(PULSE_PRIORITY.get(str(status), 4)), "count": 1
		})
	return events

static func pulse_color(cue_tag: String) -> Color:
	match cue_tag:
		"GameplayCue.Status.Sundered":
			return Color(1.0, 0.43, 0.15)
		"GameplayCue.Status.Resolve":
			return Color(0.70, 0.38, 1.0)
		"GameplayCue.Status.Staggered":
			return Color(0.48, 0.77, 1.0)
		"GameplayCue.Status.Snared":
			return Color(0.42, 0.96, 0.56)
	return Color.TRANSPARENT
