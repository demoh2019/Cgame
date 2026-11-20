extends RefCounted
## Graphics presets stay bounded and keep expensive effects off on low-end hardware.

const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")


func run(t) -> void:
	t.current = "graphics preset bounds"
	t.eq(GraphicsQuality.profile(-1), GraphicsQuality.profile(0), "below range clamps to Performance")
	t.eq(GraphicsQuality.profile(99), GraphicsQuality.profile(3), "above range clamps to Ultra")
	t.check(not GraphicsQuality.profile(0)["shadows"], "Performance omits shadow maps")
	t.eq(GraphicsQuality.profile(0)["anisotropy"], Viewport.ANISOTROPY_2X,
		"Performance uses affordable anisotropy")
	t.eq(GraphicsQuality.profile(1)["anisotropy"], Viewport.ANISOTROPY_4X,
		"Balanced keeps baseline 4x")
	t.eq(GraphicsQuality.profile(2)["anisotropy"], Viewport.ANISOTROPY_8X,
		"High improves ground angle sampling")
	t.eq(GraphicsQuality.profile(3)["anisotropy"], Viewport.ANISOTROPY_16X,
		"Ultra resolves oblique terrain texture detail")
	t.check(GraphicsQuality.profile(0)["blur_quality"] == 0, "Performance uses one screen sample")
	t.check(GraphicsQuality.profile(1)["blur_quality"] == 1, "Balanced uses five screen samples")
	t.check(GraphicsQuality.profile(2)["blur_quality"] == 2, "High retains the nine-sample diorama")
	t.check(GraphicsQuality.profile(3)["shadow_distance"] > GraphicsQuality.profile(1)["shadow_distance"], "Ultra draws distant shadows")
	t.check(GraphicsQuality.profile(3)["msaa"] != GraphicsQuality.profile(1)["msaa"], "Ultra enables MSAA")
	GraphicsQuality.set_level(99, false)
	t.eq(GraphicsQuality.level(), 3, "setting level is clamped")
	t.eq(GraphicsQuality.get_name(), "Ultra", "level has a display name")
	t.current = "scalable foliage and resolution"
	var low: Dictionary = GraphicsQuality.profile(0)
	var balanced: Dictionary = GraphicsQuality.profile(1)
	var high: Dictionary = GraphicsQuality.profile(2)
	var ultra: Dictionary = GraphicsQuality.profile(3)
	t.check(float(low["scale"]) < float(balanced["scale"]) and float(balanced["scale"]) < float(high["scale"]), "RD upscaler quality steps are ordered")
	t.check(float(low["grass_radius"]) < float(balanced["grass_radius"]) and float(balanced["grass_radius"]) < float(high["grass_radius"]) and float(high["grass_radius"]) < float(ultra["grass_radius"]), "grass distances increase with quality")
	t.check(int(low["grass_budget"]) < int(ultra["grass_budget"]), "grass generation is cheaper on Performance")
	t.check(not bool(low["ssil"]) and bool(ultra["ssil"]), "indirect light is exclusive to Ultra")
	GraphicsQuality.set_level(1, false)

	t.current = "fallback terrain shader quality"
	var fallback: String = ChunkView.GROUND_SHADER
	t.check(fallback.contains("aa_terrain_detail_radius"), "procedural terrain uses the same detail radius as textured terrain")
	t.check(fallback.contains("cloud_shadow(world_position.xz, TIME)"), "large-scale clouds are sampled in the vertex stage")
	t.check(fallback.contains("vertex_cloud_shade"), "cloud shading reaches fragment through a varying")
	t.check(fallback.contains("if (detail_fade > 0.001)"), "distant terrain skips unnecessary fine-noise work")
	t.check(fallback.contains("strata = mix(mid, fbm("), "near rock detail fades smoothly to macro layers")

	t.current = "terrain screen-space geometric error"
	var prior_error := 1e6
	for quality in GraphicsQuality.NAMES.size():
		var config: Dictionary = GraphicsQuality.profile(quality)
		var pixels: float = float(config.get("terrain_pixel_error", -1.0))
		t.check(pixels > 0.0 and pixels < prior_error,
			"higher graphics fidelity reduces terrain geometric error on %s" % GraphicsQuality.NAMES[quality])
		prior_error = pixels
	t.eq(ChunkView.TERRAIN_LOD_GROUP, "aa_terrain_pixel_lod",
		"the geometry LOD preset reaches all streamed terrain materials")
	var terrain := ChunkedTerrain3D.new()
	ChunkView.configure_terrain_pixel_error(2.25)
	terrain.add_to_group(ChunkView.TERRAIN_LOD_GROUP)
	ChunkView.apply_terrain_pixel_error(terrain)
	t.near(terrain.lod_pixel_error, 2.25, 0.0001,
		"native engine receives the active pixel-error threshold")
	terrain.free()
	var chunk_code: GDScript = load("res://scripts/client/chunk_view.gd") as GDScript
	t.check(chunk_code != null and chunk_code.source_code.contains(
		"_terrain.lod_pixel_error = terrain_lod_pixel_error"),
		"newly streamed chunks inherit pixel-error LOD without a separate rebuild")
	var quality_code: GDScript = load("res://scripts/client/graphics_quality.gd") as GDScript
	t.check(quality_code != null and quality_code.source_code.contains(
		"ChunkView.apply_terrain_pixel_error(terrain)"),
		"runtime preset switch updates already-streamed terrain chunks")
	ChunkView.configure_terrain_pixel_error(float(GraphicsQuality.profile(1)["terrain_pixel_error"]))
