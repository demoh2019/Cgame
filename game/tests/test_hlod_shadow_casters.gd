extends RefCounted
## Headless exact native/GDScript shadow HLOD plan parity and quality policy.
const ShadowBudget = preload("res://scripts/client/shadow_budget.gd")
const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")


func run(t) -> void:
	t.current = "HLOD solar shadow quota follows graphics quality"
	for quality in 4:
		t.check(ShadowBudget.cap_for_quality(quality) <= 128,
			"native maximum caster budget never exceeds 128")
	t.eq(ShadowBudget.cap_for_quality(-1), 0, "Performance disables extra sun shadows")
	t.eq(ShadowBudget.cap_for_quality(1), 8, "Balanced permits eight groups per chunk")
	t.eq(ShadowBudget.cap_for_quality(2), 16, "High permits sixteen groups per chunk")
	t.eq(ShadowBudget.cap_for_quality(3), 24, "Ultra permits twenty-four groups per chunk")
	t.eq(ShadowBudget.role_index("structure"), 2, "structures receive highest importance")
	t.eq(ShadowBudget.role_index("tree"), 1, "trees are medium importance")
	t.eq(ShadowBudget.role_index("bush"), 0, "bushes are lowest importance")
	t.eq(ShadowBudget.role_index("unknown"), 3, "unknown role cannot consume budget")

	ShadowBudget.configure(VisualProfiles.settings(1))
	t.current = "world AABB ranking preserves nearest trees and landmarks"
	var lower := PackedVector3Array()
	var upper := PackedVector3Array()
	for d in [10.0, 1.0, 60.0, 9.0, 0.0]:
		lower.append(Vector3(d, 100.0, 0.0))
		upper.append(Vector3(d + 2.0, 150.0, 3.0))
	var roles := PackedByteArray([1, 0, 2, 1, 3])
	var active := PackedByteArray([0, 0, 0, 1, 0])
	var chosen: PackedInt32Array = ShadowBudget.select_shadow_casters(
		lower, upper, roles, active, Vector3.ZERO, 3, false)
	t.eq(chosen, PackedInt32Array([2, 3, 0]),
		"landmarks win, then retained/nearest trees; bush loses limited slot")
	t.eq(ShadowBudget.select_shadow_casters(
		lower, upper, roles, active, Vector3.ZERO, 0, false).size(),
		0, "zero quality cap drops all cosmetic shadows")
	lower[0] = Vector3(0, 100, 0)
	upper[0] = Vector3(10, 150, 10)
	chosen = ShadowBudget.select_shadow_casters(
		lower, upper, roles, active, Vector3(5, 1000, 5), 3, false)
	t.eq(chosen, PackedInt32Array([2, 0, 3]),
		"camera altitude ignored; actual world-space footprint used")

	t.current = "shadow hysteresis boundaries and malformed input"
	lower.clear()
	upper.clear()
	for d in [44.0, 52.0, 53.0, 54.0, 43.0]:
		lower.append(Vector3(d, 0, 0))
		upper.append(Vector3(d, 1, 1))
	roles = PackedByteArray([1, 1, 1, 1, 1])
	active = PackedByteArray([0, 1, 1, 1, 0])
	t.eq(ShadowBudget.select_shadow_casters(
		lower, upper, roles, active, Vector3.ZERO, 3, false),
		PackedInt32Array([4, 1, 2]),
		"new cast enters at radius - 5; existing remains until radius + 5")
	t.eq(ShadowBudget.select_shadow_casters(
		lower, upper, roles, active, Vector3.ZERO, 129, false).size(), 0,
		"invalid budget atomically rejected")
	var invalid := lower.duplicate()
	invalid[4] = Vector3(NAN, 0, 0)
	t.eq(ShadowBudget.select_shadow_casters(
		invalid, upper, roles, active, Vector3.ZERO, 3, false).size(), 0,
		"late NaN rejects entire render plan, not a partial prefix")
	ShadowBudget.configure(VisualProfiles.settings(0))
	t.eq(ShadowBudget.select_shadow_casters(
		lower, upper, roles, active, Vector3.ZERO, 3, false).size(), 0,
		"Performance zero radius disables even previously active casters")
	ShadowBudget.configure(VisualProfiles.settings(1))

	t.current = "native significance HLOD shadow plan matches script at scale"
	if ClassDB.class_exists("SignificanceBudgetPlanner"):
		var planner: Object = ClassDB.instantiate("SignificanceBudgetPlanner")
		if planner != null and planner.has_method("select_shadow_casters"):
			var rng := RandomNumberGenerator.new()
			rng.seed = 229875
			for sample in 24:
				var lows := PackedVector3Array()
				var highs := PackedVector3Array()
				var kinds := PackedByteArray()
				var states := PackedByteArray()
				for i in 80:
					var point := Vector3(rng.randf_range(-80.0, 80.0),
						rng.randf_range(-10.0, 10.0),
						rng.randf_range(-80.0, 80.0))
					lows.append(point)
					highs.append(point + Vector3(rng.randf_range(0.5, 8.0),
						rng.randf_range(0.5, 10.0), rng.randf_range(0.5, 8.0)))
					kinds.append(rng.randi_range(0, 3))
					states.append(rng.randi_range(0, 1))
				var radii := PackedFloat64Array([
					ShadowBudget.radius_for("bush"),
					ShadowBudget.radius_for("tree"),
					ShadowBudget.radius_for("structure")])
				for cap in [0, 1, 8, 16, 24]:
					var expected: PackedInt32Array = ShadowBudget.select_shadow_casters(
						lows, highs, kinds, states, Vector3.ZERO, cap, false)
					t.eq(planner.call("select_shadow_casters", lows, highs, kinds,
						states, Vector3.ZERO, radii, cap, 5.0), expected,
						"native/GDScript exact parity sample %d quota %d" % [sample, cap])
					t.eq(ShadowBudget.select_shadow_casters(
						lows, highs, kinds, states, Vector3.ZERO, cap), expected,
						"actual client dispatch parity sample %d quota %d" % [sample, cap])
	# Restore default Balanced profile for the rest of the headless test run.
	ShadowBudget.configure(VisualProfiles.settings(1))
