extends RefCounted
## Cached error-driven terrain geometry selection in the engine + Albion After.

const ChunkView = preload("res://scripts/client/chunk_view.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "quality-based terrain geometric error budget"
	var previous: float = -1.0
	for level in 4:
		var weight: float = ChunkView.terrain_error_strength_for_quality(level)
		t.check(weight >= 0.0 and weight <= 1.0,
			"terrain error sensitivity is bounded")
		t.check(weight > previous,
			"higher quality protects more complicated surface silhouettes")
		previous = weight
	t.near(ChunkView.terrain_error_strength_for_quality(0), 0.0, 0.0001,
		"Performance preserves original LOD with no error sampling")
	t.near(ChunkView.terrain_error_strength_for_quality(3), 1.0, 0.0001,
		"Ultra enables full ridge protection")
	t.near(ChunkView.terrain_error_strength_for_quality(-10), 0.0, 0.0001,
		"invalid low level clamps")
	t.near(ChunkView.terrain_error_strength_for_quality(100), 1.0, 0.0001,
		"invalid high level clamps")

	t.current = "native terrain integration"
	var terrain := ChunkedTerrain3D.new()
	t.near(terrain.lod_geometric_error_strength, 0.0, 0.0001,
		"engine default is opt-in and backwards compatible")
	ChunkView.configure_terrain_error_lod(3)
	ChunkView.apply_terrain_error_lod(terrain)
	t.near(terrain.lod_geometric_error_strength, 1.0, 0.0001,
		"Ultra enables geometric-error selection")
	ChunkView.configure_terrain_error_lod(1)
	ChunkView.apply_terrain_error_lod(terrain)
	t.near(terrain.lod_geometric_error_strength, 0.25, 0.0001,
		"Balanced uses a limited error-bias budget")
	ChunkView.configure_terrain_error_lod(0)
	ChunkView.apply_terrain_error_lod(terrain)
	t.near(terrain.lod_geometric_error_strength, 0.0, 0.0001,
		"returning to Performance disables error-aware LOD")
	t.eq(terrain.collision_enabled, true,
		"geometry LOD never modifies existing collision properties")
	terrain.free()
	ChunkView.configure_terrain_error_lod(1)

	t.current = "streaming, projection LOD and geomorph coexist"
	var chunk_source: String = (ChunkView as Script).source_code
	var quality_source: String = (Quality as Script).source_code
	t.check(chunk_source.contains("apply_terrain_error_lod(_terrain)"),
		"new streamed chunks inherit the error profile")
	t.check(chunk_source.contains("apply_terrain_screen_lod(_terrain)"),
		"existing screen-relative LOD remains enabled")
	t.check(chunk_source.contains("_terrain.lod_geomorph_enabled"),
		"existing terrain geometry transition remains enabled")
	t.check(chunk_source.contains("_terrain.set_color_data(TerrainCurvature.build("),
		"per-vertex curvature material shading is preserved")
	t.check(quality_source.contains("ChunkView.configure_terrain_error_lod(_level)"),
		"graphics presets broadcast an error budget")
	t.check(quality_source.contains("ChunkView.apply_terrain_error_lod(lod_terrain)"),
		"already-streamed terrain changes quality in place")
	t.check(chunk_source.contains("_terrain.collision_enabled = false"),
		"the server remains the authority on player collision")
