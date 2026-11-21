extends RefCounted
## Headless numeric parity tests for native and stock-Godot crowd tier planning.

const CharacterAnim = preload("res://scripts/client/character_anim.gd")


func run(t) -> void:
	t.current = "numeric crowd pose LOD boundaries and priority"
	var positions := PackedFloat64Array([2.0, 4.0, 30.0, 55.0, 80.0, 100.0])
	var priorities := PackedByteArray([0, 0, 0, 1, 1, 1])
	var expected := PackedInt32Array([0, 1, 1, 1, 3, 4])
	var result: PackedInt32Array = CharacterAnim.plan_crowd_tiers(positions, priorities, 1, 1, false)
	t.eq(result, expected, "script planner preserves near, mid, far and attack LOD")
	t.eq(CharacterAnim.plan_crowd_tiers(positions, priorities, 1, 2, false)[4], 1,
		"second visible attacker receives an additional combat slot")
	t.eq(positions[0], 2.0, "numeric query does not mutate input distances")
	var tie_distances := PackedFloat64Array([5.0, 5.0, 5.0, 22.0, 38.0, 60.0, 90.0])
	var all_priority := PackedByteArray([1, 1, 1, 1, 1, 1, 1])
	t.eq(CharacterAnim.plan_crowd_tiers(tie_distances, all_priority, 1, 0, false),
		PackedInt32Array([0, 1, 1, 1, 2, 3, 4]),
		"equal distances favor the earlier entity for full procedural IK")
	t.eq(CharacterAnim.plan_crowd_tiers(tie_distances, all_priority, 0, 2, false)[0],
		1, "combat priority raises full-rate pose but not expensive IK")

	t.current = "invalid numeric batches are rejected before mutation"
	t.eq(CharacterAnim.plan_crowd_tiers(PackedFloat64Array([1.0]),
		PackedByteArray(), 1, 1, false).size(), 0, "mismatched sizes reject")
	t.eq(CharacterAnim.plan_crowd_tiers(PackedFloat64Array([NAN]),
		PackedByteArray([1]), 1, 1, false).size(), 0, "NaN input rejected")
	t.eq(CharacterAnim.plan_crowd_tiers(PackedFloat64Array([-1.0]),
		PackedByteArray([1]), 1, 1, false).size(), 0, "negative camera distance rejected")
	t.eq(CharacterAnim.plan_crowd_tiers(positions, priorities, 257, 1, false).size(),
		0, "unbounded full-rate budget rejected")
	t.eq(CharacterAnim.plan_crowd_tiers(positions, priorities, 1, -1, false).size(),
		0, "negative attack budget rejected")
	var oversized := PackedFloat64Array()
	var oversized_mask := PackedByteArray()
	oversized.resize(16385)
	oversized_mask.resize(16385)
	t.eq(CharacterAnim.plan_crowd_tiers(oversized, oversized_mask, 1, 1, false).size(),
		0, "crowds over 16384 rejected")


	t.current = "render-frame crowd tiers use bounded hysteresis around distance thresholds"
	var jitter_distances := PackedFloat64Array([22.3, 37.2, 60.6, 89.4, 90.2])
	var old_tiers := PackedInt32Array([0, 1, 2, 3, 4])
	var no_flags := PackedByteArray([0, 0, 0, 0, 0])
	var stable_result: PackedInt32Array = CharacterAnim.plan_crowd_tiers_stable(
		jitter_distances, no_flags, old_tiers, 1, 0, 1.5, false)
	t.eq(stable_result, PackedInt32Array([0, 1, 2, 3, 4]),
		"small oscillations preserve prior pose tiers")
	var crossed: PackedInt32Array = CharacterAnim.plan_crowd_tiers_stable(
		PackedFloat64Array([23.6, 39.6, 62.0, 92.0, 87.0]), no_flags,
		old_tiers, 1, 0, 1.5, false)
	t.eq(crossed, PackedInt32Array([1, 2, 3, 4, 3]),
		"new tiers apply when camera crosses the actual margin")
	var full_crowd := CharacterAnim.plan_crowd_tiers_stable(
		PackedFloat64Array([10.0, 10.4, 10.8]), PackedByteArray([1, 1, 1]),
		PackedInt32Array([0, 1, 1]), 1, 1, 1.5, false)
	t.eq(full_crowd, PackedInt32Array([0, 1, 1]),
		"prior full pose has stability but never exceeds hard slots")
	var urgent := CharacterAnim.plan_crowd_tiers_stable(
		PackedFloat64Array([90.5, 89.2]), PackedByteArray([1, 1]),
		PackedInt32Array([1, 3]), 0, 1, 1.5, false)
	t.eq(urgent, PackedInt32Array([1, 3]),
		"combat priority avoids flicker near the far threshold")
	t.eq(CharacterAnim.plan_crowd_tiers_stable(positions, priorities,
		PackedInt32Array([0, 0, 0, 0, 0, 0]), 1, 1, 0.0, false),
		CharacterAnim.plan_crowd_tiers(positions, priorities, 1, 1, false),
		"zero hysteresis exactly preserves legacy planner")
	t.eq(CharacterAnim.plan_crowd_tiers_stable(PackedFloat64Array([10.0]),
		PackedByteArray([0]), PackedInt32Array([5]), 1, 0, 1.5, false).size(),
		0, "invalid previous tier rejected")
	t.eq(CharacterAnim.plan_crowd_tiers_stable(PackedFloat64Array([10.0]),
		PackedByteArray([0]), PackedInt32Array(), 1, 0, 1.5, false).size(),
		0, "misaligned actor tiers rejected")
	t.eq(CharacterAnim.plan_crowd_tiers_stable(PackedFloat64Array([10.0]),
		PackedByteArray([0]), PackedInt32Array([0]), 1, 0, NAN, false).size(),
		0, "NaN hysteresis rejected")

	if ClassDB.class_exists("CrowdAnimationTierPlanner"):
		var native_stable: Object = ClassDB.instantiate("CrowdAnimationTierPlanner")
		if native_stable != null and native_stable.has_method("plan_tiers_stable"):
			for full_slots in [0, 1, 4]:
				for priority_slots in [0, 1, 4]:
					var ds := PackedFloat64Array()
					var flags := PackedByteArray()
					var prior := PackedInt32Array()
					for i in 120:
						ds.append(float(i % 25) * 4.0 + float(i % 3) * 0.25)
						flags.append(1 if i % 7 == 0 else 0)
						prior.append(i % 5)
					var fallback: PackedInt32Array = CharacterAnim.plan_crowd_tiers_stable(
						ds, flags, prior, full_slots, priority_slots, 1.5, false)
					var actual: PackedInt32Array = native_stable.call(
						"plan_tiers_stable", ds, flags, prior, full_slots, priority_slots, 1.5)
					t.eq(actual, fallback, "native hysteresis parity for budgets %d/%d" % [
						full_slots, priority_slots])

	t.current = "native planner agrees with script fallback on structured crowds"
	if ClassDB.class_exists("CrowdAnimationTierPlanner"):
		var native: Object = ClassDB.instantiate("CrowdAnimationTierPlanner")
		t.check(native != null and native.has_method("plan_tiers"),
			"C++ planner registered and callable")
		if native != null and native.has_method("plan_tiers"):
			for full_slots in [0, 1, 2, 8]:
				for priority_slots in [0, 1, 3, 8]:
					var d := PackedFloat64Array()
					var p := PackedByteArray()
					for i in 120:
						d.append(float(i % 25) * 4.0)
						p.append(1 if (i % 7) == 0 else 0)
					var fallback: PackedInt32Array = CharacterAnim.plan_crowd_tiers(
						d, p, full_slots, priority_slots, false)
					var output: PackedInt32Array = native.call(
						"plan_tiers", d, p, full_slots, priority_slots)
					t.eq(output, fallback, "native/script parity for budgets %d/%d" % [
						full_slots, priority_slots])
