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
