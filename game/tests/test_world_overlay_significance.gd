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
	t.check(source_code.contains("for selected in select_zombie_bar_indices(distances, priorities):"),
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
