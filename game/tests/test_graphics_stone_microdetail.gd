extends RefCounted
## Shared native PBR detail normal assets without per-chunk shader copies.
const Stone = preload("res://scripts/client/graphics_stone_microdetail.gd")
const MeshPBR = preload("res://scripts/client/mesh_pbr_preservation.gd")
const Catalog = preload("res://scripts/client/model_catalog.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	Stone.clear_cache()
	t.current = "masonry-only eligibility"
	for name in ["dungeon/wall_broken.gltf", "dungeon/pillar_decorated.gltf",
			"dungeon/rubble_large.gltf", "dungeon/column.gltf",
			"dungeon/stairs_wide.gltf"]:
		t.check(Stone.is_masonry_path(name), "ruined stone mesh receives detail")
	for name in ["dungeon/bed_decorated.gltf", "dungeon/barrel_small.gltf",
			"dungeon/torch_lit.gltf", "village/EA03_Fence_Wall_01b.glb",
			"dungeon/chest_gold.gltf", "dungeon/table_medium.gltf"]:
		t.check(not Stone.is_masonry_path(name), "nonstone geometry stays untouched")
	t.eq(Stone.tier_for(0, "forward_plus"), 0,
		"Performance does not sample stone detail")
	t.eq(Stone.tier_for(1, "forward_plus"), 0,
		"Balanced remains on imported base textures only")
	t.eq(Stone.tier_for(3, "gl_compatibility"), 0,
		"Compatibility skips additional PBR sampling")
	t.eq(Stone.tier_for(3, "mobile"), 0,
		"Mobile skips additional PBR sampling")
	t.eq(Stone.tier_for(2, "forward_plus"), 2,
		"High activates shared native detail normals")
	t.eq(Stone.tier_for(3, "forward_plus"), 3,
		"Ultra activates stronger stone microstructure")

	t.current = "seamless and safe tangent-space normal"
	for u in [0.0, 0.14, 0.55, 0.99]:
		for v in [0.0, 0.37, 0.75, 1.0]:
			t.near(Stone.height_at(Vector2(u, v)),
				Stone.height_at(Vector2(u + 1.0, v)), 0.0001,
				"integer-frequency image wraps horizontally")
			t.near(Stone.height_at(Vector2(u, v)),
				Stone.height_at(Vector2(u, v + 1.0)), 0.0001,
				"detail texture wraps vertically")
	var high: Vector3 = Stone.normal_at(Vector2(0.23, 0.64), Stone.HIGH_AMOUNT)
	var ultra: Vector3 = Stone.normal_at(Vector2(0.23, 0.64), Stone.ULTRA_AMOUNT)
	t.near(high.length(), 1.0, 0.00001, "high normal remains unit length")
	t.near(ultra.length(), 1.0, 0.00001, "ultra normal remains unit length")
	t.check(Vector2(ultra.x, ultra.y).length() >
		Vector2(high.x, high.y).length(),
		"Ultra exaggerates only shallow stone relief, not mesh geometry")

	t.current = "PBR surfaces preserve imported texture maps and quality"
	var original := StandardMaterial3D.new()
	original.albedo_color = Color(0.63, 0.45, 0.28)
	original.metallic = 0.07
	original.roughness = 0.72
	original.normal_enabled = true
	var authored_normal := ImageTexture.new()
	original.normal_texture = authored_normal
	Stone.configure(3, "forward_plus")
	var baked: BaseMaterial3D = MeshPBR.material_for_bake(
		original, true, true, true)
	t.check(baked != original, "new world material is independent of pack art")
	t.check(baked.detail_enabled, "Ultra stone enables native dual-normal shading")
	t.check(baked.detail_normal != null, "stone receives extra PBR micro normal")
	t.check(baked.normal_texture == authored_normal,
		"authored normals are not replaced with new texture")
	t.check(original.detail_normal == null and not original.detail_enabled,
		"imported source materials remain completely unchanged")
	t.check(baked.albedo_texture == original.albedo_texture,
		"existing albedo maps remain untouched")
	t.near(baked.metallic, original.metallic, 0.00001,
		"microdetail cannot change metalness")
	t.near(baked.roughness, 1.0, 0.00001,
		"hand-painted dungeon roughness is still respected")
	var ultra_texture: Texture2D = baked.detail_normal
	t.eq(ultra_texture.get_width(), Stone.IMAGE_SIZE,
		"shared texture uses a bounded 128 texel resolution")
	t.eq(ultra_texture.get_height(), Stone.IMAGE_SIZE,
		"shared texture is square with mipmaps")
	var another: BaseMaterial3D = MeshPBR.material_for_bake(
		original, true, true, true)
	t.check(another.detail_normal == ultra_texture,
		"all baked stone surfaces share the same texture")
	Stone.configure(2, "forward_plus")
	t.check(baked.detail_enabled and another.detail_enabled,
		"quality changes update already-instanced scene materials")
	t.check(baked.detail_normal == another.detail_normal,
		"High automatically shares one cached native PBR texture")
	t.check(baked.detail_normal != ultra_texture,
		"High reduces strength instead of retaining expensive Ultra layer")
	Stone.configure(1, "forward_plus")
	t.check(not baked.detail_enabled and baked.detail_normal == null,
		"Balanced fully disables shader detail and releases its material slot")
	t.check(not another.detail_enabled, "all streamed objects downgrade together")
	Stone.configure(3, "forward_plus")
	t.check(baked.detail_normal == ultra_texture,
		"returning to Ultra reuses the texture instead of regenerating it")
	var no_tangents: BaseMaterial3D = MeshPBR.material_for_bake(
		original, false, true, true)
	t.check(not no_tangents.detail_enabled and no_tangents.detail_normal == null,
		"missing tangents never enable a broken normal map")
	var artist_detail := StandardMaterial3D.new()
	artist_detail.detail_enabled = true
	var artist_bake: BaseMaterial3D = MeshPBR.material_for_bake(
		artist_detail, true, true, true)
	t.check(artist_bake.detail_enabled and artist_bake.detail_normal == null,
		"existing authored detail maps always take precedence")
	var cutout := StandardMaterial3D.new()
	cutout.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var transparent_bake: BaseMaterial3D = MeshPBR.material_for_bake(
		cutout, true, true, true)
	t.check(not transparent_bake.detail_enabled,
		"cutout surfaces do not sample added stone detail")
	Stone.configure(3, "mobile")
	t.check(not baked.detail_enabled and not another.detail_enabled,
		"backend fallback cleans previous Forward+ materials")
	Stone.clear_cache()

	t.current = "render subsystem and actual model catalog integration"
	var catalog: String = (Catalog as Script).source_code
	var model: String = (MeshPBR as Script).source_code
	var quality: String = (Quality as Script).source_code
	t.check(catalog.contains("StoneMicrodetail.is_masonry_path(path)"),
		"catalog filters only installed dungeon masonry models")
	t.check(model.contains("StoneMicrodetail.register(result, tangent_frame_valid)"),
		"baked copied PBR is registered once without altering imported art")
	t.check(quality.contains("StoneMicrodetail.configure(_level, str(method))"),
		"graphics quality changes apply to all cached and streamed structures")
