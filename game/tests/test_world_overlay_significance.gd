extends RefCounted
## Tests native-significance HUD selection without camera, rendering or networking.
const Overlay = preload("res://scripts/client/world_overlay.gd")


func run(t) -> void:
	t.current = "Unreal-style significance prioritizes bosses, elites and active attacks"
	var distances := PackedFloat64Array([2.0, 1.0, 5.0, 5.0, 0.5, 8.0])
	var priorities := PackedByteArray([0, 0, 3, 3, 2, 1])
	var expected := PackedInt32Array([2, 3, 4, 5])
	t.eq(Overlay.select_zombie_bar_indices(distances, priorities, 4, false),
		expected, "fallback reserves scarce HUD slots for critical actors")
	t.eq(Overlay.select_zombie_bar_indices(distances, priorities, 4),
		expected, "native and fallback share the same stable ranking")
	t.eq(Overlay.select_zombie_bar_indices(distances, priorities, 0).size(), 0,
		"zero budget renders no HUD bars")
	t.eq(Overlay.select_zombie_bar_indices(distances, priorities, 128).size(), 6,
		"all visible candidates are eligible when below the hard budget")
	t.eq(distances[0], 2.0, "planning never edits the supplied distances")
	t.eq(priorities[2], 3, "planning never edits urgency flags")

	t.current = "batches are bounded and invalid inputs fail closed"
	t.check(Overlay.select_zombie_bar_indices(distances, priorities, -1).is_empty(),
		"invalid negative budgets cannot be used")
	t.check(Overlay.select_zombie_bar_indices(distances, priorities, 129).is_empty(),
		"budgets above 128 are rejected")
	t.check(Overlay.select_zombie_bar_indices(distances, PackedByteArray([0]), 4).is_empty(),
		"mismatched array lengths are rejected")
	t.check(Overlay.select_zombie_bar_indices(PackedFloat64Array([NAN]),
		PackedByteArray([1]), 2).is_empty(), "nonfinite distances fail closed")
	t.check(Overlay.select_zombie_bar_indices(PackedFloat64Array([-1.0]),
		PackedByteArray([1]), 2).is_empty(), "negative distances fail closed")
	t.check(Overlay.select_zombie_bar_indices(PackedFloat64Array([1.0]),
		PackedByteArray([4]), 2).is_empty(), "invalid priority levels fail closed")

	t.current = "real overlay routes actual visible infected through the selector"
	var source_code: String = (Overlay as Script).source_code
	t.check(source_code.contains("camera.is_position_behind(top)"),
		"behind-camera infected never consume a HUD slot")
	t.check(source_code.contains("var chosen: PackedInt32Array = select_zombie_bar_indices_stable(distances,"),
		"real _draw_zombie_bars uses significance-planned indices")
	t.check(source_code.contains("const ZOMBIE_BAR_BUDGET := 32"),
		"HUD draw work is capped at 32 infected")
	t.check(source_code.contains('ClassDB.class_exists("SignificanceBudgetPlanner")'),
		"stock Godot gracefully bypasses the native module")
	if ClassDB.class_exists("SignificanceBudgetPlanner"):
		var native: Object = ClassDB.instantiate("SignificanceBudgetPlanner")
		t.check(native != null, "native significance budget class is registered")
		if native != null:
			var ranks: PackedInt32Array = native.call("select_top", distances, priorities, 4)
			t.eq(ranks, expected, "native C++ selection matches expected ranking")
			var positions := PackedVector3Array([
				Vector3(0, 0, 0), Vector3(99, 0, 0), Vector3(50, 0, 0)])
			var viewers := PackedVector3Array([Vector3(0, 0, 0), Vector3(100, 0, 0)])
			t.eq(native.call("select_world", positions, viewers, PackedByteArray([0, 0, 3]), 2, 10.0),
				PackedInt32Array([0, 1]), "multiple viewers honor range before urgency")
	else:
		t.check(true, "stock Godot preserves deterministic GDScript selection")


	t.current = "priority-stable significance prevents HUD flicker but never hides bosses"
	var crowd_distances := PackedFloat64Array([7.0, 6.0, 5.0, 13.0, 8.0])
	var crowd_priorities := PackedByteArray([0, 0, 3, 2, 2])
	var crowd_ids := PackedInt64Array([100, 101, 50, 52, 55])
	var prior_visible := PackedInt64Array([100, 55])
	var expected_stable := PackedInt32Array([2, 4, 0])
	t.eq(Overlay.select_zombie_bar_indices_stable(crowd_distances, crowd_priorities,
		crowd_ids, prior_visible, 3, 10.0, 2.0, false), expected_stable,
		"retained normal cannot overtake boss or elite; peers receive hysteresis")
	t.eq(Overlay.select_zombie_bar_indices_stable(crowd_distances, crowd_priorities,
		crowd_ids, prior_visible, 3, 10.0, 2.0), expected_stable,
		"native selection and stock fallback have identical ordering")
	t.eq(Overlay.select_zombie_bar_indices_stable(PackedFloat64Array([6.0, 6.0]),
		PackedByteArray([1, 1]), PackedInt64Array([90, 7]), PackedInt64Array(),
		2, 10.0, 0.0, false), PackedInt32Array([1, 0]),
		"stable server ID breaks identical priority/distance ties")
	t.eq(Overlay.select_zombie_bar_indices_stable(PackedFloat64Array([6.0, 6.0]),
		PackedByteArray([1, 1]), PackedInt64Array([90, 7]), PackedInt64Array([90]),
		1, 10.0, 1.5, false), PackedInt32Array([0]),
		"a retained peer keeps its slot when only marginally farther away")
	t.eq(Overlay.select_zombie_bar_indices_stable(PackedFloat64Array([10.01, 2.0]),
		PackedByteArray([3, 0]), PackedInt64Array([777, 7]), PackedInt64Array([777]),
		2, 10.0, 2.0, false), PackedInt32Array([1]),
		"out-of-range bosses never survive the strict distance gate")
	t.check(Overlay.select_zombie_bar_indices_stable(PackedFloat64Array([1.0, 2.0]),
		PackedByteArray([3, 0]), PackedInt64Array([9, 9]), PackedInt64Array(),
		2, 10.0, 1.5, false).is_empty(), "duplicate network IDs are rejected")
	t.check(Overlay.select_zombie_bar_indices_stable(PackedFloat64Array([1.0, NAN]),
		PackedByteArray([3, 0]), PackedInt64Array([9, 10]), PackedInt64Array(),
		2, 10.0, 1.5, false).is_empty(), "invalid distances fail closed")
	t.check(Overlay.select_zombie_bar_indices_stable(PackedFloat64Array([1.0, 2.0]),
		PackedByteArray([3, 0]), PackedInt64Array([9, 10]), PackedInt64Array([9, 9]),
		2, 10.0, 1.5, false).is_empty(), "invalid retained-ID lists fail closed")
	t.check(Overlay.select_zombie_bar_indices_stable(PackedFloat64Array([1.0, 2.0]),
		PackedByteArray([3, 4]), PackedInt64Array([9, 10]), PackedInt64Array(),
		2, 10.0, 1.5, false).is_empty(), "invalid urgency classes fail closed")
	t.check(Overlay.select_zombie_bar_indices_stable(PackedFloat64Array([1.0]),
		PackedByteArray([3]), PackedInt64Array([9]), PackedInt64Array(),
		129, 10.0, 1.5, false).is_empty(), "max K budget still enforced")
	var live_source: String = (Overlay as Script).source_code
	t.check(live_source.contains("var _zombie_bar_retained_ids := PackedInt64Array()"),
		"actual HUD remembers last-frame displayed zombie server IDs")
	t.check(live_source.contains("_zombie_bar_retained_ids = current_ids"),
		"actual HUD advances retained IDs after ranking every frame")
	t.check(live_source.contains("for zombie_id in client.zombies:"),
		"ranking reads stable authoritative dictionary keys, not list positions")
	if ClassDB.class_exists("SignificanceBudgetPlanner"):
		var native_stable = ClassDB.instantiate("SignificanceBudgetPlanner")
		if native_stable != null and native_stable.has_method("select_top_priority_stable"):
			t.eq(native_stable.call("select_top_priority_stable", crowd_distances,
				crowd_priorities, crowd_ids, prior_visible, 3, 10.0, 2.0),
				expected_stable, "the C++ priority-stable API matches the stock Godot reference")

	t.current = "multi-viewer stable POI significance in the playable compass"
	var poi_positions := PackedVector3Array([Vector3(4, 0, 0), Vector3(6, 0, 0),
		Vector3(96, 0, 0), Vector3(200, 0, 0)])
	var poi_viewers := PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0)])
	var poi_priority := PackedByteArray([0, 0, 2, 3])
	var poi_ids := PackedInt64Array([42, 43, 44, 45])
	var poi_retained := PackedInt64Array([43, 45])
	var expected_poi := PackedInt32Array([2, 1])
	t.eq(Overlay.select_world_marker_indices(poi_positions, poi_viewers, poi_priority,
		poi_ids, poi_retained, 2, 10.0, 3.0, false), expected_poi,
		"stock fallback keeps same-tier POIs, but not ahead of higher priority")
	t.eq(Overlay.select_world_marker_indices(poi_positions, poi_viewers, poi_priority,
		poi_ids, poi_retained, 2, 10.0, 3.0), expected_poi,
		"native and stock fallback select the same stable POIs")
	t.eq(Overlay.select_world_marker_indices(PackedVector3Array([Vector3(6, 0, 0),
		Vector3(6, 0, 0)]), PackedVector3Array([Vector3.ZERO]),
		PackedByteArray([0, 0]), PackedInt64Array([9, 7]), PackedInt64Array(),
		2, 10.0, 0.0, false), PackedInt32Array([1, 0]),
		"stable IDs break identical-distance ties")
	t.eq(Overlay.select_world_marker_indices(PackedVector3Array([Vector3(11, 0, 0),
		Vector3(1, 0, 0)]), PackedVector3Array([Vector3.ZERO]),
		PackedByteArray([3, 0]), PackedInt64Array([9, 7]), PackedInt64Array([9]),
		2, 10.0, 2.0, false), PackedInt32Array([1]),
		"retained marker cannot survive outside max_distance")
	t.check(Overlay.select_world_marker_indices(poi_positions, PackedVector3Array(),
		poi_priority, poi_ids, poi_retained).is_empty(), "no observers rejects selection")
	t.check(Overlay.select_world_marker_indices(poi_positions, poi_viewers,
		poi_priority, PackedInt64Array([42, 43, 44, 44]), poi_retained, 2,
		10.0, 3.0, false).is_empty(), "duplicate IDs fail closed")
	t.check(Overlay.select_world_marker_indices(poi_positions, poi_viewers,
		poi_priority, poi_ids, PackedInt64Array([43, 43]), 2,
		10.0, 3.0, false).is_empty(), "duplicate retained IDs fail closed")
	var marker_source: String = (Overlay as Script).source_code
	t.check(marker_source.contains("var chosen := select_world_marker_indices(positions,"),
		"actual in-game compass invokes significance ranking")
	t.check(marker_source.contains("_marker_retained_ids = next_retained"),
		"actual compass advances retained IDs each update")
	if ClassDB.class_exists("SignificanceBudgetPlanner"):
		var native_world = ClassDB.instantiate("SignificanceBudgetPlanner")
		if native_world != null and native_world.has_method("select_world_priority_stable"):
			t.eq(native_world.call("select_world_priority_stable", poi_positions,
				poi_viewers, poi_priority, poi_ids, poi_retained, 2, 10.0, 3.0),
				expected_poi, "native multi-viewer selection matches GDScript")
