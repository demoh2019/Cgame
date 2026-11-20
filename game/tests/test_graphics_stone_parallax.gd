extends RefCounted
## Native Godot POM stays Ultra-only with bounded layers and shared assets.
const Stone = preload("res://scripts/client/graphics_stone_microdetail.gd")
const MeshPBR = preload("res://scripts/client/mesh_pbr_preservation.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	Stone.clear_cache()
	t.current = "parallax budget, material selection and cheap renderer fallback"
	t.eq(Stone.PARALLAX_MIN_LAYERS, 4, "front-facing stone uses only four samples")
	t.eq(Stone.PARALLAX_MAX_LAYERS, 8, "oblique stone limits native POM to eight steps")
	t.check(Stone.PARALLAX_SCALE > 0.0 and Stone.PARALLAX_SCALE < 1.5,
		"parallax depth is shallow to prevent masonry silhouettes tearing")
	var original := StandardMaterial3D.new()
	original.albedo_color = Color(0.53, 0.5, 0.47)
	original.roughness = 0.72
	original.normal_enabled = true
	var original_normal := ImageTexture.new()
	original.normal_texture = original_normal

	for method in ["gl_compatibility", "mobile"]:
		Stone.configure(3, method)
		var fallback: BaseMaterial3D = MeshPBR.material_for_bake(
			original, true, true, true)
		t.check(not fallback.heightmap_enabled and fallback.heightmap_texture == null,
			"non-Forward+ backend does no extra POM sampling")
	for level in [0, 1, 2]:
		Stone.configure(level, "forward_plus")
		var cheap: BaseMaterial3D = MeshPBR.material_for_bake(
			original, true, true, true)
		t.check(not cheap.heightmap_enabled and cheap.heightmap_texture == null,
			"Performance/Balanced/High skip the native POM shader")
	t.current = "Ultra uses native deep parallax with shared normal and height fields"
	Stone.configure(3, "forward_plus")
	var first: BaseMaterial3D = MeshPBR.material_for_bake(
		original, true, true, true)
	var second: BaseMaterial3D = MeshPBR.material_for_bake(
		original, true, true, true)
	t.check(first.heightmap_enabled and first.heightmap_deep_parallax,
		"engine native POM is enabled on Ultra masonry")
	t.check(first.heightmap_texture != null,
		"Ultra lazily generates one procedural stone height texture")
	t.eq(first.heightmap_texture, second.heightmap_texture,
		"all ruins share one height image, no individual world uploads")
	t.eq(first.heightmap_min_layers, Stone.PARALLAX_MIN_LAYERS,
		"actual engine sample count minimum equals the strict budget")
	t.eq(first.heightmap_max_layers, Stone.PARALLAX_MAX_LAYERS,
		"actual engine sample count maximum equals the strict budget")
	t.near(first.heightmap_scale, Stone.PARALLAX_SCALE, 0.00001,
		"engine height offset remains less than one centimeter")
	t.eq(first.heightmap_texture.get_width(), Stone.IMAGE_SIZE,
		"height texture is at most 128 pixels across")
	t.eq(first.heightmap_texture.get_height(), Stone.IMAGE_SIZE,
		"height texture is at most 128 pixels tall")
	t.check(first.detail_enabled and first.detail_normal != null,
		"new POM builds on the existing normal-mapped masonry")
	t.check(first.normal_enabled and first.normal_texture == original_normal,
		"imported PBR tangent-space normal still reaches the renderer")
	t.near(first.roughness, 1.0, 0.00001,
		"authored hand-painted dungeon roughness remains preserved")
	t.check(not original.heightmap_enabled and original.heightmap_texture == null,
		"original imported art remains entirely untouched")
	t.current = "tileable normalized heightmap and live Auto material selection"
	var minimum := 1.0
	var maximum := 0.0
	for y in 11:
		for x in 13:
			var uv := Vector2(float(x) / 12.0, float(y) / 10.0)
			var height: float = Stone.parallax_height_at(uv)
			minimum = minf(minimum, height)
			maximum = maxf(maximum, height)
			t.near(height, Stone.parallax_height_at(uv + Vector2(1.0, 0.0)),
				0.0001, "height texels repeat seamlessly across the U border")
			t.near(height, Stone.parallax_height_at(uv + Vector2(0.0, 1.0)),
				0.0001, "height texels repeat seamlessly across the V border")
	t.check(minimum >= 0.0 and maximum <= 1.0 and maximum - minimum > 0.25,
		"height map has actual bounded stone displacement variation")
	var shared_height: Texture2D = first.heightmap_texture
	Stone.configure(2, "forward_plus")
	t.check(not first.heightmap_enabled and first.heightmap_texture == null and
		not second.heightmap_enabled, "High disables native POM on existing meshes")
	t.check(first.detail_enabled and first.detail_normal != null,
		"High retains the original less expensive detail normals")
	Stone.configure(3, "forward_plus")
	t.eq(first.heightmap_texture, shared_height,
		"Auto upscale reuses the same generated texture without recreation")
	Stone.configure(3, "mobile")
	t.check(not first.heightmap_enabled and not second.heightmap_enabled,
		"renderer fallback drops POM without replacing world geometry")

	t.current = "author-created UV and depth features are never overwritten"
	var authored := StandardMaterial3D.new()
	authored.heightmap_enabled = true
	var custom: BaseMaterial3D = MeshPBR.material_for_bake(
		authored, true, true, true)
	t.check(custom.heightmap_enabled and custom.heightmap_texture == null,
		"existing authored height-mapping feature retains original configuration")
	var triplanar := StandardMaterial3D.new()
	triplanar.uv1_triplanar = true
	var tri: BaseMaterial3D = MeshPBR.material_for_bake(
		triplanar, true, true, true)
	t.check(not tri.heightmap_enabled,
		"native triplanar material is excluded from incompatible height mapping")
	var no_tangents: BaseMaterial3D = MeshPBR.material_for_bake(
		original, false, true, true)
	t.check(not no_tangents.heightmap_enabled,
		"invalid mesh tangent frame never receives POM")
	Stone.clear_cache()

	t.current = "real engine and quality wiring"
	var code: String = (Stone as Script).source_code
	t.check(code.contains("material.heightmap_deep_parallax = true") and
		code.contains("material.heightmap_max_layers = PARALLAX_MAX_LAYERS"),
		"native Godot deep parallax is used, not a fake image-space effect")
	t.check((Quality as Script).source_code.contains(
		"StoneMicrodetail.configure(_level, str(method))"),
		"automatic and manual graphics quality both update stone shading")
