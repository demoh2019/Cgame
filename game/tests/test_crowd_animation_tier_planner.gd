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


	t.current = "camera-visible crowd reclaims expensive animation slots"
	var visible := PackedByteArray([0, 1, 0, 1, 0, 1])
	var visible_expected := PackedInt32Array([2, 0, 2, 1, 3, 4])
	t.eq(CharacterAnim.plan_crowd_tiers(positions, priorities, 1, 1, false, visible),
		visible_expected, "off-screen nearest and far attackers cannot consume IK or combat slots")
	var all_visible := PackedByteArray([1, 1, 1, 1, 1, 1])
	t.eq(CharacterAnim.plan_crowd_tiers(positions, priorities, 1, 1, false, all_visible),
		expected, "all-visible crowd preserves legacy exact tier results")
	var all_hidden := PackedByteArray([0, 0, 0, 0, 0, 0])
	t.eq(CharacterAnim.plan_crowd_tiers(positions, priorities, 16, 16, false, all_hidden),
		PackedInt32Array([2, 2, 2, 2, 3, 4]),
		"hidden actors retain a reduced animation update instead of pausing entirely")
	t.eq(CharacterAnim.plan_crowd_tiers(positions, priorities, 1, 1, false,
		PackedByteArray([1])).size(), 0, "mismatched visibility masks reject atomically")
	t.eq(CharacterAnim.plan_crowd_tiers(PackedFloat64Array([NAN]), PackedByteArray([1]),
		1, 1, false, PackedByteArray([1])).size(), 0,
		"invalid distance cannot yield a partial visible crowd tier batch")
	var camera_source := FileAccess.get_file_as_string("res://scripts/client/character_anim.gd")
	t.check(camera_source.contains("visible_mask.append(1 if visible else 0)") and
		camera_source.contains("CombatAnimationPriority.slots(quality), true, visible_mask"),
		"real Albion After crowd pass feeds frustum visibility to the native engine")

	t.current = "native visibility budget agrees with stock-Godot fallback"
	# This also checks stock Godot and older Cgame binaries without the extension.
	t.eq(CharacterAnim.plan_crowd_tiers(positions, priorities, 1, 1, true, visible),
		visible_expected, "auto-selects native planning or the equivalent safe fallback")
	if ClassDB.class_exists("CrowdAnimationTierPlanner"):
		var native_visible: Object = ClassDB.instantiate("CrowdAnimationTierPlanner")
		if native_visible != null and native_visible.has_method("plan_visible_tiers"):
			t.eq(native_visible.call("plan_visible_tiers", positions, priorities, visible, 1, 1),
				visible_expected, "native engine exposes visibility-aware planning")
			for full_slots in [0, 1, 4, 12]:
				for priority_slots in [0, 1, 3, 7]:
					var batch_distances := PackedFloat64Array()
					var batch_priority := PackedByteArray()
					var batch_visible := PackedByteArray()
					for i in 120:
						batch_distances.append(float(i % 29) * 4.0)
						batch_priority.append(1 if i % 5 == 0 else 0)
						batch_visible.append(0 if i % 3 == 0 else 1)
					var fallback: PackedInt32Array = CharacterAnim.plan_crowd_tiers(
						batch_distances, batch_priority, full_slots, priority_slots,
						false, batch_visible)
					var planned: PackedInt32Array = native_visible.call(
						"plan_visible_tiers", batch_distances, batch_priority,
						batch_visible, full_slots, priority_slots)
					t.eq(planned, fallback, "native/script visible-crowd parity %d/%d" % [
						full_slots, priority_slots])
					var full_count: int = 0
					for tier in planned:
						if tier == 0:
							full_count += 1
					t.check(full_count <= full_slots,
						"native visibility planner respects full IK slot cap")


	t.current = "stable full-IK slots resist camera jitter without hiding combat"
	var stable_distances := PackedFloat64Array([10.0, 10.4, 21.0, 22.0, 50.0])
	var stable_priority := PackedByteArray([0, 0, 0, 1, 1])
	var stable_visible := PackedByteArray([1, 1, 1, 1, 1])
	var stable_retained := PackedByteArray([0, 1, 1, 1, 0])
	var stable_expected := PackedInt32Array([1, 0, 1, 1, 2])
	t.eq(CharacterAnim.plan_crowd_tiers(stable_distances, stable_priority, 1, 1,
		false, stable_visible, stable_retained, 1.5), stable_expected,
		"the previous IK owner wins a small distance difference")
	t.eq(CharacterAnim.plan_crowd_tiers(stable_distances, stable_priority, 1, 1,
		false, stable_visible, stable_retained, 0.0),
		CharacterAnim.plan_crowd_tiers(stable_distances, stable_priority, 1, 1,
			false, stable_visible), "zero hysteresis reproduces old visibility planner")
	var none_retained := PackedByteArray([0, 0, 0, 0, 0])
	t.eq(CharacterAnim.plan_crowd_tiers(stable_distances, stable_priority, 1, 1,
		false, stable_visible, none_retained, 1.5),
		CharacterAnim.plan_crowd_tiers(stable_distances, stable_priority, 1, 1,
			false, stable_visible), "no previous owner yields original nearest IK selection")
	var hidden_held := PackedByteArray([1, 0, 1, 1, 1])
	t.eq(CharacterAnim.plan_crowd_tiers(stable_distances, stable_priority, 1, 1,
		false, hidden_held, stable_retained, 1.5),
		PackedInt32Array([0, 2, 1, 1, 2]),
		"an invisible former owner releases expensive work immediately")
	var closer_distances := PackedFloat64Array([8.0, 10.4, 21.0, 22.0, 50.0])
	t.eq(CharacterAnim.plan_crowd_tiers(closer_distances, stable_priority, 1, 1,
		false, stable_visible, stable_retained, 1.5)[0], 0,
		"a materially closer newly visible actor takes priority")
	t.eq(CharacterAnim.plan_crowd_tiers(stable_distances, stable_priority, 1, 1,
		false, stable_visible, PackedByteArray([0]), 1.5).size(), 0,
		"mismatched retention masks fail closed")
	t.eq(CharacterAnim.plan_crowd_tiers(stable_distances, stable_priority, 1, 1,
		false, stable_visible, stable_retained, -0.1).size(), 0,
		"negative hysteresis is invalid")
	t.eq(CharacterAnim.plan_crowd_tiers(stable_distances, stable_priority, 1, 1,
		false, stable_visible, stable_retained, 8.01).size(), 0,
		"excessive hysteresis is invalid")
	t.eq(CharacterAnim.plan_crowd_tiers(stable_distances, stable_priority, 1, 1,
		false, stable_visible, stable_retained, NAN).size(), 0,
		"NaN retention strength rejected atomically")
	var anim_source := FileAccess.get_file_as_string("res://scripts/client/character_anim.gd")
	var model_source := FileAccess.get_file_as_string("res://scripts/client/character_model.gd")
	t.check(anim_source.contains("retained_full_mask.append(") and
		anim_source.contains("IK_RETENTION_HYSTERESIS_METRES") and
		anim_source.contains('model.set_meta("aa_full_ik_retained", full_ik_now)'),
		"real Albion crowd pass keeps previous-frame IK owners")
	t.check(model_source.contains('set_meta("aa_full_ik_retained", false)'),
		"pooled character reuse clears stale IK retention")

	t.current = "native and stock-Godot stable crowd tier parity"
	t.eq(CharacterAnim.plan_crowd_tiers(stable_distances, stable_priority, 1, 1,
		true, stable_visible, stable_retained, 1.5), stable_expected,
		"engine-dispatched stable planner matches expected IK assignment")
	if ClassDB.class_exists("CrowdAnimationTierPlanner"):
		var native_stable: Object = ClassDB.instantiate("CrowdAnimationTierPlanner")
		if native_stable != null and native_stable.has_method("plan_visible_tiers_stable"):
			t.eq(native_stable.call("plan_visible_tiers_stable", stable_distances,
				stable_priority, stable_visible, stable_retained, 1, 1, 1.5),
				stable_expected, "native stable IK interface is exposed and correct")
			var stable_rng := RandomNumberGenerator.new()
			stable_rng.seed = 524019
			for sample in 12:
				var sampled_distances := PackedFloat64Array()
				var sampled_priorities := PackedByteArray()
				var sampled_visibility := PackedByteArray()
				var sampled_retained := PackedByteArray()
				for i in 128:
					sampled_distances.append(float(stable_rng.randi_range(0, 1100)) * 0.1)
					sampled_priorities.append(1 if stable_rng.randi_range(0, 4) == 0 else 0)
					sampled_visibility.append(1 if stable_rng.randi_range(0, 4) > 0 else 0)
					sampled_retained.append(1 if stable_rng.randi_range(0, 9) == 0 else 0)
				for budget in [0, 1, 4, 12]:
					for hysteresis in [0.0, 1.5, 8.0]:
						var script_tiers: PackedInt32Array = CharacterAnim.plan_crowd_tiers(
							sampled_distances, sampled_priorities, budget, 3, false,
							sampled_visibility, sampled_retained, hysteresis)
						var native_tiers: PackedInt32Array = native_stable.call(
							"plan_visible_tiers_stable", sampled_distances,
							sampled_priorities, sampled_visibility, sampled_retained,
							budget, 3, hysteresis)
						t.eq(native_tiers, script_tiers,
							"stable native/script parity sample %d slots %d bonus %.1f" % [
								sample, budget, hysteresis])


	t.current = "independent combat animation retention on top of existing IK hysteresis"
	var combat_d := PackedFloat64Array([5.6, 5.4, 60.5, 60.3])
	var combat_p := PackedByteArray([0, 0, 1, 1])
	var combat_v := PackedByteArray([1, 1, 1, 1])
	var full_old := PackedByteArray([1, 0, 0, 0])
	var combat_old := PackedByteArray([0, 0, 1, 0])
	var dual: PackedInt32Array = CharacterAnim.plan_crowd_tiers(
		combat_d, combat_p, 1, 1, false, combat_v, full_old, 1.5,
		combat_old, 1.0)
	t.eq(dual, PackedInt32Array([0, 1, 1, 3]),
		"two independent budgets retain near IK and distant combat animation")
	t.eq(CharacterAnim.plan_crowd_tiers(combat_d, combat_p, 1, 1,
		false, combat_v, full_old, 1.5, combat_old, 0.0),
		PackedInt32Array([0, 1, 3, 1]),
		"zero combat bonus preserves previously merged full-IK-only ranking")
	t.eq(CharacterAnim.plan_crowd_tiers(
		PackedFloat64Array([7.0, 5.4, 62.0, 60.3]), combat_p, 1, 1,
		false, combat_v, full_old, 1.0, combat_old, 1.0),
		PackedInt32Array([1, 0, 3, 1]),
		"large distance changes release retained combat and IK slots")

	t.current = "retained combat does not exceed visibility or the 90m radius"
	t.eq(CharacterAnim.plan_crowd_tiers(
		PackedFloat64Array([21.9, 22.1, 89.9, 90.1, 3.0]),
		PackedByteArray([0, 0, 1, 1, 1]), 1, 1, false,
		PackedByteArray([1, 1, 1, 1, 0]), PackedByteArray([1, 1, 0, 0, 1]),
		4.0, PackedByteArray([0, 0, 1, 1, 1]), 4.0),
		PackedInt32Array([0, 1, 1, 4, 2]),
		"retention cannot keep an offscreen attack, out-of-range warning or excess IK")
	t.eq(CharacterAnim.plan_crowd_tiers(combat_d, combat_p, 1, 1,
		false, combat_v, full_old, 1.5, PackedByteArray([1]), 1.0).size(), 0,
		"invalid history size is rejected")
	t.eq(CharacterAnim.plan_crowd_tiers(combat_d, combat_p, 1, 1,
		false, combat_v, full_old, 1.5, combat_old, NAN).size(), 0,
		"NaN combat retention is rejected")
	t.eq(CharacterAnim.plan_crowd_tiers(combat_d, combat_p, 1, 1,
		false, combat_v, full_old, 1.5, combat_old, 4.1).size(), 0,
		"combat retention is limited to four metres")

	t.current = "real Albion crowd pass stores combat priority per model"
	var updated_source: String = (CharacterAnim as Script).source_code
	t.check(updated_source.contains('model.get_meta("aa_combat_pose_retained", false)') and
		updated_source.contains('model.set_meta("aa_combat_pose_retained", combat_promoted)'),
		"client animation stores each actor's combat-pose retention without index leak")
	var model_script: String = FileAccess.get_file_as_string("res://scripts/client/character_model.gd")
	t.check(model_script.contains('set_meta("aa_combat_pose_retained", false)'),
		"reused character models discard previous combat budget ownership")
	t.eq(CharacterAnim.plan_crowd_tiers(combat_d, combat_p, 1, 1,
		true, combat_v, full_old, 1.5, combat_old, 1.0), dual,
		"new native method or older engine fallback preserves the same selection")
	if ClassDB.class_exists("CrowdAnimationTierPlanner"):
		var dual_native: Object = ClassDB.instantiate("CrowdAnimationTierPlanner")
		if dual_native != null and dual_native.has_method("plan_visible_tiers_temporal"):
			t.eq(dual_native.call("plan_visible_tiers_temporal", combat_d, combat_p,
				combat_v, full_old, combat_old, 1, 1, 1.5, 1.0),
				dual, "native independent combat and IK retention parity")
			for trial in 10:
				var d := PackedFloat64Array()
				var p := PackedByteArray()
				var v := PackedByteArray()
				var f := PackedByteArray()
				var c := PackedByteArray()
				for i in 120:
					d.append(float((i * 13 + trial * 7) % 110) + float(i % 5) * 0.2)
					p.append(1 if i % 3 == 0 else 0)
					v.append(1 if i % 7 != 0 else 0)
					f.append(1 if i % 9 == 0 else 0)
					c.append(1 if i % 4 == 0 else 0)
				var fallback: PackedInt32Array = CharacterAnim.plan_crowd_tiers(
					d, p, 8, 4, false, v, f, 1.5, c, 1.5)
				var native_tiers: PackedInt32Array = dual_native.call(
					"plan_visible_tiers_temporal", d, p, v, f, c, 8, 4, 1.5, 1.5)
				t.eq(native_tiers, fallback,
					"native/script dual retention parity sample %d" % trial)


	t.current = "optional measured IK CPU cap composes with two independent pose budgets"
	var cap_distances := PackedFloat64Array([5.6, 5.4, 60.5, 60.3])
	var cap_priority := PackedByteArray([0, 0, 1, 1])
	var cap_visible := PackedByteArray([1, 1, 1, 1])
	var cap_full_retained := PackedByteArray([1, 0, 0, 0])
	var cap_combat_retained := PackedByteArray([0, 0, 1, 0])
	var cap_tiers := CharacterAnim.plan_crowd_tiers(
		cap_distances, cap_priority, 1, 1, false, cap_visible, cap_full_retained,
		1.5, cap_combat_retained, 1.0)
	var cap_expected := PackedInt32Array([1, 1, 1, 3])
	t.eq(CharacterAnim.cap_full_pose_cost(cap_tiers, cap_distances,
		cap_full_retained, PackedInt32Array([800, 90, 0, 0]), 100, 1.5, false),
		cap_expected, "expensive optional IK drops, but retained visible combat pose remains")
	t.eq(cap_tiers, PackedInt32Array([0, 1, 1, 3]),
		"CPU admission never mutates the original animation policy")
	t.eq(CharacterAnim.cap_full_pose_cost(cap_tiers, cap_distances,
		cap_full_retained, PackedInt32Array([800, 90, 0, 0]), 0, 1.5, false),
		cap_tiers, "a zero CPU budget disables the extra limit")
	var cheap_tiers := PackedInt32Array([0, 0, 0, 1, 2])
	var cheap_distances := PackedFloat64Array([2.0, 4.0, 10.0, 18.0, 55.0])
	var cheap_retained := PackedByteArray([0, 0, 0, 0, 0])
	var cheap_costs := PackedInt32Array([500, 100, 100, 100, 0])
	t.eq(CharacterAnim.cap_full_pose_cost(cheap_tiers, cheap_distances,
		cheap_retained, cheap_costs, 250, 1.5, false),
		PackedInt32Array([1, 0, 0, 1, 2]),
		"nearest expensive pose skips IK while two cheaper poses fit")
	t.eq(CharacterAnim.cap_full_pose_cost(PackedInt32Array([0, 0, 1]),
		PackedFloat64Array([10.0, 10.4, 80.0]),
		PackedByteArray([0, 1, 0]), PackedInt32Array([0, 0, 0]),
		100, 1.5, false), PackedInt32Array([1, 0, 1]),
		"unmeasured models start at 100us and retained owner wins")
	t.eq(CharacterAnim.cap_full_pose_cost(cheap_tiers, cheap_distances,
		cheap_retained, PackedInt32Array([0]), 250, 1.5, false).size(),
		0, "cost samples must match all actors")
	t.eq(CharacterAnim.cap_full_pose_cost(cheap_tiers, cheap_distances,
		cheap_retained, PackedInt32Array([0, 0, -1, 0, 0]),
		250, 1.5, false).size(), 0, "invalid late cost fails atomically")
	t.eq(CharacterAnim.cap_full_pose_cost(cheap_tiers, cheap_distances,
		cheap_retained, cheap_costs, 1000001, 1.5, false).size(),
		0, "CPU budget over one second is invalid")
	t.eq(CharacterAnim.cap_full_pose_cost(cheap_tiers, cheap_distances,
		cheap_retained, cheap_costs, 250, NAN, false).size(),
		0, "NaN hysteresis fails atomically")
	t.current = "real Albion After procedural cost samples and native/script parity"
	var cap_source: String = FileAccess.get_file_as_string("res://scripts/client/character_anim.gd")
	var modifier_source: String = FileAccess.get_file_as_string(
		"res://scripts/client/character_anim_modifier.gd")
	t.check(cap_source.contains("tiers = cap_full_pose_cost(tiers, distances") and
		cap_source.contains("retained_combat_mask, 1.5") and
		cap_source.contains("full_pose_cost_us.append("),
		"real game passes independent combat, live full-IK history and measured costs")
	t.check(modifier_source.contains("Time.get_ticks_usec()") and
		modifier_source.contains("estimated_full_pose_us"),
		"procedural modifier measures bounded CPU work with a smoothed estimate")
	t.eq(CharacterAnim.cap_full_pose_cost(cap_tiers, cap_distances,
		cap_full_retained, PackedInt32Array([800, 90, 0, 0]), 100),
		cap_expected, "native-first dispatch or older-engine fallback returns expected tiers")
	if ClassDB.class_exists("CrowdAnimationTierPlanner"):
		var native_cap: Object = ClassDB.instantiate("CrowdAnimationTierPlanner")
		if native_cap != null and native_cap.has_method("cap_full_pose_cost"):
			var rng_cap := RandomNumberGenerator.new()
			rng_cap.seed = 127399
			for sample in 16:
				var sampled_tiers := PackedInt32Array()
				var sampled_distances := PackedFloat64Array()
				var sampled_retained := PackedByteArray()
				var sampled_costs := PackedInt32Array()
				for i in 120:
					sampled_tiers.append(0 if i % 5 == 0 else i % 4 + 1)
					sampled_distances.append(float(rng_cap.randi_range(0, 1100)) * 0.1)
					sampled_retained.append(1 if rng_cap.randi_range(0, 3) == 0 else 0)
					sampled_costs.append(rng_cap.randi_range(0, 800))
				for cost_limit in [0, 100, 750, 2000]:
					var fallback_cap: PackedInt32Array = CharacterAnim.cap_full_pose_cost(
						sampled_tiers, sampled_distances, sampled_retained,
						sampled_costs, cost_limit, 1.5, false)
					var native_result: PackedInt32Array = native_cap.call(
						"cap_full_pose_cost", sampled_tiers, sampled_distances,
						sampled_retained, sampled_costs, cost_limit, 1.5)
					t.eq(native_result, fallback_cap, "native/script work cap parity %d/%d" % [
						sample, cost_limit])
