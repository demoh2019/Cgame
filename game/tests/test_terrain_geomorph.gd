extends RefCounted
## Real game terrain uses native UV2 geomorph with shader instance uniform.
const ChunkView = preload("res://scripts/client/chunk_view.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")

func run(t) -> void:
	t.current = "renderer-specific terrain geomorph levels"
	for tier in 4:
		ChunkView.configure_terrain_geomorph(tier)
		t.eq(ChunkView.terrain_geomorph_enabled, tier >= 2,
			"geomorph enabled only for premium terrain tier")
	var node := ChunkedTerrain3D.new()
	ChunkView.configure_terrain_geomorph(2)
	ChunkView.apply_terrain_geomorph(node)
	t.check(node.lod_geomorph_enabled, "real native chunked mesh toggles geomorph")
	t.near(node.update_interval, 0.16, 0.001, "premium morph updates are smooth")
	ChunkView.configure_terrain_geomorph(0)
	ChunkView.apply_terrain_geomorph(node)
	t.check(not node.lod_geomorph_enabled, "performance disables additional UV2 stream")
	t.near(node.update_interval, 0.5, 0.001, "low preset avoids extra CPU refresh")
	node.free()
	t.current = "native mesh is used by both ground shader variants"
	var ground := load("res://assets/shaders/ground.gdshader") as Shader
	t.check(ground != null, "textured ground shader loads")
	if ground != null:
		t.check(ground.code.contains("instance uniform float aa_lod_morph"),
			"textured terrain has per-instance morph strength")
		t.check(ground.code.contains("mix(VERTEX.y, UV2.x, aa_lod_morph * UV2.y)"),
			"textured terrain morphs GPU vertex height")
	t.check(ChunkView.GROUND_SHADER.contains("mix(VERTEX.y, UV2.x, aa_lod_morph * UV2.y)"),
		"fallback painted material renders identical geometry")
	t.check((Quality as Script).source_code.contains("ChunkView.apply_terrain_geomorph"),
		"graphics settings reconfigure live chunks without a scene reload")


	t.current = "projected terrain shape-error controls per quality preset"
	var source: String = (ChunkView as Script).source_code
	t.check(source.contains("terrain.max_lod_pixel_error = terrain_max_lod_pixel_error"),
		"already-streamed terrain receives native error limit")
	t.check(source.contains("_terrain.max_lod_pixel_error = terrain_max_lod_pixel_error"),
		"newly streamed terrain receives native error limit")
	for tier in 4:
		ChunkView.configure_terrain_geomorph(tier)
		t.eq(ChunkView.terrain_max_lod_pixel_error,
			[0.0, 0.0, 3.0, 1.5][tier],
			"Performance/Balanced keep legacy LOD while High/Ultra protect rocky silhouettes")
	ChunkView.configure_terrain_geomorph(1)
