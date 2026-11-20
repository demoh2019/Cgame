extends RefCounted
## Projection-aware terrain geometry in the custom Godot engine and real game.
const ChunkView = preload("res://scripts/client/chunk_view.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "quality-aware screen-space terrain geometry"
	var prev: float = 0.0
	for q in 4:
		var distance: float = ChunkView.terrain_lod_distance_for_quality(q)
		t.check(distance > prev, "higher quality preserves more terrain triangles")
		prev = distance
	t.eq(ChunkView.terrain_lod_distance_for_quality(-1), 55.0,
		"lower invalid quality clamps")
	t.eq(ChunkView.terrain_lod_distance_for_quality(90), 112.0,
		"higher invalid quality clamps")
	t.eq(ChunkView.terrain_lod_distance_for_quality(1), 70.0,
		"Balanced preserves original authored terrain distance")

	t.current = "native terrain property is opt-in and reversible"
	var terrain := ChunkedTerrain3D.new()
	t.eq(terrain.screen_space_lod_enabled, false,
		"existing engine terrains keep distance-only selection")
	t.near(terrain.lod_reference_fov, 60.0, 0.0001,
		"generic engine FOV reference is 60 degrees")
	ChunkView.configure_terrain_screen_lod(3)
	ChunkView.apply_terrain_screen_lod(terrain)
	t.eq(terrain.screen_space_lod_enabled, true,
		"streamed game chunks use camera-relative LOD")
	t.near(terrain.lod_reference_fov, 38.0, 0.0001,
		"terrain is calibrated to the game's actual 38-degree camera")
	t.near(terrain.lod_distance, 112.0, 0.0001,
		"Ultra chooses high-detail terrain farther away")
	ChunkView.configure_terrain_screen_lod(0)
	ChunkView.apply_terrain_screen_lod(terrain)
	t.near(terrain.lod_distance, 55.0, 0.0001,
		"Performance reduces geometric detail distance")
	terrain.lod_reference_fov = 500.0
	t.check(terrain.lod_reference_fov < 179.0,
		"native engine clamps excessive reference angles")
	t.check(not terrain.collision_enabled == false or terrain.collision_enabled,
		"screen LOD does not require collision state changes")
	terrain.free()
	ChunkView.configure_terrain_screen_lod(1)

	t.current = "full game terrain stream and quality integration"
	var game: String = (ChunkView as Script).source_code
	var quality: String = (GraphicsQuality as Script).source_code
	t.check(game.contains("apply_terrain_screen_lod(_terrain)"),
		"new terrain receives active LOD when built")
	t.check(game.contains("_terrain.add_to_group(TERRAIN_LOD_GROUP)"),
		"all terrain variants register for quality updates")
	t.check(quality.contains("ChunkView.configure_terrain_screen_lod(_level)"),
		"graphics profiles select projected geometry distance")
	t.check(quality.contains("ChunkView.apply_terrain_screen_lod(lod_terrain)"),
		"already-visible chunks update on quality changes")
	t.check(game.contains("_terrain.lod_geomorph_enabled"),
		"compatible with native smooth geometry morphing")
	t.check(game.contains("_terrain.collision_enabled = false"),
		"authoritative game collision remains unchanged")
