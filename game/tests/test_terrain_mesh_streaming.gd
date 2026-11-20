extends RefCounted
## Native main-thread terrain mesh streaming is time sliced like modern level
## streaming systems. Tests are GPU-free and preserve gameplay collision.
const ChunkView = preload("res://scripts/client/chunk_view.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "quality-specific terrain mesh streaming budgets"
	var previous_usec := 0
	for tier in 4:
		var profile: Dictionary = GraphicsQuality.profile(tier)
		var microseconds: int = int(profile.get("terrain_mesh_build_budget_usec", -1))
		t.check(microseconds > previous_usec and microseconds <= 20000,
			"higher quality grants a larger CPU geometry streaming time slice")
		previous_usec = microseconds

	t.current = "engine streaming API and defaults"
	var terrain := ChunkedTerrain3D.new()
	t.eq(terrain.mesh_build_budget_usec, 0,
		"stock behavior on the customized engine remains eager by default")
	t.eq(terrain.get_pending_mesh_build_count(), 0,
		"new unloaded terrain starts with no pending LOD meshes")
	terrain.mesh_build_budget_usec = -15
	t.eq(terrain.mesh_build_budget_usec, 0,
		"negative streaming budgets clamp to the legacy eager mode")
	terrain.mesh_build_budget_usec = 30000
	t.eq(terrain.mesh_build_budget_usec, 20000,
		"native streaming time slice is capped to a safe 20 ms")

	t.current = "game streaming and runtime profile changes"
	terrain.add_to_group(ChunkView.TERRAIN_LOD_GROUP)
	ChunkView.configure_terrain_mesh_budget(1700)
	ChunkView.apply_terrain_mesh_budget(terrain)
	t.eq(terrain.mesh_build_budget_usec, 1700,
		"live terrain receives shared geometry budget without rebuilding")
	ChunkView.configure_terrain_mesh_budget(0)
	ChunkView.apply_terrain_mesh_budget(terrain)
	t.eq(terrain.mesh_build_budget_usec, 0,
		"streaming can be disabled without destroying terrain")
	var chunk_code: String = (ChunkView as Script).source_code
	t.check(chunk_code.contains("_terrain.mesh_build_budget_usec = terrain_mesh_build_budget_usec"),
		"new world chunks configure streaming before entering the scene")
	t.check(chunk_code.contains("static func apply_terrain_mesh_budget(node: Node)"),
		"all scene terrain variants share the same native streaming policy")
	var quality_code: String = (GraphicsQuality as Script).source_code
	t.check(quality_code.contains("ChunkView.configure_terrain_mesh_budget("),
		"quality changes update terrain streaming time budgets")
	t.check(quality_code.contains("ChunkView.apply_terrain_mesh_budget(lod_terrain)"),
		"already-loaded terrain is retuned without a scene reload")
	t.check(chunk_code.contains("_terrain.collision_enabled = false"),
		"native visual streaming keeps authoritative world collision untouched")
	terrain.free()
	ChunkView.configure_terrain_mesh_budget(
		int(GraphicsQuality.profile(1)["terrain_mesh_build_budget_usec"]))
