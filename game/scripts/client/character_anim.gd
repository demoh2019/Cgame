extends RefCounted
## Pure, unit-testable helpers for procedural character animation (foot IK, look-at, lean, breathing, additive
## flinch, upper-body layering, animation LOD). The runtime driver is character_anim_modifier.gd.

const UP := Vector3.UP
const CombatAnimationPriority = preload("res://scripts/client/combat_animation_priority.gd")
static var _native_tier_planner: Object = null
static var _native_budget_governor: Object = null
static var _native_budget_quality: int = -1
# A compact fallback state: stock Godot and old Cgame must make the same
# admission decisions as the native governor without changing game simulation.
static var _fallback_budget_quality: int = -1
static var _fallback_budget_us: int = 0
static var _fallback_process_ema_us: int = 0
static var _fallback_window_frames: int = 0
static var _fallback_high_windows: int = 0
static var _fallback_low_windows: int = 0
const NEAR_CAMERA_VISIBILITY_RADIUS := 3.0 # Matches the animation LOD close-camera safeguard.
const IK_RETENTION_HYSTERESIS_METRES := 1.5 # Keeps a prior on-screen IK owner during small camera moves.
# The soft CPU cap applies only to the optional script full-pose modifier.
const FULL_POSE_CPU_BUDGET_US := [0, 750, 1500, 2750]
# 0: players, 1: standard infected, 2: elite / raid boss, 3: reserved
# for future scripted characters. Only active groups receive CPU shares.
static var FULL_POSE_GROUP_WEIGHTS := PackedFloat64Array([3.0, 1.0, 2.0, 2.0])
const POSE_PROCESS_TARGET_US := 12500 # Main-thread process time, not FPS or GPU frame duration.

## Clears CPU pressure history when the world/session or rendering policy
## changes. This is visual-only: combat, server ticks and networking remain
## completely outside adaptive full-pose budgeting.
static func reset_adaptive_pose_budget() -> void:
	_fallback_budget_quality = -1
	_fallback_budget_us = 0
	_fallback_process_ema_us = 0
	_fallback_window_frames = 0
	_fallback_high_windows = 0
	_fallback_low_windows = 0
	if _native_budget_governor != null and _native_budget_governor.has_method("reset"):
		_native_budget_governor.call("reset")
	_native_budget_quality = -1


## A predictable native/stock-Godot CPU pressure controller. This only
## adjusts the *optional* full-IK work-unit microsecond allowance; the
## existing cap_full_pose_cost() still ranks actors by distance and prior
## full-IK ownership and never reduces separately prioritized combat poses.
## It consumes the most recently reported Godot Performance.TIME_PROCESS.
static func adaptive_full_pose_budget_us(quality: int, frame_process_us: int,
		prefer_native: bool = true) -> int:
	if quality < 0 or quality > 3 or frame_process_us < 0 or frame_process_us > 1000000:
		return -1
	var base: int = FULL_POSE_CPU_BUDGET_US[quality]
	if prefer_native and ClassDB.class_exists("CrowdAnimationBudgetGovernor"):
		if _native_budget_governor == null:
			_native_budget_governor = ClassDB.instantiate("CrowdAnimationBudgetGovernor")
			_native_budget_quality = -1
		if _native_budget_governor != null and _native_budget_governor.has_method(
				"observe_process_time"):
			if _native_budget_quality != quality:
				if not bool(_native_budget_governor.call("configure", base, POSE_PROCESS_TARGET_US)):
					return -1
				_native_budget_quality = quality
			return int(_native_budget_governor.call("observe_process_time", frame_process_us))
	if _fallback_budget_quality != quality:
		_fallback_budget_quality = quality
		_fallback_budget_us = base
		_fallback_process_ema_us = 0
		_fallback_window_frames = 0
		_fallback_high_windows = 0
		_fallback_low_windows = 0
	if frame_process_us == 0 or base == 0:
		return _fallback_budget_us
	_fallback_process_ema_us = frame_process_us if _fallback_process_ema_us == 0 else \
		int((3 * _fallback_process_ema_us + frame_process_us + 2) / 4)
	_fallback_window_frames += 1
	if _fallback_window_frames < 12:
		return _fallback_budget_us
	_fallback_window_frames = 0
	if _fallback_process_ema_us * 100 > POSE_PROCESS_TARGET_US * 95:
		_fallback_high_windows = mini(_fallback_high_windows + 1, 2)
		_fallback_low_windows = 0
	elif _fallback_process_ema_us * 100 < POSE_PROCESS_TARGET_US * 70:
		_fallback_low_windows = mini(_fallback_low_windows + 1, 3)
		_fallback_high_windows = 0
	else:
		_fallback_high_windows = 0
		_fallback_low_windows = 0
	if _fallback_high_windows >= 2:
		_fallback_budget_us = maxi(maxi(1, int((base + 3) / 4)),
			int((3 * _fallback_budget_us + 2) / 4))
		_fallback_high_windows = 0
	elif _fallback_low_windows >= 3:
		_fallback_budget_us = mini(base,
			_fallback_budget_us + maxi(1, int(base / 8)))
		_fallback_low_windows = 0
	return _fallback_budget_us


## On-demand diagnostics; never constructed by the per-frame crowd path.
static func adaptive_pose_budget_snapshot(quality: int) -> Dictionary:
	var base: int = FULL_POSE_CPU_BUDGET_US[clampi(quality, 0, 3)]
	if _native_budget_governor != null and _native_budget_quality == quality and \
			_native_budget_governor.has_method("get_current_budget_us"):
		return {
			"source": "native", "base_us": base,
			"allowance_us": int(_native_budget_governor.call("get_current_budget_us")),
			"process_ema_us": int(_native_budget_governor.call("get_smoothed_process_us")),
			"pressure_percent": int(_native_budget_governor.call("get_pressure_percent")),
			"samples": int(_native_budget_governor.call("get_frames_observed"))
		}
	var same_quality: bool = _fallback_budget_quality == quality
	var process_us: int = _fallback_process_ema_us if same_quality else 0
	return {
		"source": "script", "base_us": base,
		"allowance_us": _fallback_budget_us if same_quality else base,
		"process_ema_us": process_us,
		"pressure_percent": mini(1000, int(process_us * 100 / POSE_PROCESS_TARGET_US))
	}


# --- Animation LOD / crowd budget (Unreal URO / Unity Animator Culling) --------------------------------------------------

## How many characters may run the full procedural stack (IK, look-at) per quality tier 0..3.
static func full_budget(quality: int) -> int:
	return [0, 4, 8, 14][clampi(quality, 0, 3)]


## 0 full rate + modifiers, 1 full rate no IK, 2 half rate, 3 quarter rate, 4 eighth rate.
static func lod_tier(distance: float) -> int:
	if distance < 22.0:
		return 0
	if distance < 38.0:
		return 1
	if distance < 60.0:
		return 2
	if distance < 90.0:
		return 3
	return 4


## Seconds between animation updates of a tier (0 = every frame).
static func lod_interval(tier: int) -> float:
	return [0.0, 0.0, 1.0 / 30.0, 1.0 / 15.0, 1.0 / 8.0][clampi(tier, 0, 4)]


## Assigns a tier to each character from its distance. Only the nearest `budget` characters may be tier 0;
## the rest of the near crowd is demoted to tier 1. Returns tiers in the order of `distances`.
static func assign_tiers(distances: Array, budget: int) -> PackedInt32Array:
	var order: Array = range(distances.size())
	order.sort_custom(func(a, b): return float(distances[a]) < float(distances[b]))
	var out := PackedInt32Array()
	out.resize(distances.size())
	var granted := 0
	for index in order:
		var tier := lod_tier(float(distances[index]))
		if tier == 0:
			if granted < budget:
				granted += 1
			else:
				tier = 1
		out[index] = tier
	return out


## Stable crowd tiers suppress threshold flip-flopping across render frames.
## `previous` is aligned 1:1 to the current list of models. No process-wide
## cache is kept: streamed actors can despawn/reorder without stale lookups.
const TIER_BOUNDARIES := [22.0, 38.0, 60.0, 90.0]
const TIER_HYSTERESIS_METERS := 1.5


static func plan_crowd_tiers_stable(distances: PackedFloat64Array, priority_flags: PackedByteArray,
		previous: PackedInt32Array, full_slots: int, priority_slots: int,
		hysteresis_meters: float = TIER_HYSTERESIS_METERS,
		prefer_native: bool = true) -> PackedInt32Array:
	var count: int = distances.size()
	if count != priority_flags.size() or count != previous.size() or count > 16384 \
			or full_slots < 0 or full_slots > 256 or priority_slots < 0 or priority_slots > 256 \
			or not is_finite(hysteresis_meters) or hysteresis_meters < 0.0 or hysteresis_meters > 4.0:
		return PackedInt32Array()
	for i in count:
		if not is_finite(distances[i]) or distances[i] < 0.0 or previous[i] < 0 or previous[i] > 4:
			return PackedInt32Array()
	if prefer_native and ClassDB.class_exists("CrowdAnimationTierPlanner"):
		if _native_tier_planner == null:
			_native_tier_planner = ClassDB.instantiate("CrowdAnimationTierPlanner")
		if _native_tier_planner != null and _native_tier_planner.has_method("plan_tiers_stable"):
			var native_tiers: PackedInt32Array = _native_tier_planner.call(
				"plan_tiers_stable", distances, priority_flags, previous, full_slots,
				priority_slots, hysteresis_meters)
			if native_tiers.size() == count:
				return native_tiers
	# Identical math and deterministic tie-breaking in stock Godot / old forks.
	var tiers := PackedInt32Array()
	tiers.resize(count)
	var full_order: Array[int] = []
	var priority_order: Array[int] = []
	for i in count:
		var tier: int = previous[i]
		var distance: float = distances[i]
		while tier < 4 and distance >= TIER_BOUNDARIES[tier] + hysteresis_meters:
			tier += 1
		while tier > 0 and distance < TIER_BOUNDARIES[tier - 1] - hysteresis_meters:
			tier -= 1
		tiers[i] = maxi(1, tier) # Full IK is awarded only from a finite shared budget.
		if distance < 22.0 or (previous[i] == 0 and distance < 22.0 + hysteresis_meters):
			full_order.append(i)
		if priority_flags[i] != 0 and (
				distance < 90.0 or (previous[i] <= 1 and distance < 90.0 + hysteresis_meters)):
			priority_order.append(i)
	full_order.sort_custom(func(a: int, b: int) -> bool:
		var da: float = distances[a] - (hysteresis_meters if previous[a] == 0 else 0.0)
		var db: float = distances[b] - (hysteresis_meters if previous[b] == 0 else 0.0)
		return da < db if da != db else a < b)
	priority_order.sort_custom(func(a: int, b: int) -> bool:
		var da: float = distances[a] - (hysteresis_meters if previous[a] <= 1 else 0.0)
		var db: float = distances[b] - (hysteresis_meters if previous[b] <= 1 else 0.0)
		return da < db if da != db else a < b)
	for i in mini(full_slots, full_order.size()):
		tiers[full_order[i]] = 0
	for i in mini(priority_slots, priority_order.size()):
		tiers[priority_order[i]] = mini(tiers[priority_order[i]], 1)
	return tiers


## Applies boundary hysteresis only to tiers that were chosen purely by
## distance. Budget-driven results (full-IK owners, combat-priority promotion,
## cost-capped demotion) keep the planner's decision. Off-screen actors still
## never outrank tier 2.
static func apply_distance_hysteresis(tiers: PackedInt32Array, stable_tiers: PackedInt32Array,
		distances: PackedFloat64Array, visible_mask: PackedByteArray) -> PackedInt32Array:
	var count: int = tiers.size()
	if stable_tiers.size() != count or distances.size() != count or visible_mask.size() != count:
		return tiers
	var out := tiers.duplicate()
	for i in count:
		var plain: int = maxi(1, lod_tier(distances[i]))
		var visible: bool = visible_mask[i] != 0
		var expected: int = plain if visible else maxi(2, plain)
		if tiers[i] != expected:
			continue
		out[i] = stable_tiers[i] if visible else maxi(2, stable_tiers[i])
	return out


## Batch-selects pose tiers. Native Cgame does bounded top-K on numeric
## arrays; stock Godot uses an equivalent deterministic GDScript fallback.
## visible_flags is optional for backward compatibility. When provided, off-screen
## characters retain their distance tier but never outrank tier 2, and cannot
## consume expensive procedural or combat-priority slots.
## retained_full_flags adds a bounded distance discount for prior full-IK owners,
## but only within the usual 22m / visible eligibility. A zero discount keeps
## the original selection byte-for-byte compatible.
static func plan_crowd_tiers(distances: PackedFloat64Array, priority_flags: PackedByteArray,
		full_slots: int, priority_slots: int, prefer_native: bool = true,
		visible_flags: PackedByteArray = PackedByteArray(),
		retained_full_flags: PackedByteArray = PackedByteArray(),
		full_hysteresis: float = 0.0,
		retained_combat_flags: PackedByteArray = PackedByteArray(),
		combat_hysteresis: float = 0.0) -> PackedInt32Array:
	var count: int = distances.size()
	if count != priority_flags.size() or count > 16384 or full_slots < 0 or full_slots > 256 \
			or priority_slots < 0 or priority_slots > 256 or \
			(not visible_flags.is_empty() and visible_flags.size() != count) or \
			(not retained_full_flags.is_empty() and retained_full_flags.size() != count) or \
			(not retained_combat_flags.is_empty() and retained_combat_flags.size() != count) or \
			not is_finite(full_hysteresis) or full_hysteresis < 0.0 or full_hysteresis > 8.0 or \
			not is_finite(combat_hysteresis) or combat_hysteresis < 0.0 or combat_hysteresis > 4.0:
		return PackedInt32Array()
	for distance in distances:
		if not is_finite(distance) or distance < 0.0:
			return PackedInt32Array()
	if prefer_native and ClassDB.class_exists("CrowdAnimationTierPlanner"):
		if _native_tier_planner == null:
			_native_tier_planner = ClassDB.instantiate("CrowdAnimationTierPlanner")
		if _native_tier_planner != null:
			# A newer native API preserves BOTH independent budgets, without
			# replacing older engines' full-IK-only retention semantics.
			if combat_hysteresis > 0.0 and not retained_combat_flags.is_empty():
				if not retained_full_flags.is_empty() and not visible_flags.is_empty() and \
						_native_tier_planner.has_method("plan_visible_tiers_temporal"):
					var temporal_tiers: PackedInt32Array = _native_tier_planner.call(
						"plan_visible_tiers_temporal", distances, priority_flags, visible_flags,
						retained_full_flags, retained_combat_flags, full_slots, priority_slots,
						full_hysteresis, combat_hysteresis)
					if temporal_tiers.size() == count:
						return temporal_tiers
				return _plan_crowd_tiers_fallback(distances, priority_flags,
					full_slots, priority_slots, visible_flags, retained_full_flags,
					full_hysteresis, retained_combat_flags, combat_hysteresis)
			if not retained_full_flags.is_empty() and full_hysteresis > 0.0 and \
					not visible_flags.is_empty() and \
					_native_tier_planner.has_method("plan_visible_tiers_stable"):
				var stable_tiers: PackedInt32Array = _native_tier_planner.call(
					"plan_visible_tiers_stable", distances, priority_flags, visible_flags,
					retained_full_flags, full_slots, priority_slots, full_hysteresis)
				if stable_tiers.size() == count:
					return stable_tiers
			# Do not call an older native method when retention is requested:
			# the matching GDScript fallback must preserve the sticky ranking.
			if full_hysteresis > 0.0 and not retained_full_flags.is_empty():
				return _plan_crowd_tiers_fallback(distances, priority_flags,
					full_slots, priority_slots, visible_flags, retained_full_flags,
					full_hysteresis)
			# An older Cgame build may have only the original four-argument
			# API; never call it with visibility flags and lose safety parity.
			if not visible_flags.is_empty() and _native_tier_planner.has_method("plan_visible_tiers"):
				var native_visible: PackedInt32Array = _native_tier_planner.call(
					"plan_visible_tiers", distances, priority_flags, visible_flags,
					full_slots, priority_slots)
				if native_visible.size() == count:
					return native_visible
			elif visible_flags.is_empty() and _native_tier_planner.has_method("plan_tiers"):
				var native_tiers: PackedInt32Array = _native_tier_planner.call(
					"plan_tiers", distances, priority_flags, full_slots, priority_slots)
				if native_tiers.size() == count:
					return native_tiers
	return _plan_crowd_tiers_fallback(distances, priority_flags, full_slots,
		priority_slots, visible_flags, retained_full_flags, full_hysteresis,
		retained_combat_flags, combat_hysteresis)


## Script-only parity for older Cgame builds and stock Godot.
static func _plan_crowd_tiers_fallback(distances: PackedFloat64Array,
		priority_flags: PackedByteArray, full_slots: int, priority_slots: int,
		visible_flags: PackedByteArray, retained_full_flags: PackedByteArray,
		full_hysteresis: float, retained_combat_flags: PackedByteArray = PackedByteArray(),
		combat_hysteresis: float = 0.0) -> PackedInt32Array:
	var count: int = distances.size()
	var order: Array[int] = []
	var eligible_full: Array[int] = []
	for i in count:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return distances[a] < distances[b] if distances[a] != distances[b] else a < b)
	var tiers := PackedInt32Array()
	tiers.resize(count)
	for index in order:
		var tier: int = lod_tier(distances[index])
		var visible: bool = visible_flags.is_empty() or visible_flags[index] != 0
		if not visible:
			tiers[index] = maxi(tier, 2)
		else:
			tiers[index] = maxi(tier, 1)
			if tier == 0:
				eligible_full.append(index)
	# Only the IK pool gets hysteresis. Combat priority is still selected by
	# unmodified distance and never retains invisible actors.
	if full_hysteresis > 0.0 and not retained_full_flags.is_empty():
		eligible_full.sort_custom(func(a: int, b: int) -> bool:
			var a_score: float = maxf(0.0, distances[a] -
				(full_hysteresis if retained_full_flags[a] != 0 else 0.0))
			var b_score: float = maxf(0.0, distances[b] -
				(full_hysteresis if retained_full_flags[b] != 0 else 0.0))
			return a_score < b_score if a_score != b_score else a < b
		)
	for i in mini(full_slots, eligible_full.size()):
		tiers[eligible_full[i]] = 0
	# Keep the combat pose queue stable independently of procedural IK.
	var combat_order: Array[int] = order.duplicate()
	if combat_hysteresis > 0.0 and not retained_combat_flags.is_empty():
		combat_order.sort_custom(func(a: int, b: int) -> bool:
			var a_score: float = maxf(0.0, distances[a] -
				(combat_hysteresis if retained_combat_flags[a] != 0 else 0.0))
			var b_score: float = maxf(0.0, distances[b] -
				(combat_hysteresis if retained_combat_flags[b] != 0 else 0.0))
			return a_score < b_score if a_score != b_score else a < b
		)
	var granted_priority: int = 0
	for index in combat_order:
		if granted_priority >= priority_slots:
			break
		if (not visible_flags.is_empty() and visible_flags[index] == 0) or \
				priority_flags[index] == 0 or distances[index] >= 90.0:
			continue
		tiers[index] = mini(tiers[index], 1)
		granted_priority += 1
	return tiers


## Cost-only second-stage admission. Call after the engine's distance,
## visibility, sticky-IK and independently retained combat tiers are chosen.
## This *never* promotes or demotes existing tier-1/2/3/4 poses.
static func cap_full_pose_cost(tiers: PackedInt32Array, distances: PackedFloat64Array,
		retained_full_flags: PackedByteArray, full_pose_cost_us: PackedInt32Array,
		full_pose_budget_us: int, hysteresis: float = IK_RETENTION_HYSTERESIS_METRES,
		prefer_native: bool = true) -> PackedInt32Array:
	var count: int = tiers.size()
	if count != distances.size() or count != retained_full_flags.size() or \
			count != full_pose_cost_us.size() or count > 16384 or \
			full_pose_budget_us < 0 or full_pose_budget_us > 1000000 or \
			not is_finite(hysteresis) or hysteresis < 0.0 or hysteresis > 8.0:
		return PackedInt32Array()
	var full_count := 0
	for i in count:
		if tiers[i] < 0 or tiers[i] > 4 or \
				not is_finite(distances[i]) or distances[i] < 0.0 or \
				full_pose_cost_us[i] < 0 or full_pose_cost_us[i] > 100000:
			return PackedInt32Array()
		if tiers[i] == 0:
			full_count += 1
	if full_count > 256:
		return PackedInt32Array()
	if full_pose_budget_us == 0:
		return tiers
	if prefer_native and ClassDB.class_exists("CrowdAnimationTierPlanner"):
		if _native_tier_planner == null:
			_native_tier_planner = ClassDB.instantiate("CrowdAnimationTierPlanner")
		if _native_tier_planner != null and _native_tier_planner.has_method("cap_full_pose_cost"):
			var native_tiers: PackedInt32Array = _native_tier_planner.call(
				"cap_full_pose_cost", tiers, distances, retained_full_flags,
				full_pose_cost_us, full_pose_budget_us, hysteresis)
			if native_tiers.size() == count:
				return native_tiers
	# The stock-Godot and old-Cgame path follows exactly the same
	# admission order as the native bounded top-K selector.
	var result: PackedInt32Array = tiers.duplicate()
	var winners: Array[int] = []
	for i in count:
		if tiers[i] == 0:
			winners.append(i)
	winners.sort_custom(func(a: int, b: int) -> bool:
		var da: float = maxf(0.0, distances[a] -
			(hysteresis if retained_full_flags[a] != 0 else 0.0))
		var db: float = maxf(0.0, distances[b] -
			(hysteresis if retained_full_flags[b] != 0 else 0.0))
		return da < db if da != db else a < b
	)
	var spent_us: int = 0
	for idx in winners:
		var estimated_us: int = full_pose_cost_us[idx]
		if estimated_us == 0:
			estimated_us = 100
		if spent_us + estimated_us <= full_pose_budget_us:
			spent_us += estimated_us
		else:
			result[idx] = 1
	return result


# --- Smoothing / springs --------------------------------------------------------------------------------------------------


## Reserve a proportional share of the current measured IK allowance for
## each active actor type, then redistribute unused shares in weighted
## significance order. Uses ONLY the tier-0 actors that the existing planner
## already selected. Never promotes tier-1/2/3/4 or slows combat locomotion.
static func cap_full_pose_cost_grouped(tiers: PackedInt32Array,
		distances: PackedFloat64Array, retained_full_flags: PackedByteArray,
		full_pose_cost_us: PackedInt32Array, group_ids: PackedByteArray,
		group_weights: PackedFloat64Array, full_pose_budget_us: int,
		hysteresis: float = IK_RETENTION_HYSTERESIS_METRES,
		prefer_native: bool = true) -> PackedInt32Array:
	var count: int = tiers.size()
	if count != distances.size() or count != retained_full_flags.size() or \
			count != full_pose_cost_us.size() or count != group_ids.size() or \
			count > 16384 or group_weights.size() != 4 or \
			full_pose_budget_us < 0 or full_pose_budget_us > 1000000 or \
			not is_finite(hysteresis) or hysteresis < 0.0 or hysteresis > 8.0:
		return PackedInt32Array()
	for weight in group_weights:
		if not is_finite(weight) or weight < 0.25 or weight > 8.0:
			return PackedInt32Array()
	var present: Array[bool] = [false, false, false, false]
	var full_count: int = 0
	for i in count:
		if tiers[i] < 0 or tiers[i] > 4 or not is_finite(distances[i]) or \
				distances[i] < 0.0 or full_pose_cost_us[i] < 0 or \
				full_pose_cost_us[i] > 100000 or group_ids[i] > 3:
			return PackedInt32Array()
		if tiers[i] == 0:
			full_count += 1
			present[group_ids[i]] = true
	if full_count > 256:
		return PackedInt32Array()
	if full_pose_budget_us == 0 or full_count == 0:
		return tiers
	if prefer_native and ClassDB.class_exists("CrowdAnimationTierPlanner"):
		if _native_tier_planner == null:
			_native_tier_planner = ClassDB.instantiate("CrowdAnimationTierPlanner")
		if _native_tier_planner != null and _native_tier_planner.has_method(
				"cap_full_pose_cost_grouped"):
			var native_tiers: PackedInt32Array = _native_tier_planner.call(
				"cap_full_pose_cost_grouped", tiers, distances, retained_full_flags,
				full_pose_cost_us, group_ids, group_weights, full_pose_budget_us,
				hysteresis)
			if native_tiers.size() == count:
				return native_tiers
	# Entirely deterministic fallback for stock Godot / older Cgame.
	var active_weight: float = 0.0
	for group in 4:
		if present[group]:
			active_weight += group_weights[group]
	var quota_us: Array[int] = [0, 0, 0, 0]
	var spent_group_us: Array[int] = [0, 0, 0, 0]
	for group in 4:
		if present[group]:
			quota_us[group] = int(float(full_pose_budget_us) *
				group_weights[group] / active_weight)
	var order: Array[int] = []
	for i in count:
		if tiers[i] == 0:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var da: float = maxf(0.0, distances[a] -
			(hysteresis if retained_full_flags[a] != 0 else 0.0)) / group_weights[group_ids[a]]
		var db: float = maxf(0.0, distances[b] -
			(hysteresis if retained_full_flags[b] != 0 else 0.0)) / group_weights[group_ids[b]]
		return da < db if da != db else a < b
	)
	var selected := PackedByteArray()
	selected.resize(count)
	var total_spent_us: int = 0
	for idx in order:
		var group: int = group_ids[idx]
		var work_us: int = full_pose_cost_us[idx] if full_pose_cost_us[idx] > 0 else 100
		if spent_group_us[group] + work_us <= quota_us[group]:
			spent_group_us[group] += work_us
			total_spent_us += work_us
			selected[idx] = 1
	# No reservation is wasted if its group has no eligible/affordable work.
	for idx in order:
		if selected[idx] != 0:
			continue
		var work_us: int = full_pose_cost_us[idx] if full_pose_cost_us[idx] > 0 else 100
		if total_spent_us + work_us <= full_pose_budget_us:
			total_spent_us += work_us
			selected[idx] = 1
	var out: PackedInt32Array = tiers.duplicate()
	for idx in order:
		if selected[idx] == 0:
			out[idx] = 1
	return out


## Exponential smoothing independent of frame rate.
static func smooth(current: float, target: float, delta: float, rate: float) -> float:
	return lerpf(current, target, 1.0 - exp(-rate * maxf(delta, 0.0)))


## Moves a playback rate toward its target at most `max_rate` per second (no pops when the speed bracket changes).
static func smooth_rate(current: float, target: float, delta: float, max_rate: float = 4.0) -> float:
	return move_toward(current, target, max_rate * maxf(delta, 0.0))


## One semi-implicit spring-damper step; returns [position, velocity].
static func spring_step(x: float, v: float, target: float, stiffness: float, damping: float, delta: float) -> Array:
	v += ((target - x) * stiffness - v * damping) * delta
	x += v * delta
	return [x, v]


# --- Procedural body motion -----------------------------------------------------------------------------------------------

## Lean into a turn: [roll, pitch] radians for the spine. `yaw_rate` rad/s (positive = turning left), `speed` m/s.
## Roll toward the inside of the turn, pitch forward with speed.
static func lean_angles(yaw_rate: float, speed: float) -> Vector2:
	var strength := clampf(speed / 4.0, 0.0, 1.2)
	var roll := clampf(-yaw_rate * 0.05 * strength, -0.17, 0.17)
	var pitch := clampf(speed * 0.012, 0.0, 0.08)
	return Vector2(roll, pitch)


## Idle breathing: chest pitch in radians at time t, fading out while moving (`moving_weight` 0..1).
static func breath_angle(t: float, moving_weight: float) -> float:
	return sin(t * TAU * 0.28) * 0.016 * (1.0 - clampf(moving_weight, 0.0, 1.0))


## Yaw/pitch (radians, clamped) needed to look along `target_dir` for a body whose basis is `body_basis`
## (+Z forward, +Y up). Targets behind the body stay clamped at the limit, scaled down to zero when directly behind.
static func look_angles(body_basis: Basis, target_dir: Vector3, max_yaw: float, max_pitch: float) -> Vector2:
	if target_dir.length_squared() < 0.0001:
		return Vector2.ZERO
	var d := body_basis.orthonormalized().inverse() * target_dir.normalized()
	var yaw := atan2(d.x, d.z)
	var pitch := asin(clampf(d.y, -1.0, 1.0))
	var behind := clampf((absf(yaw) - PI * 0.6) / (PI * 0.4), 0.0, 1.0) # past ~108 degrees, ease back to forward
	var fade := 1.0 - behind
	return Vector2(clampf(yaw, -max_yaw, max_yaw) * fade, clampf(pitch, -max_pitch, max_pitch) * fade)


## World-space rotation for a yaw/pitch look pair, expressed around the body frame.
static func look_rotation(body_basis: Basis, angles: Vector2) -> Quaternion:
	var local := Quaternion(UP, angles.x) * Quaternion(Vector3.RIGHT, -angles.y)
	var b := Quaternion(body_basis.orthonormalized())
	return b * local * b.inverse()


## Rotation conjugated into world space: roll about the body forward axis, pitch about its lateral axis.
static func lean_rotation(body_basis: Basis, roll: float, pitch: float) -> Quaternion:
	var local := Quaternion(Vector3.BACK, roll) * Quaternion(Vector3.RIGHT, pitch)
	var b := Quaternion(body_basis.orthonormalized())
	return b * local * b.inverse()


# --- Foot IK ---------------------------------------------------------------------------------------------------------------

## 1 while a foot is on the ground, 0 once it lifted `lift` metres above its planted height (swing phase).
static func contact_weight(height_above_plant: float, lift: float = 0.14) -> float:
	return 1.0 - clampf(height_above_plant / lift, 0.0, 1.0)


## Pelvis shift (<= 0 normally): the hips follow the lower foot target so neither leg overextends; clamped.
static func pelvis_offset(left_delta: float, right_delta: float, limit: float = 0.35) -> float:
	return clampf(minf(minf(left_delta, right_delta), 0.0), -limit, 0.0)


## Surface normal from a centre sample and two neighbours `step` metres along +X and +Z.
static func ground_normal(h0: float, hx: float, hz: float, step: float) -> Vector3:
	return Vector3(-(hx - h0) / step, 1.0, -(hz - h0) / step).normalized()


## Analytic two-bone IK. Hip `a`, knee `b`, ankle `c`, desired ankle `target`. Returns [new_knee, new_ankle]; bone
## lengths are kept, the knee bends toward its original side, unreachable targets are clamped to full extension.
static func solve_knee(a: Vector3, b: Vector3, c: Vector3, target: Vector3) -> Array:
	var l1 := (b - a).length()
	var l2 := (c - b).length()
	var to_target := target - a
	var dir := to_target.normalized() if to_target.length_squared() > 0.000001 else (c - a).normalized()
	var d := clampf(to_target.length(), absf(l1 - l2) + 0.0005, l1 + l2 - 0.0005)
	var along := (l1 * l1 + d * d - l2 * l2) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - along * along, 0.0))
	var bend := (b - a) - dir * (b - a).dot(dir)
	if bend.length_squared() < 0.000001:
		bend = (b - a).cross(Vector3.RIGHT)
	if bend.length_squared() < 0.000001:
		bend = Vector3.BACK
	return [a + dir * along + bend.normalized() * h, a + dir * d]


# --- Upper-body layering (Unity Avatar Mask / Unreal Layered Blend Per Bone) -----------------------------------------------

const UPPER_PREFIXES := ["spine", "neck", "head", "clavicle", "upperarm", "lowerarm", "hand", "thumb", "index", "middle",
	"ring", "pinky", "weapon"]


static func is_upper_body_bone(bone: String) -> bool:
	var lower := bone.to_lower()
	for prefix in UPPER_PREFIXES:
		if lower.begins_with(prefix):
			return true
	return false


## The bone a skeleton track path points at ("Armature/Skeleton3D:upperarm_l" -> "upperarm_l"); "" for non-bone paths.
static func track_bone(path: NodePath) -> String:
	var subname := path.get_concatenated_subnames()
	return subname.get_slice(":", 0) if subname != "" else ""


## Copy of `animation` that only drives upper-body bones (loop mode kept). Used by a second AnimationPlayer layered
## over locomotion so a swing plays while the legs keep walking.
static func upper_body_copy(animation: Animation) -> Animation:
	var copy := animation.duplicate() as Animation
	for i in range(copy.get_track_count() - 1, -1, -1):
		var bone := track_bone(copy.track_get_path(i))
		if bone == "" or not is_upper_body_bone(bone):
			copy.remove_track(i)
	return copy


## Whether an action clip should be layered over locomotion rather than replace it.
static func layerable(animation_name: String, moving: bool, zombie: bool) -> bool:
	if not moving or zombie:
		return false
	for prefix in ["Sword", "Melee", "Punch", "Pistol", "Spell", "Throw", "Interact"]:
		if animation_name.begins_with(prefix):
			return true
	return false


# --- Crowd pass ----------------------------------------------------------------------------------------------------------

## Once per frame over every live CharacterModel: distance LOD tiers within the crowd budget, terrain source for foot
## IK, and a camera look-at for the closest few. `models` are CharacterModel nodes.
static func apply_crowd(models: Array, camera: Camera3D, quality: int, ground: Callable,
		pose_budget_us: int = -1) -> void:
	if camera == null or models.is_empty():
		return
	var cam: Vector3 = camera.global_position
	var distances := PackedFloat64Array()
	var priority_mask := PackedByteArray()
	var previous_tiers := PackedInt32Array()
	var visible_mask := PackedByteArray()
	var retained_full_mask := PackedByteArray()
	var retained_combat_mask := PackedByteArray()
	var full_pose_cost_us := PackedInt32Array()
	var full_pose_group_ids := PackedByteArray()
	for model in models:
		# The live CharacterModel owns its current tier. This remains correct
		# when WorldStreamer changes the array order or despawns characters.
		previous_tiers.append(int(model.get("_lod_tier")))
		var distance: float = model.global_position.distance_to(cam)
		distances.append(distance)
		# Use the actual camera, but keep close actors conservative: their
		# limbs may cross the frustum while the root point is outside.
		var visible: bool = model.is_visible_in_tree() and (distance < NEAR_CAMERA_VISIBILITY_RADIUS or \
			camera.is_position_in_frustum(model.global_position + Vector3.UP))
		visible_mask.append(1 if visible else 0)
		retained_full_mask.append(1 if bool(model.get_meta("aa_full_ik_retained", false)) else 0)
		retained_combat_mask.append(1 if bool(model.get_meta("aa_combat_pose_retained", false)) else 0)
		# A native FootPlacementModifier3D measures its own terrain/IK work.
		# The model combines that with scripted breathing/look-at cost; stock
		# Godot has no native foot sample, so only the script cost is used.
		full_pose_cost_us.append(model.estimated_full_pose_cost_us())
		full_pose_group_ids.append(clampi(int(model.animation_budget_group), 0, 3))
		# Combat urgency is visual-only, and the native mixer controller
		# already handles critical poses when external_anim_lod is enabled.
		var critical: bool = not bool(model.get("external_anim_lod")) \
			and bool(model.get_meta("aa_combat_animation_priority", false)) \
			and distance < 90.0 and visible
		priority_mask.append(1 if critical else 0)
	var tiers: PackedInt32Array = plan_crowd_tiers(distances, priority_mask,
		full_budget(quality), CombatAnimationPriority.slots(quality), true, visible_mask,
		retained_full_mask, IK_RETENTION_HYSTERESIS_METRES,
		retained_combat_mask, 1.5)
	if tiers.size() != models.size():
		return
	# Secondary predicted CPU gate: a caller-supplied adaptive allowance
	# reduces only optional IK work. No change to prioritized combat poses.
	var allowance_us: int = FULL_POSE_CPU_BUDGET_US[clampi(quality, 0, 3)]
	if pose_budget_us >= 0:
		allowance_us = mini(allowance_us, pose_budget_us)
	tiers = cap_full_pose_cost_grouped(tiers, distances, retained_full_mask,
		full_pose_cost_us, full_pose_group_ids, FULL_POSE_GROUP_WEIGHTS,
		allowance_us, IK_RETENTION_HYSTERESIS_METRES)
	var stable_tiers: PackedInt32Array = plan_crowd_tiers_stable(distances, priority_mask,
		previous_tiers, full_budget(quality), CombatAnimationPriority.slots(quality))
	tiers = apply_distance_hysteresis(tiers, stable_tiers, distances, visible_mask)
	if tiers.size() != models.size():
		return
	for i in models.size():
		var model = models[i]
		if ground.is_valid() and not model.has_ground_source():
			model.set_ground_source(ground)
		model.set_anim_lod(tiers[i])
		var full_ik_now: bool = tiers[i] == 0
		if bool(model.get_meta("aa_full_ik_retained", false)) != full_ik_now:
			model.set_meta("aa_full_ik_retained", full_ik_now)
		# Only count poses promoted above their natural distance tier.
		var combat_promoted: bool = priority_mask[i] != 0 and tiers[i] == 1 and distances[i] >= 38.0
		if bool(model.get_meta("aa_combat_pose_retained", false)) != combat_promoted:
			model.set_meta("aa_combat_pose_retained", combat_promoted)
		model.set_look_point(cam if tiers[i] == 0 and distances[i] < 12.0 else Vector3.INF)
