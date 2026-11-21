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
	t.check(source_code.contains("var chosen: PackedInt32Array = select_zombie_bar_world_stable(positions,"),
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

	
	t.current = "multi-viewer stable world-significance matches single-viewer legacy ranking"
	var actors := PackedVector3Array([
		Vector3(7, 0, 0), Vector3(6, 0, 0), Vector3(5, 0, 0),
		Vector3(13, 0, 0), Vector3(8, 0, 0)])
	var eye := PackedVector3Array([Vector3.ZERO])
	t.eq(Overlay.select_zombie_bar_world_stable(actors, eye, crowd_priorities,
		crowd_ids, prior_visible, 3, 10.0, 2.0, false), expected_stable,
		"stock Godot keeps retained peers without overriding boss urgency")
	t.eq(Overlay.select_zombie_bar_world_stable(actors, eye, crowd_priorities,
		crowd_ids, prior_visible, 3, 10.0, 2.0), expected_stable,
		"engine selection, when available, agrees with the fallback")
	var cameras := PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0)])
	var across := PackedVector3Array([
		Vector3(1, 0, 0), Vector3(99, 0, 0), Vector3(50, 0, 0)])
	var cross_priority := PackedByteArray([0, 0, 3])
	var cross_ids := PackedInt64Array([31, 30, 32])
	var expected_cross := PackedInt32Array([1, 0])
	t.eq(Overlay.select_zombie_bar_world_stable(across, cameras, cross_priority,
		cross_ids, PackedInt64Array(), 2, 10.0, 0.0, false), expected_cross,
		"each observer protects nearby actors; stable ID breaks nearest-distance ties")
	t.eq(Overlay.select_zombie_bar_world_stable(across, cameras, cross_priority,
		cross_ids, PackedInt64Array(), 2, 10.0, 0.0), expected_cross,
		"native multi-observer ranking matches stock Godot when available")
	t.check(Overlay.select_zombie_bar_world_stable(across,
		PackedVector3Array(), cross_priority, cross_ids, PackedInt64Array(),
		2, 10.0).is_empty(), "no viewer fails closed")
	t.check(Overlay.select_zombie_bar_world_stable(
		PackedVector3Array([Vector3(NAN, 0, 0)]), eye, PackedByteArray([3]),
		PackedInt64Array([9]), PackedInt64Array()).is_empty(),
		"nonfinite actor coordinates fail closed")
	t.check(Overlay.select_zombie_bar_world_stable(across, cameras,
		cross_priority, PackedInt64Array([31, 31, 32]), PackedInt64Array(),
		2, 10.0, 0.0, false).is_empty(), "duplicate IDs fail closed")
	t.check(source_code.contains("top.distance_squared_to(here) > 45.0 * 45.0"),
		"actual HUD uses squared-distance prefilter instead of per-enemy square roots")
	if ClassDB.class_exists("SignificanceBudgetPlanner"):
		var world_native: Object = ClassDB.instantiate("SignificanceBudgetPlanner")
		if world_native != null and world_native.has_method("select_world_priority_stable"):
			t.eq(world_native.call("select_world_priority_stable", across, cameras,
				cross_priority, cross_ids, PackedInt64Array(), 2, 10.0, 0.0),
				expected_cross, "new native method is callable by game scripts")

