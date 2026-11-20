extends RefCounted
## Biome-aware instanced ambient particles; deterministic positions and GPU
## limits are testable without requiring external textures or network clients.

const AmbientMotes = preload("res://scripts/client/ambient_motes.gd")
const OnlineClient = preload("res://scripts/client/online_main.gd")
const SoloClient = preload("res://scripts/client/client_main.gd")


func run(t) -> void:
	t.current = "all ambient VFX profiles are finite and GPU-bounded"
	var previous: int = -1
	for quality in 4:
		var profile: Dictionary = AmbientMotes.profile(quality)
		var per_tile: int = int(profile["per_tile"])
		t.check(per_tile > previous, "higher quality increases the visible density")
		t.check(per_tile <= AmbientMotes.MAX_PER_TILE,
			"no preset allocates more than the persistent per-tile capacity")
		t.check(float(profile["radius"]) <= 64.0,
			"GPU fragment work is capped at the artistic visibility radius")
		previous = per_tile
	t.eq(AmbientMotes.profile(-10), AmbientMotes.profile(0),
		"invalid lower quality clamps to Performance")
	t.eq(AmbientMotes.profile(100), AmbientMotes.profile(3),
		"invalid higher quality clamps to Ultra")
	var bad: Dictionary = AmbientMotes.profile(2)
	bad["per_tile"] = -10
	t.check(int(AmbientMotes.profile(2)["per_tile"]) > 0,
		"callers cannot mutate global quality budgets")

	t.current = "forest and swamp glow at night, dust catches daytime light"
	var forest: Dictionary = AmbientMotes.visibility("forest", 0.0, 0.0, 2)
	var swamp: Dictionary = AmbientMotes.visibility("swamp", 0.0, 0.0, 2)
	t.check(float(forest["fireflies"]) > 0.5,
		"forest nights contain subtle golden fireflies")
	t.check(float(swamp["fireflies"]) > float(forest["fireflies"]),
		"swamp contains stronger night firefly glow")
	t.eq(float(forest["pollen"]), 0.0,
		"unlit pollen does not produce ghostly night specks")
	var forest_day: Dictionary = AmbientMotes.visibility("forest", 1.0, 0.0, 2)
	t.eq(float(forest_day["fireflies"]), 0.0,
		"fireflies disappear gracefully in strong sunlight")
	t.check(float(forest_day["pollen"]) > 0.0,
		"forest sunlight catches fine drifting pollen")
	t.check(float(AmbientMotes.visibility("plains", 1.0, 0.0, 2)["pollen"]) >
		float(forest_day["pollen"]),
		"dry meadow skies have brighter dust than woodland")
	t.check(float(AmbientMotes.visibility("plains", 0.0, 0.0, 2)["fireflies"]) == 0.0,
		"plains do not invent woodland fireflies")
	t.eq(float(AmbientMotes.visibility("", 0.0, 0.0, 2)["fireflies"]), 0.0,
		"underground uses an empty biome and creates no night particles")
	var storm: Dictionary = AmbientMotes.visibility("forest", 1.0, 1.0, 2)
	t.check(float(storm["pollen"]) < float(forest_day["pollen"]) * 0.1,
		"heavy rain suppresses floating dust instead of increasing overdraw")
	t.check(float(AmbientMotes.visibility("swamp", 0.0, 1.0, 2)["fireflies"]) <
		float(swamp["fireflies"]) * 0.1,
		"storm suppresses night fireflies")
	var disabled: Dictionary = AmbientMotes.visibility("swamp", 0.0, 0.0, 0)
	t.eq(disabled["count"], 0, "Performance disables the VFX draw entirely")
	t.eq(disabled["radius"], 0.0, "Performance has no hidden particle range")
	for quality in 4:
		var state: Dictionary = AmbientMotes.visibility("forest", 0.0, 0.0, quality)
		t.eq(int(state["count"]),
			int(AmbientMotes.profile(quality)["per_tile"]) * AmbientMotes.CELL_COUNT,
			"visible instances are kept in the budget, never a resource reallocation")
		t.check(int(state["count"]) <= AmbientMotes.MAX_INSTANCES,
			"all rendering presets fit the one allocated MultiMesh")

	t.current = "world tiles stay stable across negative coordinates and moves"
	t.eq(AmbientMotes.grid_cell(Vector3(0.0, 0.0, 0.0)), Vector2i.ZERO,
		"world origin starts in cell zero")
	t.eq(AmbientMotes.grid_cell(Vector3(-0.1, 50.0, -42.01)),
		Vector2i(-1, -2), "negative world coordinates use floor not truncation")
	t.eq(AmbientMotes.grid_cell(Vector3(42.01, 0.0, 84.01)),
		Vector2i(1, 2), "tile snapping is deterministic")
	t.eq(AmbientMotes.tile_seed(Vector2i(3, -7)),
		AmbientMotes.tile_seed(Vector2i(3, -7)),
		"same world cell reproduces exactly the same pattern")
	t.check(AmbientMotes.tile_seed(Vector2i(3, -7)) !=
		AmbientMotes.tile_seed(Vector2i(3, -6)),
		"neighbouring tiles do not share one identical pattern")

	t.current = "real GPU instancing avoids per-particle scene objects"
	var field := AmbientMotes.new()
	field.setup(null)
	field._ready()
	t.check(field._batch != null, "one persistent MultiMesh created")
	t.eq(field._batch.instance_count, AmbientMotes.MAX_INSTANCES,
		"all quality levels reuse one resident GPU buffer")
	t.eq(field.get_child_count(), 1,
		"particles occupy exactly one rendering node, not hundreds of nodes")
	t.check(field._batch.use_custom_data,
		"seed, phase, size and brightness ride in per-instance custom data")
	t.check(field._batch.mesh is QuadMesh,
		"camera-facing motes require only two triangles each")
	t.eq(field._batch.visible_instance_count, 0,
		"nothing draws before the first camera context arrives")
	field.update_view(Vector3(2, 0, 2), "swamp", 0.0, 0.0,
		Vector2.ZERO, 1, 0.25)
	t.check(field._renderer.visible, "night swamp enables the GPU billboard batch")
	t.eq(field._batch.visible_instance_count, 72,
		"Balanced draws eight motes across each of the nine world cells")
	t.eq(field._generated_tiles, 9, "first image builds nine stable tile groups")
	var anchor: Transform3D = field._batch.get_instance_transform(0)
	t.eq(field._batch.get_instance_custom_data(0).r, 1.0,
		"each grid begins with a guaranteed firefly")
	field.update_view(Vector3(7, 0, 3), "swamp", 0.0, 0.0,
		Vector2.ZERO, 1, 0.25)
	t.eq(field._generated_tiles, 9, "standing within a world tile has no CPU rebuild")
	t.eq(field._batch.get_instance_transform(0), anchor,
		"unchanged world cell retains exact particle placements")
	field.update_view(Vector3(45, 0, 3), "swamp", 0.0, 0.0,
		Vector2.ZERO, 3, 0.25)
	t.eq(field._generated_tiles, 12,
		"crossing one tile samples only the three previously unseen world tiles")
	t.eq(field._batch.instance_count, AmbientMotes.MAX_INSTANCES,
		"Ultra never resizes or restarts the GPU mesh")
	t.eq(field._batch.visible_instance_count, -1,
		"Ultra uses native show-all mode for all 252 preallocated instances")
	field.update_view(Vector3(2, 0, 2), "swamp", 0.0, 0.0,
		Vector2.ZERO, 3, 0.25)
	t.eq(field._batch.get_instance_transform(0), anchor,
		"returning to an old location reproduces identical positions")
	t.eq(field._generated_tiles, 12,
		"backtracking to cached tiles requires no new heightmap queries")
	t.check(field._tile_cache.size() <= AmbientMotes.TILE_CACHE_LIMIT,
		"CPU cache remains bounded while preserving recent tiles")
	field.update_view(Vector3(2, 0, 2), "swamp", 0.0, 0.0,
		Vector2.ZERO, 1, 0.25)
	t.eq(field._batch.visible_instance_count, 72,
		"downgrading Ultra hides distant GPU instances")
	field.update_view(Vector3(2, 0, 2), "swamp", 0.0, 0.0,
		Vector2.ZERO, 3, 0.25)
	t.eq(field._batch.visible_instance_count, -1,
		"restoring Ultra reveals even instances updated while hidden")
	field.update_view(Vector3(2, 0, 2), "plains", 0.0, 0.0,
		Vector2.ZERO, 3, 0.25)
	t.check(not field._renderer.visible,
		"nighttime open plains cull the whole draw when neither effect contributes")
	t.eq(field._batch.visible_instance_count, 0,
		"disabled visual state incurs zero visible GPU particles")
	field.free()

	t.current = "shader and both clients are wired to the same GPU field"
	var code: String = FileAccess.get_file_as_string(
		"res://assets/shaders/ambient_motes.gdshader")
	t.check(code.contains("INSTANCE_CUSTOM") and code.contains("skip_vertex_transform"),
		"shader animates per-instance motes and billboards in the vertex stage")
	t.check(code.contains("fade_distance") and code.contains("ambient_wind"),
		"shader fades smoothly by distance and responds to real weather")
	t.check(not code.contains("texture(") and not code.contains("hint_depth_texture"),
		"mote shader does not increase fullscreen/depth texture bandwidth")
	var online: String = (OnlineClient as Script).source_code
	t.check(online.contains("_ambient_motes.setup(client.world)") and
		online.contains("_ambient_motes.update_view(here,"),
		"multiplayer streams particles from world height and actual weather")
	t.check(online.contains('"" if underground else _visual_biome'),
		"underground gameplay suppresses surface fireflies and pollen")
	var solo: String = (SoloClient as Script).source_code
	t.check(solo.contains("_ambient_motes.setup(world)") and
		solo.contains("_ambient_motes.update_view(survivor.position"),
		"solo mode shares the same GPU motes and deterministic world seeds")
