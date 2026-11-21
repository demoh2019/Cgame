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


	t.current = "measured procedural-IK budget conserves time and combat poses"
	var cpu_distances := PackedFloat64Array([2.0, 4.0, 10.0, 18.0, 55.0])
	var cpu_priority := PackedByteArray([0, 0, 0, 1, 1])
	var cpu_visible := PackedByteArray([1, 1, 1, 1, 1])
	var cpu_retained := PackedByteArray([0, 0, 0, 0, 0])
	var cpu_costs := PackedInt32Array([500, 100, 100, 100, 0])
	var cpu_expected := PackedInt32Array([1, 0, 0, 1, 2])
	t.eq(CharacterAnim.plan_crowd_tiers_costed(cpu_distances, cpu_priority,
		cpu_visible, cpu_retained, cpu_costs, 3, 1, 250, 1.5, false),
		cpu_expected, "expensive IK owner defers; two cheaper visible owners fit")
	t.eq(CharacterAnim.plan_crowd_tiers_costed(cpu_distances, cpu_priority,
		cpu_visible, cpu_retained, cpu_costs, 3, 1, 0, 1.5, false),
		CharacterAnim.plan_crowd_tiers(cpu_distances, cpu_priority, 3, 1,
			false, cpu_visible, cpu_retained, 1.5),
		"disabling the microsecond budget restores the previous tier planner")
	var small_distances := PackedFloat64Array([10.0, 10.4, 21.0, 22.0])
	var small_priority := PackedByteArray([0, 0, 0, 1])
	var small_visible := PackedByteArray([1, 1, 1, 1])
	var small_retained := PackedByteArray([0, 1, 1, 1])
	var small_cost := PackedInt32Array([1000, 75, 100, 0])
	t.eq(CharacterAnim.plan_crowd_tiers_costed(small_distances, small_priority,
		small_visible, small_retained, small_cost, 2, 1, 80, 1.5, false),
		PackedInt32Array([1, 0, 1, 1]),
		"previous retained IK winner remains selected when its cost fits")
	t.eq(CharacterAnim.plan_crowd_tiers_costed(small_distances, small_priority,
		small_visible, small_retained, PackedInt32Array([0, 0, 0, 0]),
		2, 1, 100, 1.5, false),
		PackedInt32Array([1, 0, 1, 1]),
		"unknown costs use the bounded 100us initial estimate")
	t.eq(CharacterAnim.plan_crowd_tiers_costed(small_distances, small_priority,
		PackedByteArray([1, 0, 1, 1]), small_retained, small_cost,
		2, 1, 80, 1.5, false)[1], 2,
		"no hysteresis keeps an invisible IK owner active")
	t.eq(CharacterAnim.plan_crowd_tiers_costed(small_distances, small_priority,
		small_visible, small_retained, PackedInt32Array([100]), 2, 1, 80,
		1.5, false).size(), 0, "mismatched costs fail atomically")
	t.eq(CharacterAnim.plan_crowd_tiers_costed(small_distances, small_priority,
		small_visible, small_retained, PackedInt32Array([1, -1, 1, 1]),
		2, 1, 80, 1.5, false).size(), 0,
		"negative measured CPU cost rejected")
	t.eq(CharacterAnim.plan_crowd_tiers_costed(small_distances, small_priority,
		small_visible, small_retained, small_cost, 2, 1, 1000001,
		1.5, false).size(), 0, "unbounded CPU budget rejected")
	t.eq(CharacterAnim.plan_crowd_tiers_costed(small_distances, small_priority,
		small_visible, small_retained, small_cost, 2, 1, 80,
		NAN, false).size(), 0, "invalid hysteresis rejected before planning")
	var anim_source_cpu := FileAccess.get_file_as_string("res://scripts/client/character_anim.gd")
	var modifier_source_cpu := FileAccess.get_file_as_string(
		"res://scripts/client/character_anim_modifier.gd")
	t.check(anim_source_cpu.contains("full_pose_cost_us.append(") and
		anim_source_cpu.contains("FULL_POSE_CPU_BUDGET_US[clampi(quality, 0, 3)]"),
		"real Albion crowd pass supplies a quality-based measured CPU budget")
	t.check(modifier_source_cpu.contains("Time.get_ticks_usec()") and
		modifier_source_cpu.contains("estimated_full_pose_us"),
		"actual procedural skeleton modifier records bounded runtime measurements")

	t.current = "native and script CPU-cost crowd tier parity"
	t.eq(CharacterAnim.plan_crowd_tiers_costed(cpu_distances, cpu_priority,
		cpu_visible, cpu_retained, cpu_costs, 3, 1, 250),
		cpu_expected, "native preferred call matches expected work-unit admission")
	if ClassDB.class_exists("CrowdAnimationTierPlanner"):
		var native_costed: Object = ClassDB.instantiate("CrowdAnimationTierPlanner")
		if native_costed != null and native_costed.has_method("plan_visible_tiers_costed"):
			t.eq(native_costed.call("plan_visible_tiers_costed", cpu_distances,
				cpu_priority, cpu_visible, cpu_retained, cpu_costs, 3, 1, 250),
				cpu_expected, "native Cgame exposes cost-bounded crowd API")
			var cpu_rng := RandomNumberGenerator.new()
			cpu_rng.seed = 341288
			for sample in 16:
				var ds := PackedFloat64Array()
				var pr := PackedByteArray()
				var vis := PackedByteArray()
				var held := PackedByteArray()
				var costs := PackedInt32Array()
				for i in 120:
					ds.append(float(cpu_rng.randi_range(0, 1050)) * 0.1)
					pr.append(1 if cpu_rng.randi_range(0, 4) == 0 else 0)
					vis.append(1 if cpu_rng.randi_range(0, 4) > 0 else 0)
					held.append(1 if cpu_rng.randi_range(0, 9) == 0 else 0)
					costs.append(cpu_rng.randi_range(0, 750))
				for slots in [0, 1, 4, 12]:
					for microseconds in [0, 100, 750, 2000]:
						var fallback := CharacterAnim.plan_crowd_tiers_costed(
							ds, pr, vis, held, costs, slots, 3, microseconds, 1.5, false)
						var native_result: PackedInt32Array = native_costed.call(
							"plan_visible_tiers_costed", ds, pr, vis, held, costs,
							slots, 3, microseconds, 1.5)
						t.eq(native_result, fallback,
							"native/script CPU budget parity %d slots %d cap %d" % [
								sample, slots, microseconds])
