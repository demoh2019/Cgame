extends RefCounted
## Foliage wind LOD and material regression. Requires no downloaded nature pack.

const Foliage = preload("res://scripts/client/foliage.gd")


func run(t) -> void:
	t.current = "foliage vertex budget"
	var shader: String = Foliage.SHADER_CODE
	t.check(shader.contains("uniform float wind_fade_start = 48.0"), "near plants keep full wind animation")
	t.check(shader.contains("uniform float wind_fade_end = 120.0"), "far plants fade animation smoothly")
	t.check(shader.contains("wind_lod > 0.001"), "distant plants skip gust trigonometry")
	t.check(shader.contains("CAMERA_POSITION_WORLD.xz"), "LOD depends on camera rather than chunk boundaries")
	t.check(shader.contains("dot(root, vec2(0.23, 0.19))"), "wind phase is coherent per plant")
	t.check(shader.contains("float h2 = fract(h1"), "per-plant colours avoid a second sine hash")
	t.check(shader.contains("plant_roughness"), "plant highlights vary without more textures")
	t.check(shader.contains("cloud_xz = w.xz"), "cloud shadows still align in world space")

	t.current = "foliage mesh material setup"
	var source := BoxMesh.new()
	var original := StandardMaterial3D.new()
	original.albedo_color = Color(0.32, 0.5, 0.21)
	source.material = original
	var built := Foliage.swayed(source, "regression_foliage_wind_lod", 0.14, true)
	t.check(built is ArrayMesh, "foliage is converted to a cached mesh")
	if built is ArrayMesh:
		var material := built.surface_get_material(0) as ShaderMaterial
		t.check(material != null, "shader material stays attached")
		if material != null:
			t.near(float(material.get_shader_parameter("sway")), 0.14, 0.0001, "wind amplitude is preserved")
			t.eq(material.get_shader_parameter("instance_tinted"), true, "MultiMesh per-instance tint is preserved")
			t.eq(material.get_shader_parameter("albedo_color"), original.albedo_color, "artist colour is preserved")
	t.check(Foliage.swayed(source, "regression_foliage_wind_lod", 0.14, true) == built, "identical mesh setup is cached")

	t.current = "imported foliage PBR"
	t.eq(Foliage._channel_mask(BaseMaterial3D.TEXTURE_CHANNEL_BLUE), Vector4(0.0, 0.0, 1.0, 0.0), "blue roughness channel is preserved")
	t.eq(Foliage._channel_mask(BaseMaterial3D.TEXTURE_CHANNEL_ALPHA), Vector4(0.0, 0.0, 0.0, 1.0), "alpha metallic channel is preserved")
	t.eq(Foliage._channel_mask(BaseMaterial3D.TEXTURE_CHANNEL_GREEN), Vector4(0.0, 1.0, 0.0, 0.0), "green channel is preserved")
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.5, 0.65, 0.75, 1.0))
	var map_texture := ImageTexture.create_from_image(image)
	var authored := StandardMaterial3D.new()
	authored.roughness = 0.54
	authored.metallic = 0.22
	authored.metallic_specular = 0.41
	authored.roughness_texture = map_texture
	authored.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	authored.metallic_texture = map_texture
	authored.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_ALPHA
	authored.normal_enabled = true
	authored.normal_texture = map_texture
	authored.normal_scale = 0.7
	authored.vertex_color_use_as_albedo = true
	var pbr_mesh := BoxMesh.new()
	pbr_mesh.material = authored
	var copied := Foliage.swayed(pbr_mesh, "regression_foliage_pbr", 0.2) as ArrayMesh
	t.check(copied != null, "source PBR material can be converted into an animated mesh")
	if copied != null:
		var pbr := copied.surface_get_material(0) as ShaderMaterial
		t.check(pbr != null, "animated surface has a shader material")
		if pbr != null:
			t.near(float(pbr.get_shader_parameter("material_roughness")), authored.roughness, 0.0001, "artist roughness preserved")
			t.near(float(pbr.get_shader_parameter("material_metallic")), authored.metallic, 0.0001, "artist metalness preserved")
			t.near(float(pbr.get_shader_parameter("material_specular")), authored.metallic_specular, 0.0001, "artist specular preserved")
			t.eq(pbr.get_shader_parameter("use_roughness_map"), true, "authored roughness map enabled")
			t.eq(pbr.get_shader_parameter("roughness_mask"), Vector4(0.0, 0.0, 1.0, 0.0), "blue roughness channel transferred")
			t.eq(pbr.get_shader_parameter("use_metallic_map"), true, "authored metallic map enabled")
			t.eq(pbr.get_shader_parameter("metallic_mask"), Vector4(0.0, 0.0, 0.0, 1.0), "alpha metallic channel transferred")
			t.eq(pbr.get_shader_parameter("use_vertex_colors"), true, "authored vertex tint preserved")
			var source_tangents = pbr_mesh.surface_get_arrays(0)[Mesh.ARRAY_TANGENT]
			var source_normals = pbr_mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
			var has_tangents: bool = source_tangents != null and source_tangents.size() > 0 and source_normals != null and source_normals.size() > 0
			t.eq(pbr.get_shader_parameter("use_normal_map"), has_tangents, "tangent-free meshes skip normal mapping")
			if has_tangents:
				t.eq(pbr.get_shader_parameter("normal_tex"), map_texture, "authored tangent-space normals retained")
				t.near(float(pbr.get_shader_parameter("normal_strength")), authored.normal_scale, 0.0001, "normal scale retained")

	t.current = "packed ORM foliage"
	var orm := ORMMaterial3D.new()
	orm.roughness = 0.74
	orm.metallic = 0.1
	orm.orm_texture = map_texture
	var packed_mesh := BoxMesh.new()
	packed_mesh.material = orm
	var packed := Foliage.swayed(packed_mesh, "regression_foliage_orm", 0.08) as ArrayMesh
	t.check(packed != null, "ORM surface can be converted")
	if packed != null:
		var packed_material := packed.surface_get_material(0) as ShaderMaterial
		t.check(packed_material != null, "ORM material stays attached")
		if packed_material != null:
			t.eq(packed_material.get_shader_parameter("use_orm_map"), true, "packed occlusion/roughness/metalness sampled together")
			t.eq(packed_material.get_shader_parameter("orm_tex"), map_texture, "single packed ORM texture reused")
	t.check(Foliage.SHADER_CODE.contains("aa_terrain_detail_radius"), "normal map fade follows renderer quality preset")
	t.check(Foliage.SHADER_CODE.contains("textureGrad(normal_tex"), "optional normal map uses explicit mip gradients")
