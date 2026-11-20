extends RefCounted
## Render-quality gated alpha coverage mips retain cutout leaf silhouettes.
const Foliage = preload("res://scripts/client/foliage.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "foliage alpha mip quality profile"
	for tier in 4:
		t.eq(Foliage.alpha_mipmaps_enabled(tier, "forward_plus"), tier >= 2,
			"only High and Ultra allocate the corrected foliage mip chain")
		t.check(not Foliage.alpha_mipmaps_enabled(tier, "mobile"),
			"Mobile stays on the original imported foliage texture")
		t.check(not Foliage.alpha_mipmaps_enabled(tier, "gl_compatibility"),
			"Compatibility stays on the original imported foliage texture")
	t.check((GraphicsQuality as Script).source_code.contains(
		"Foliage.configure_alpha_mipmaps(_level, str(method))"),
		"quality menu updates existing cached leaf material surfaces")

	t.current = "native image coverage independently preserves source pixels"
	var source := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			source.set_pixel(x, y, Color(0.3, 0.6, 0.2,
				1.0 if x % 4 == 0 else 0.0))
	var original: PackedByteArray = source.get_data()
	var image: Image
	if source.has_method("create_alpha_coverage_mipmaps"):
		image = source.call("create_alpha_coverage_mipmaps", 0.5) as Image
	else:
		image = source.duplicate()
		t.eq(image.generate_mipmaps(false, true, 0.5), OK,
			"regular Godot also supports alpha coverage mip generation")
	t.check(image != null, "filtered image exists")
	if image != null:
		t.check(image.has_mipmaps(), "premium alpha has a complete mip chain")
		t.check(source.get_data() == original and not source.has_mipmaps(),
			"prefilter does not modify original imported pixels")
		var plain: Image = source.duplicate()
		t.eq(plain.generate_mipmaps(), OK, "ordinary box-filter comparison exists")
		var off: int = image.get_mipmap_offset(1)
		t.check(image.get_data()[off + 3] >= plain.get_data()[off + 3],
			"thin leaf mask is not made worse by mip filtering")

	t.current = "live mesh leaves use one cached GPU texture"
	Foliage.configure_alpha_mipmaps(0, "forward_plus")
	var standard := StandardMaterial3D.new()
	standard.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	standard.albedo_texture = ImageTexture.create_from_image(source)
	var mesh := BoxMesh.new()
	mesh.material = standard
	var rendered: ArrayMesh = Foliage.swayed(mesh, "tree:alpha_mip_test", 0.1) as ArrayMesh
	t.check(rendered != null, "foliage mesh converts to GPU-ready material")
	if rendered != null:
		var material: ShaderMaterial = rendered.surface_get_material(0) as ShaderMaterial
		t.check(material != null, "leaf material preserves original PBR surface")
		if material != null:
			var imported: Texture2D = standard.albedo_texture
			t.check(material.get_shader_parameter("albedo_tex") == imported,
				"Performance uses source texture and zero extra VRAM")
			Foliage.configure_alpha_mipmaps(3, "forward_plus")
			var optimized: Texture2D = material.get_shader_parameter("albedo_tex") as Texture2D
			t.check(optimized != null, "Ultra binds alpha-aware mipmapped texture")
			if optimized != null:
				t.check(optimized.get_image().has_mipmaps(),
					"actual bound texture carries generated coverage mipmaps")
			Foliage.configure_alpha_mipmaps(0, "forward_plus")
			t.check(material.get_shader_parameter("albedo_tex") == imported,
				"return to low graphics restores original source texture")
