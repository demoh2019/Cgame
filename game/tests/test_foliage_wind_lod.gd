extends RefCounted
## Foliage wind LOD and material regression. Requires no downloaded nature pack.

const Foliage = preload("res://scripts/client/foliage.gd")
const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


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

	t.current = "thin leaf transmission quality"
	t.check(ProjectSettings.has_setting("shader_globals/aa_leaf_transmission"), "Godot registers the shared leaf light global")
	t.check(shader.contains("global uniform float aa_leaf_transmission;"), "foliage shader receives leaf transmission strength")
	t.check(shader.contains("BACKLIGHT = vec3(0.0);"), "non-leaf materials start with zero backlighting")
	t.check(shader.contains("if (cut_out && aa_leaf_transmission > 0.001)"), "only transparent leaf material computes transmission")
	t.check(shader.contains("float leaf_mask = smoothstep("), "thick dark veins stay less translucent")
	t.check(shader.contains("BACKLIGHT = t.rgb * instance_tint * hue"), "transmitted light retains original source colors and per-instance tint")
	t.check(shader.contains("ALPHA_SCISSOR_THRESHOLD = scissor"), "leaf alpha cutout remains intact")
	var prior_strength := -1.0
	for level in VisualProfiles.PRESETS.size():
		var settings: Dictionary = VisualProfiles.settings(level)
		var strength: float = float(settings.get("leaf_transmission", -1.0))
		t.check(strength >= 0.0 and strength <= 0.7, "transmission is bounded on %s" % GraphicsQuality.NAMES[level])
		t.check(strength > prior_strength, "higher quality increases translucency on %s" % GraphicsQuality.NAMES[level])
		prior_strength = strength
	t.eq(float(VisualProfiles.settings(0)["leaf_transmission"]), 0.0, "Performance skips leaf backlight computation")
	var controller: GDScript = load("res://scripts/client/graphics_quality.gd") as GDScript
	t.check(controller != null and controller.source_code.contains('global_shader_parameter_set(&"aa_leaf_transmission"'),
		"graphics preset broadcasts shared leaf translucency to all foliage")

	t.current = "alpha-to-coverage leaf edges"
	t.check(Foliage.supports_alpha_coverage("forward_plus", Viewport.MSAA_2X), "Forward+ 2x MSAA supports leaf edge coverage")
	t.check(Foliage.supports_alpha_coverage("forward_plus", Viewport.MSAA_4X), "Forward+ 4x MSAA supports leaf edge coverage")
	t.check(Foliage.supports_alpha_coverage("mobile", Viewport.MSAA_2X), "Vulkan Mobile may use coverage when MSAA is active")
	t.check(not Foliage.supports_alpha_coverage("forward_plus", Viewport.MSAA_DISABLED), "FSR2 without MSAA stays on the cheaper cutout")
	t.check(not Foliage.supports_alpha_coverage("gl_compatibility", Viewport.MSAA_4X), "OpenGL Compatibility never attempts coverage")
	var cut_source := BoxMesh.new()
	var source_material := StandardMaterial3D.new()
	source_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	source_material.alpha_scissor_threshold = 0.46
	source_material.albedo_color = Color(0.31, 0.44, 0.21)
	cut_source.material = source_material
	Foliage.configure_antialiasing(true)
	var cut_mesh := Foliage.swayed(cut_source, "regression_foliage_msaa_edges", 0.15) as ArrayMesh
	t.check(cut_mesh != null, "cutout foliage mesh can be generated with coverage")
	if cut_mesh != null:
		var mat := cut_mesh.surface_get_material(0) as ShaderMaterial
		t.check(mat != null, "cutout material is still a shader material")
		if mat != null:
			var coverage_shader := mat.shader
			t.check(coverage_shader.code.contains("alpha_to_coverage;"), "MSAA shader requests alpha to coverage")
			t.check(coverage_shader.code.contains("ALPHA_ANTIALIASING_EDGE = 0.3;"), "MSAA edge threshold is specified")
			t.check(coverage_shader.code.contains("ALPHA_TEXTURE_COORDINATE = UV;"), "alpha coverage receives source texture UVs")
			t.near(float(mat.get_shader_parameter("scissor")), 0.46, 0.0001, "cutout threshold is retained")
			Foliage.configure_antialiasing(false)
			t.check(mat.shader != coverage_shader, "turning off MSAA restores original cutout variant")
			t.eq(mat.get_shader_parameter("albedo_color"), source_material.albedo_color, "switch retains original artist tint")
			t.eq(mat.get_shader_parameter("cut_out"), true, "switch does not disable alpha cutout")
			Foliage.configure_antialiasing(true)
			t.check(mat.shader == coverage_shader, "existing foliage material recovers coverage without rebuilding mesh")
			t.check(Foliage.swayed(cut_source, "regression_foliage_msaa_edges", 0.15) == cut_mesh, "mesh remains in the cache on quality switches")
	Foliage.configure_antialiasing(false)
	var quality_source: GDScript = load("res://scripts/client/graphics_quality.gd") as GDScript
	t.check(quality_source != null and quality_source.source_code.contains("Foliage.configure_antialiasing("),
		"graphics quality applies antialiasing after resolution/MSAA selection")

	t.current = "crown self-occlusion"
	t.check(ProjectSettings.has_setting("shader_globals/aa_canopy_occlusion"), "shared canopy AO global is registered")
	t.check(shader.contains("global uniform float aa_canopy_occlusion;"), "foliage shader reads shared occlusion strength")
	t.check(shader.contains("canopy_height = clamp((VERTEX.y - height_min)"), "crown depth uses source-mesh-relative height")
	t.check(shader.contains("float open_sky = smoothstep("), "crown shading fades smoothly toward the tip")
	t.check(shader.contains("if (cut_out && aa_canopy_occlusion > 0.001)"), "opaque bark does not spend GPU time on crown shading")
	t.check(shader.contains("occlusion = mix(1.0, orm.r, pbr_detail);"), "source PBR ORM occlusion still fades with distance")
	t.check(shader.contains("AO = clamp(occlusion * (1.0 - crown_shadow)"), "procedural occlusion multiplies rather than replaces imported AO")
	t.check(shader.contains("ALBEDO *= 1.0 - crown_shadow * 0.12;"), "Compatibility receives subtle crown-depth shading")
	var last_strength := 1.0
	for level in VisualProfiles.PRESETS.size():
		var strength: float = float(VisualProfiles.settings(level).get("canopy_occlusion", -1.0))
		t.check(strength >= 0.0 and strength <= 0.5, "canopy strength remains bounded for %s" % GraphicsQuality.NAMES[level])
		t.check(strength < last_strength, "shadow approximation decreases as native SSAO quality rises")
		last_strength = strength
	var aabb_mesh := BoxMesh.new()
	aabb_mesh.size = Vector3(1.0, 5.0, 1.0)
	aabb_mesh.material = StandardMaterial3D.new()
	var transformed := Foliage.swayed(aabb_mesh, "regression_canopy_bounds", 0.1) as ArrayMesh
	t.check(transformed != null, "mesh can be shaded with height-relative AO")
	if transformed != null:
		var material := transformed.surface_get_material(0) as ShaderMaterial
		t.check(material != null, "source still has its PBR shader")
		if material != null:
			t.near(float(material.get_shader_parameter("height_min")), -2.5, 0.0001, "AABB base is passed to shader")
			t.near(float(material.get_shader_parameter("height_ref")), 5.0, 0.0001, "AABB vertical size is passed to shader")
	var control_script: GDScript = load("res://scripts/client/graphics_quality.gd") as GDScript
	t.check(control_script != null and control_script.source_code.contains('global_shader_parameter_set(&"aa_canopy_occlusion"'),
		"quality switch propagates new canopy ambient lighting")
