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
		t.check(ground.code.contains("mix(VERTEX.y, UV2.x, morph)"),
			"textured terrain morphs GPU vertex height")
	t.check(ChunkView.GROUND_SHADER.contains("mix(VERTEX.y, UV2.x, morph)"),
		"fallback painted material renders identical geometry")
	t.check((Quality as Script).source_code.contains("ChunkView.apply_terrain_geomorph"),
		"graphics settings reconfigure live chunks without a scene reload")

	t.current = "morph interpolates coarse vertex normals"
	var fallback: String = ChunkView.GROUND_SHADER
	t.check(fallback.contains("NORMAL = normalize(mix(NORMAL, CUSTOM0.xyz, morph));"),
		"Compatibility material blends source and coarse normals alongside heights")
	t.check(fallback.contains("if (morph > 0.001)"),
		"low-end terrain skips morph-normal work")
	if ground != null:
		t.check(ground.code.contains("NORMAL = normalize(mix(NORMAL, CUSTOM0.xyz, morph));"),
			"PBR ground shares the same smooth lighting transition")
		t.check(ground.code.contains("VERTEX.y = mix(VERTEX.y, UV2.x, morph);"),
			"vertex height and normal use the same pixel-error geomorph weight")

