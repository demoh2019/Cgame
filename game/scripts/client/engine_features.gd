extends RefCounted
## Runtime detection of optional native engine classes, so scripts run on older editor binaries too.
## Everything touching a custom class goes through ClassDB.instantiate / set / call, so scripts parse without it.


static func has(engine_class: String) -> bool:
	return ClassDB.class_exists(engine_class)


## Tags a node with Gameplay Tags (meta "tags") when the engine provides GameplayTagContainer; a no-op otherwise.
static func tag_node(node: Node, tags: Array) -> void:
	if node == null:
		return
	if has("GameplayTagContainer"):
		var container = ClassDB.instantiate("GameplayTagContainer")
		for tag in tags:
			container.add_tag(StringName(str(tag)))
		node.set_meta("tags", container)
	# Counted status effects are separate from boolean identity tags.
	# Neither class is required by stock Godot binaries.
	if has("GameplayTagStackContainer"):
		node.set_meta("tag_stacks", ClassDB.instantiate("GameplayTagStackContainer"))
	if has("GameplayEffectTimeline"):
		node.set_meta("effect_timeline", ClassDB.instantiate("GameplayEffectTimeline"))


## Creates an engine class by name and applies properties; returns null when the binary lacks it.
static func make(engine_class: String, props: Dictionary = {}) -> Object:
	if not ClassDB.class_exists(engine_class):
		return null
	var obj: Object = ClassDB.instantiate(engine_class)
	if obj == null:
		return null
	for key in props:
		obj.set(key, props[key])
	return obj


## Radial physics push (RadialForceField3D) around a world position; false when the class is missing.
## Bodies on the ragdoll layer (1 << 19) are pushed by default.
static func radial_push(parent: Node, at: Vector3, radius: float, strength: float,
		upward: float = 0.4, mask: int = 1 << 19, wall_mask: int = 0,
		wall_attenuation: float = 0.25, velocity_change: bool = false,
		falloff_mode: int = 1) -> bool:
	var field := make("RadialForceField3D", {
		"radius": radius, "strength": strength, "falloff": falloff_mode, "upward_bias": upward,
		"collision_mask": mask, "free_after_fire": true}) as Node3D
	if field == null:
		return false
	# Some older fork binaries have RadialForceField3D but not the new
	# impulse/occlusion API. Fall back to the script implementation rather
	# than silently ignoring wall shielding or changing debris mass response.
	if (wall_mask != 0 or velocity_change) and (
			not field.has_method("set_occlusion_mask") or
			not field.has_method("set_mass_independent")):
		field.free()
		return false
	if wall_mask != 0:
		field.set("occlusion_mask", wall_mask)
		field.set("occlusion_attenuation", wall_attenuation)
		field.set("max_occlusion_rays", 24)
	if velocity_change:
		field.set("mass_independent", true)
	parent.add_child(field)
	field.global_position = at
	field.call("fire")
	return true

## The native engine owns the live tag container. Snapshot states are read-only
## hints for visuals/tools; server combat authority is never inferred from tags.
static func runtime_tags(kind: String, state: Dictionary) -> PackedStringArray:
	var tags := PackedStringArray()
	if kind == "player":
		tags.append("Runtime.Life.Alive" if bool(state.get("alive", false)) else "Runtime.Life.Dead")
		if bool(state.get("mounted", false)):
			tags.append("Runtime.Movement.Mounted")
		if bool(state.get("crouching", false)):
			tags.append("Runtime.Movement.Crouching")
		if bool(state.get("outlaw", false)):
			tags.append("Runtime.Status.Outlaw")
		if bool(state.get("flare_lit", false)):
			tags.append("Runtime.Item.FlareLit")
	elif kind == "zombie":
		tags.append("Runtime.Life.Alive" if float(state.get("hp", 0.0)) > 0.0 else "Runtime.Life.Dead")
		if int(state.get("state", 0)) >= 2:
			tags.append("Runtime.Combat.Alert")
		if bool(state.get("elite", false)):
			tags.append("Runtime.Rank.Elite")
		if bool(state.get("raid_boss", false)):
			tags.append("Runtime.Rank.RaidBoss")
		if bool(state.get("raid_enraged", false)):
			tags.append("Runtime.Status.Enraged")
		if bool(state.get("melee_blocked", false)):
			tags.append("Runtime.Status.Blocked")
		if float(state.get("stagger_seconds", 0.0)) > 0.0:
			tags.append("Runtime.Status.Staggered")
		if float(state.get("snared_seconds", 0.0)) > 0.0:
			tags.append("Runtime.Status.Snared")
		if float(state.get("sunder_seconds", 0.0)) > 0.0:
			tags.append("Runtime.Status.Sundered")
		if int(state.get("resolve_stacks", 0)) >= 2 and float(state.get("resolve_seconds", 0.0)) > 0.0:
			tags.append("Runtime.Status.Resolve")
	return tags


## Replaces one namespace atomically, preserving static Enemy/Player identity.
## Old engine binaries simply retain the established rendering paths.
static func sync_runtime_tags(node: Node, kind: String, snapshot: Dictionary) -> void:
	if node == null:
		return
	var container: Object = node.get_meta("tags", null) as Object
	if container != null and container.has_method("replace_tag_branch"):
		container.call("replace_tag_branch", StringName("Runtime"), runtime_tags(kind, snapshot))
	# A complete, validated snapshot prevents stale effect stacks after expiry.
	if node.has_meta("tag_stacks"):
		var stack_container: Object = node.get_meta("tag_stacks") as Object
		if stack_container != null and stack_container.has_method("replace_stacks"):
			var counts: Dictionary = {}
			for tag in runtime_tags(kind, snapshot):
				counts[StringName(tag)] = 1
			var resolve_tag := StringName("Runtime.Status.Resolve")
			if counts.has(resolve_tag):
				counts[resolve_tag] = clampi(int(snapshot.get("resolve_stacks", 0)), 2, 65535)
			# Runtime snapshots must not erase independent local/FX stack branches.
			# Fall back to the legacy full snapshot API on older custom binaries.
			if stack_container.has_method("replace_stack_branch"):
				stack_container.call("replace_stack_branch", StringName("Runtime"), counts)
			else:
				stack_container.call("replace_stacks", counts)
	# Render-only native timers are independent from counted tag branches.
	var timeline: Object = node.get_meta("effect_timeline", null) as Object
	if timeline != null:
		var timed_effects := runtime_effect_snapshot(kind, snapshot)
		# Server snapshots own only Runtime.*, never locally spawned visual timers.
		if timeline.has_method("replace_effect_branch"):
			timeline.call("replace_effect_branch", StringName("Runtime"), timed_effects)
		elif timeline.has_method("replace_snapshot"):
			# Legacy fork binaries still get the original authoritative snapshot.
			timeline.call("replace_snapshot", timed_effects)


## Presentation-only stack counts. The server remains authoritative for combat.
## Falls back to the validated snapshot on stock Godot/older engine builds.
## Render-side durations from the authoritative zombie snapshot.
static func runtime_effect_snapshot(kind: String, snapshot: Dictionary) -> Dictionary:
	var effects: Dictionary = {}
	if kind != "zombie":
		return effects
	for pair in [
		["stagger_seconds", "Runtime.Status.Staggered"],
		["snared_seconds", "Runtime.Status.Snared"],
		["sunder_seconds", "Runtime.Status.Sundered"],
		["resolve_seconds", "Runtime.Status.Resolve"],
	]:
		var remaining: float = float(snapshot.get(pair[0], 0.0))
		if not is_finite(remaining) or remaining <= 0.0:
			continue
		var stacks: int = 1
		if pair[0] == "resolve_seconds":
			stacks = int(snapshot.get("resolve_stacks", 0))
			if stacks < 2:
				continue
		effects[StringName(pair[1])] = {
			"remaining": minf(remaining, 604800.0), "stacks": clampi(stacks, 1, 65535)
		}
	return effects


static func tick_runtime_effects(node: Node, delta: float) -> void:
	if node == null or not is_finite(delta) or delta <= 0.0:
		return
	var timeline: Object = node.get_meta("effect_timeline", null) as Object
	if timeline != null and timeline.has_method("tick"):
		timeline.call("tick", delta)


static func runtime_effect_remaining(node: Node, tag: String, fallback: float = 0.0) -> float:
	var timeline: Object = null
	if node != null:
		timeline = node.get_meta("effect_timeline", null) as Object
	if timeline != null and timeline.has_method("get_remaining"):
		return maxf(0.0, float(timeline.call("get_remaining", StringName(tag))))
	return maxf(0.0, fallback) if is_finite(fallback) else 0.0


static func runtime_stack_count(node: Node, tag: String, fallback: int = 0) -> int:
	if node != null and node.has_meta("tag_stacks"):
		var stack_container: Object = node.get_meta("tag_stacks") as Object
		if stack_container != null and stack_container.has_method("get_stack_count"):
			return maxi(0, int(stack_container.call("get_stack_count", StringName(tag), true)))
	return maxi(0, fallback)


static func runtime_has(node: Node, tag: String, fallback: bool = false) -> bool:
	if node != null and node.has_meta("tags"):
		var container: Object = node.get_meta("tags") as Object
		if container != null and container.has_method("replace_tag_branch") and container.has_method("has_tag"):
			return bool(container.call("has_tag", StringName(tag), true))
	return fallback


static var _resolve_visual_query: Object = null # Native >=2 Resolve stack query, built once.
static var _resolve_query_checked := false


## Resolve visual gate: two or more Resolve stacks (native threshold query when available).
static func runtime_has_resolve(node: Node, fallback_stacks: int = 0) -> bool:
	if node != null and node.has_meta("tag_stacks"):
		var stacks: Object = node.get_meta("tag_stacks") as Object
		if stacks != null and stacks.has_method("get_stack_count"):
			if not _resolve_query_checked:
				_resolve_query_checked = true
				if has("GameplayTagQuery") and ClassDB.class_has_method("GameplayTagQuery", "matches_stacks"):
					var query: Object = ClassDB.instantiate("GameplayTagQuery")
					if query != null and query.has_method("set_min_stack_count"):
						query.call("set_all_tags", PackedStringArray(["Runtime.Status.Resolve"]))
						query.call("set_min_stack_count", 2)
						_resolve_visual_query = query
			if _resolve_visual_query != null:
				return bool(_resolve_visual_query.call("matches_stacks", stacks))
	return runtime_stack_count(node, "Runtime.Status.Resolve", fallback_stacks) >= 2

## Cosmetic only: native stackable hit flashes intensify rapid consecutive hits.
## Local.Visual is independent from server-owned Runtime status snapshots.
static func hit_feedback_strength(node: Node, base_strength: float) -> float:
	if not is_finite(base_strength) or base_strength <= 0.0:
		return 0.0
	var timeline: Object = null
	if node != null:
		timeline = node.get_meta("effect_timeline", null) as Object
	if timeline != null and timeline.has_method("apply_effect") and timeline.has_method("get_stacks"):
		var tag := StringName("Local.Visual.RecentHit")
		if bool(timeline.call("apply_effect", tag, 0.22, 1, 4, 0)):
			var hits: int = int(timeline.call("get_stacks", tag))
			return base_strength * (1.0 + 0.12 * float(clampi(hits, 1, 4) - 1))
	return base_strength
