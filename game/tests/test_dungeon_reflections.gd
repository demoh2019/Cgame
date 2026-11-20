extends RefCounted
## One-shot box-projected interior reflections share a small camera-local pool.
## Pure scheduling tests also run without a graphics device.

const Budget = preload("res://scripts/client/dungeon_reflection_budget.gd")
const Dungeon = preload("res://scripts/shared/dungeon.gd")


func run(t) -> void:
	t.current = "dungeon reflection GPU budget"
	var low: Dictionary = Budget.settings(0, "forward_plus")
	var balanced: Dictionary = Budget.settings(1, "forward_plus")
	var high: Dictionary = Budget.settings(2, "forward_plus")
	var ultra: Dictionary = Budget.settings(3, "forward_plus")
	t.eq(int(low["count"]), 0, "Performance creates no reflection captures")
	t.eq(int(balanced["count"]), 0, "Balanced creates no reflection captures")
	t.eq(int(high["count"]), 1, "High allocates at most one local probe")
	t.eq(int(ultra["count"]), 2, "Ultra allocates at most two local probes")
	t.check(float(high["radius"]) < float(ultra["radius"]),
		"High keeps a smaller capture selection range")
	for method in ["gl_compatibility", "mobile"]:
		t.eq(int(Budget.settings(3, method)["count"]), 0,
			"unsupported renderer never allocates interior cubemaps")
	t.eq(Budget.settings(-100, "forward_plus"), low, "negative graphics tier clamps")
	t.eq(Budget.settings(99, "forward_plus"), ultra, "high graphics tier clamps")
	high["count"] = 500
	t.eq(int(Budget.settings(2, "forward_plus")["count"]), 1,
		"callers cannot mutate stored probe budgets")

	t.current = "stable room choice and capture limits"
	var rooms := [
		{"id": 11, "distance_sq": 49.0},
		{"id": 12, "distance_sq": 64.0},
		{"id": 13, "distance_sq": 144.0},
	]
	t.eq(Budget.choose(rooms, 0, 16.0).size(), 0, "zero budget selects no rooms")
	t.eq(Budget.choose(rooms, 3, 0.0).size(), 0, "zero radius selects no rooms")
	t.eq(Budget.choose(rooms, 1, 16.0)[0]["id"], 11, "nearest room wins without history")
	t.eq(Budget.choose(rooms, 2, 16.0).size(), 2, "Ultra never selects more than pool size")
	t.eq(Budget.choose(rooms, 1, 8.0).size(), 1, "selection respects capture radius")
	t.eq(Budget.choose(rooms, 2, 7.5).size(), 1, "distant rooms stay unselected")
	var near_tie := [
		{"id": 101, "distance_sq": 49.0},
		{"id": 102, "distance_sq": 36.0},
	]
	t.eq(Budget.choose(near_tie, 1, 16.0, [101])[0]["id"], 101,
		"three metre hysteresis prevents re-capture for a one metre move")
	var clear_switch := [
		{"id": 101, "distance_sq": 169.0},
		{"id": 102, "distance_sq": 16.0},
	]
	t.eq(Budget.choose(clear_switch, 1, 16.0, [101])[0]["id"], 102,
		"moving into a new room eventually switches the capture")
	t.eq(Budget.choose([], 2, 16.0, [101]).size(), 0,
		"no markers (outdoors) means no active probes")

	t.current = "actual Godot ReflectionProbe properties"
	var probe: ReflectionProbe = Budget.make_probe(ultra)
	t.eq(probe.update_mode, ReflectionProbe.UPDATE_ONCE,
		"local environment capture is never refreshed every frame")
	t.check(probe.box_projection, "room reflections receive rectangular parallax correction")
	t.check(probe.interior, "dungeon probes do not reflect a daylight sky")
	t.check(not probe.enable_shadows, "each cubemap face omits expensive shadow maps")
	t.eq(probe.cull_mask, 1, "cubemap capture uses only default geometry layer")
	t.eq(probe.reflection_mask, 1, "room material reflections stay on default layer")
	t.near(probe.size.x, Dungeon.ROOM + 0.8, 0.001,
		"reflection bounds match actual twelve-metre dungeon rooms")
	t.check(probe.max_distance <= 20.0, "room captures exclude distant open-world meshes")
	t.check(probe.mesh_lod_threshold > 1.0, "reflection capture uses cheaper imported LODs")
	probe.free()

	t.current = "runtime scene integration"
	var main_script := load("res://scripts/client/online_main.gd") as Script
	var chunk_script := load("res://scripts/client/chunk_view.gd") as Script
	var quality_script := load("res://scripts/client/graphics_quality.gd") as Script
	t.check(main_script != null and chunk_script != null and quality_script != null,
		"gameplay scripts load with pooled dungeon reflections")
	if main_script != null:
		t.check(main_script.source_code.contains("DungeonReflectionBudget.new()"),
			"world instantiates exactly one shared manager")
	if chunk_script != null:
		t.check(chunk_script.source_code.contains("room_anchor.add_to_group(DungeonReflectionBudget.GROUP)"),
			"rooms contribute markers instead of eager cubemaps")
	if quality_script != null:
		t.check(quality_script.source_code.contains("DungeonReflectionBudget.configure(_level)"),
			"manual and automatic graphics tiers both control probe allocation")
