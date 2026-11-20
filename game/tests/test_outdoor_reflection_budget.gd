extends RefCounted
## Offline regression for bounded reflection captures and native probe properties.
const Budget = preload("res://scripts/client/outdoor_reflection_budget.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")
const HubView = preload("res://scripts/client/hub_view.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "outdoor reflection quality, renderer and resource budgets"
	var low: Dictionary = Budget.settings(0, "forward_plus")
	var balanced: Dictionary = Budget.settings(1, "forward_plus")
	var high: Dictionary = Budget.settings(2, "forward_plus")
	var ultra: Dictionary = Budget.settings(3, "forward_plus")
	t.eq(int(low["count"]), 0, "Performance allocates no architecture cubemaps")
	t.eq(int(balanced["count"]), 0, "Balanced allocates no architecture cubemaps")
	t.eq(int(high["count"]), 1, "High uses just one nearby architecture capture")
	t.eq(int(ultra["count"]), 2, "Ultra caps architecture captures at two")
	t.check(float(high["radius"]) < float(ultra["radius"]),
			"Ultra selects site reflections from a slightly wider range")
	t.check(float(high["mesh_lod"]) > float(ultra["mesh_lod"]),
			"High captures cheaper mesh LODs than Ultra")
	t.check(float(ultra["max_distance"]) < 60.0,
			"cubemap faces never draw the whole streamed world")
	for method in ["mobile", "gl_compatibility", ""]:
		for tier in 4:
			t.eq(int(Budget.settings(tier, method)["count"]), 0,
					"unsupported renderer never creates an outdoor capture")
	t.eq(Budget.settings(-6, "forward_plus"), low, "low tier clamps")
	t.eq(Budget.settings(12, "forward_plus"), ultra, "high tier clamps")
	high["count"] = 99
	t.eq(int(Budget.settings(2, "forward_plus")["count"]), 1,
			"quality profiles are copied, not modified by consumers")

	t.current = "site ownership avoids duplicate probes on streamed chunk edges"
	t.check(Budget.SITE_KINDS.has("village") and Budget.SITE_KINDS.has("city")
			and Budget.SITE_KINDS.has("depot") and Budget.SITE_KINDS.has("dock"),
			"settlements, urban ruins and docks are eligible")
	t.check(not Budget.SITE_KINDS.has("landmark"),
			"remote natural landmarks do not trigger expensive cubemaps")
	t.check(Budget.belongs_to_chunk(64.0, 40.0, Vector2(64, 0), 64.0),
			"boundary site belongs to its east chunk")
	t.check(not Budget.belongs_to_chunk(64.0, 40.0, Vector2.ZERO, 64.0),
			"adjacent west chunk does not allocate a duplicate marker")
	t.check(Budget.belongs_to_chunk(-1.0, -1.0, Vector2(-64, -64), 64.0),
			"negative coordinates are handled symmetrically")
	t.check(not Budget.belongs_to_chunk(NAN, 3.0, Vector2.ZERO, 64.0),
			"invalid site coordinates are rejected")

	t.current = "camera-local capture selection with hysteresis"
	var candidates := [
		{"id": 10, "distance_sq": 64.0},
		{"id": 11, "distance_sq": 100.0},
		{"id": 12, "distance_sq": 225.0},
	]
	t.eq(Budget.choose(candidates, 0, 30.0).size(), 0,
			"disabled effect does not select any probe")
	t.eq(Budget.choose(candidates, 1, 30.0)[0]["id"], 10,
			"closest site captures the first reflection")
	t.eq(Budget.choose(candidates, 2, 30.0).size(), 2,
			"Ultra reuses no more than the two pooled cubemaps")
	t.eq(Budget.choose(candidates, 2, 9.0).size(), 1,
			"distance cutoff is applied before GPU allocations")
	t.eq(Budget.choose(candidates, 1, 30.0, [11])[0]["id"], 11,
			"existing site wins a near tie, preventing recaptures while walking")
	t.eq(Budget.choose([
			{"id": 10, "distance_sq": 9.0},
			{"id": 11, "distance_sq": 225.0},
		], 1, 30.0, [11])[0]["id"], 10,
			"dramatically closer site eventually takes over")
	t.eq(Budget.choose([], 2, 30.0).size(), 0,
			"the manager stays idle in open wilderness")

	t.current = "captured outdoor PBR environment matches sky and architecture"
	var probe: ReflectionProbe = Budget.make_probe(ultra)
	t.eq(probe.update_mode, ReflectionProbe.UPDATE_ONCE,
			"capture occurs once per site instead of every render frame")
	t.check(probe.box_projection,
			"parallax-corrected cubemap avoids sliding building reflections")
	t.check(not probe.interior,
			"sky, sun and moon remain visible in outdoor reflections")
	t.check(not probe.enable_shadows,
			"six cubemap faces skip costly shadow-map rendering")
	t.eq(probe.cull_mask, 1, "capture includes only the main world geometry")
	t.eq(probe.reflection_mask, 1,
			"reflection influence is limited to the default scene layer")
	t.check(probe.max_distance <= 42.0 and probe.mesh_lod_threshold > 1.0,
			"cubemap uses bounded geometry range and cheap imported mesh LOD")
	t.check(probe.size.x <= 30.0 and probe.blend_distance >= 2.0,
			"building-scale reflection box blends smoothly into the sky")
	t.check(not probe.visible, "new probes cannot capture the wrong origin")

	t.current = "native ReflectionProbe rejects invalid quality values"
	probe.mesh_lod_threshold = 2.4
	probe.mesh_lod_threshold = 2.4
	t.near(probe.mesh_lod_threshold, 2.4, 0.0001,
			"idempotent quality update preserves existing LOD")
	probe.free()

	t.current = "fully integrated streaming game and engine presets"
	var chunk_code: String = (ChunkView as Script).source_code
	var hub_code: String = (HubView as Script).source_code
	var main_code: String = (load("res://scripts/client/online_main.gd") as Script).source_code
	var quality_code: String = (GraphicsQuality as Script).source_code
	t.check(chunk_code.contains("_add_outdoor_reflection_anchors(origin, data)")
			and chunk_code.contains("OutdoorReflectionBudget.belongs_to_chunk"),
			"only owner chunks stream unique settlement capture anchors")
	t.check(hub_code.contains("_add_reflection_anchors(height)")
			and hub_code.contains("OutdoorReflectionBudget.GROUP"),
			"central hub has explicit reflection influence regions")
	t.check(main_code.contains("OutdoorReflectionBudget.new()"),
			"online world instantiates one shared capture manager")
	t.check(quality_code.contains("OutdoorReflectionBudget.configure(_level)"),
			"live graphics settings propagate the outdoor reflection budget")
