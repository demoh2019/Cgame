extends RefCounted
## GPU shadow-map culling is purely visual and uses hysteresis at batch boundaries.

const ShadowBudget = preload("res://scripts/client/shadow_budget.gd")
const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")


func run(t) -> void:
	t.current = "distance-based shadow budgets"
	var low: Dictionary = VisualProfiles.settings(0)
	var balanced: Dictionary = VisualProfiles.settings(1)
	var high: Dictionary = VisualProfiles.settings(2)
	var ultra: Dictionary = VisualProfiles.settings(3)
	for role in ["tree", "bush", "structure"]:
		var key: String = role + "_shadow_radius"
		t.eq(float(low[key]), 0.0, "Performance disables %s shadow casters" % role)
		t.check(float(low[key]) < float(balanced[key]), "Balanced enables nearby %s shadows" % role)
		t.check(float(balanced[key]) < float(high[key]), "High extends %s shadows" % role)
		t.check(float(high[key]) < float(ultra[key]), "Ultra extends %s shadows" % role)
	ShadowBudget.configure(balanced)
	t.eq(ShadowBudget.radius_for("tree"), 48.0, "balanced tree shadow radius is configured")
	t.eq(ShadowBudget.radius_for("structure"), 68.0, "structures retain longer shadows")
	t.eq(ShadowBudget.radius_for("bush"), 26.0, "bush shadows use a short radius")
	t.check(not ShadowBudget.should_cast("unknown", 0.0, true), "unregistered objects never cast extra shadows")

	t.current = "shadow hysteresis"
	t.check(ShadowBudget.should_cast("tree", 42.0, false), "shadow begins comfortably inside radius")
	t.check(not ShadowBudget.should_cast("tree", 46.0, false), "an inactive shadow waits before restarting")
	t.check(ShadowBudget.should_cast("tree", 52.0, true), "active shadow survives the boundary")
	t.check(not ShadowBudget.should_cast("tree", 54.0, true), "distant shadow eventually stops")
	ShadowBudget.configure(low)
	t.check(not ShadowBudget.should_cast("structure", 0.0, true), "zero budget clears previously active shadows")

	t.current = "actual world geometry bounds"
	var box := AABB(Vector3(2.0, -3.0, 3.0), Vector3(10.0, 8.0, 5.0))
	t.near(ShadowBudget.distance_to_bounds_xz(Vector3(4.0, 50.0, 4.0), box), 0.0, 0.0001, "overhead camera is inside the group's ground footprint")
	t.near(ShadowBudget.distance_to_bounds_xz(Vector3(14.0, 10.0, 5.0), box), 2.0, 0.0001, "distance is measured from nearest batch edge")
	t.near(ShadowBudget.distance_to_bounds_xz(Vector3(12.0, -50.0, 11.0), box), 3.0, 0.0001, "height does not shrink the horizontal shadow reach")
	# Never leak a test-only budget into other integration tests.
	ShadowBudget.configure(balanced)
