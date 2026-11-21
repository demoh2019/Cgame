extends RefCounted
## Native ObjectDB class census is manually requested; no frame-time scan.
const Profiler = preload("res://scripts/client/object_population_profiler.gd")
const OnlineMain = preload("res://scripts/client/online_main.gd")


func run(t) -> void:
	t.current = "ObjectDB census is wired to the real debug-only game shortcut"
	var source: String = (OnlineMain as Script).source_code
	t.check(source.contains("OS.is_debug_build()") and
		source.contains("event.ctrl_pressed and event.shift_pressed"),
		"object census shortcut is debug-only and requires Ctrl+Shift")
	t.check(source.contains("event.keycode == KEY_F10"),
		"actual Albion online client exposes object diagnostics on Ctrl+Shift+F10")
	t.check(source.contains("ObjectPopulationProfiler.format_report(object_sample)"),
		"the game's normal HUD displays census and comparison")
	t.check(source.contains("get_viewport().set_input_as_handled()"),
		"debug key is consumed before ordinary gameplay item actions")

	t.current = "stock Godot debug and release fallback"
	var profiler = Profiler.new()
	if not profiler.available():
		t.check(profiler.sample().is_empty(),
			"without native debug profiler no ObjectDB scan is performed")
		t.check(Profiler.format_report({}).contains("debug engine"),
			"unsupported binaries give a useful safe message")
		return

	t.current = "native class census observes actual visual object lifetimes"
	var first: Dictionary = profiler.sample()
	t.check(first.has("total") and first.has("counts"),
		"one native synchronized pass provides total and per-class counts")
	t.eq(first["has_previous"], false, "first census establishes a baseline")
	t.eq(int(first["delta"]), 0, "first report does not invent object growth")
	t.eq((first["counts"] as Dictionary).size(), Profiler.TRACKED_CLASSES.size(),
		"all tracked gameplay visual classes have defined counters")
	t.check(int(first["total"]) > 0, "live game engine has registered objects")
	t.check(Profiler.format_report(first).contains("MultiMeshInstance3D"),
		"debug report names the important GPU-instanced scenery class")

	var temporary_node := Node3D.new()
	var temporary_mesh := MeshInstance3D.new()
	var second: Dictionary = profiler.sample()
	var changes: Dictionary = second["changes"]
	t.eq(changes["Node3D"], 1,
		"exact native Node3D count observes a newly created real game node")
	t.eq(changes["MeshInstance3D"], 1,
		"mesh population census observes a newly created renderer node")
	t.eq(second["has_previous"], true,
		"second manual census measures growth against the prior sample")
	t.check(int(second["delta"]) >= 2,
		"the total population also sees both new objects")
	t.check(Profiler.format_report(second).contains("+1"),
		"the HUD/log report makes class growth visible in the field")

	temporary_mesh.free()
	temporary_node.free()
	var after: Dictionary = profiler.sample()
	var released: Dictionary = after["changes"]
	t.eq(released["Node3D"], -1,
		"freed Node3D is not accidentally kept alive by the profiler")
	t.eq(released["MeshInstance3D"], -1,
		"freed renderer object is not retained in the native census")
	t.check(int(after["delta"]) <= -2,
		"overall object population shrinks when visuals are released")
	profiler.reset_baseline()
	t.eq(profiler.sample()["has_previous"], false,
		"explicit baseline reset starts a fresh independent comparison")
