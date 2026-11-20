extends RefCounted
## Normal-map mip coherence reduces subpixel specular aliasing on PBR ground.
const Quality = preload("res://scripts/client/graphics_quality.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")


func run(t) -> void:
	t.current = "normal variance detail presets"
	var last := -1.0
	for tier in 4:
		var val: float = float(Quality.profile(tier)["normal_variance_strength"])
		t.check(is_finite(val) and val >= 0.0 and val <= 1.0,
			"all graphics tiers use bounded normal variance")
		t.check(val >= last, "normal variance budget grows with quality")
		last = val
	t.eq(float(Quality.profile(0)["normal_variance_strength"]), 0.0,
		"Performance avoids variance filtering")
	t.eq(float(Quality.profile(1)["normal_variance_strength"]), 0.0,
		"Balanced preserves existing normal maps")
	t.check(float(Quality.profile(3)["normal_variance_strength"]) >
			float(Quality.profile(2)["normal_variance_strength"]),
		"Ultra minimizes unresolved fine-normal highlights")
	var global_def: Dictionary = ProjectSettings.get_setting(
		"shader_globals/aa_terrain_normal_variance_strength", {})
	t.eq(str(global_def.get("type", "")), "float",
		"GPU normal coherence uniform is registered before shaders load")
	t.eq(float(global_def.get("value", -1.0)), 0.0,
		"project startup keeps the low-cost legacy path")
	t.check((Quality as Script).source_code.contains(
		'global_shader_parameter_set(&"aa_terrain_normal_variance_strength"'),
		"graphics preset pushes one global setting to streamed terrain")
	t.current = "premium PBR normal coherence and water exclusions"
	var ground := load("res://assets/shaders/ground.gdshader") as Shader
	t.check(ground != null, "PBR terrain shader loads")
	if ground != null:
		var source: String = ground.code
		t.check(source.contains("vec4 top_normal("),
			"one existing normal lookup includes coherence alpha")
		t.check(source.contains("normal_sample.a * w[i]"),
			"texture layer weights preserve normal coherence")
		t.check(source.contains("cliff_coherence"),
			"triplanar rock normals use their own mip-level variance")
		t.check(source.contains("variance = min((1.0 - coherence) / coherence, 0.14)"),
			"subpixel normal variance has strict glossy cap")
		t.check(source.contains("puddle < 0.85") and
			source.contains("* (1.0 - puddle)"),
			"wet puddles keep narrow physically reflective highlights")
		t.check(source.contains("filter_specular_roughness(final_roughness, bent)"),
			"existing geometric specular AA remains active")
	t.check((ChunkView as Script).source_code.contains(
		'ClassDB.class_exists("NormalVarianceMipmaps")'),
		"ordinary Godot falls back to legacy RGB8 normal-map mipmaps")
	t.check((ChunkView as Script).source_code.contains(
		'prefilter.call("build_image", normal_image)'),
		"native engine builds the real normal texture arrays only once")
	if ClassDB.class_exists("NormalVarianceMipmaps"):
		var generator: Object = ClassDB.instantiate("NormalVarianceMipmaps")
		var src := Image.create(4, 4, false, Image.FORMAT_RGB8)
		for z in 4:
			for x in 4:
				src.set_pixel(x, z, Color(1.0, 0.5, 0.5) if x % 2 == 0
					else Color(0.0, 0.5, 0.5))
		var result: Image = generator.call("build_image", src) as Image
		t.check(result != null, "native prefilter returns an image")
		if result != null:
			t.eq(result.get_format(), Image.FORMAT_RGBA8,
				"coherence is stored in the alpha channel")
			t.check(result.has_mipmaps(), "full prefiltered mip chain exists")
			var bytes: PackedByteArray = result.get_data()
			var offset: int = result.get_mipmap_offset(1)
			t.check(bytes[offset + 3] < 64,
				"opposing detail normals cancel to low coherence at mip 1")
