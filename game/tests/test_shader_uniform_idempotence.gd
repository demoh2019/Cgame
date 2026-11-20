extends RefCounted
## Repeated scalar/vector shader parameters and lifecycle compatibility.
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "native ShaderMaterial uniform value stability"
	var shader := Shader.new()
	shader.code = "shader_type spatial; uniform float intensity = 0.0; uniform vec3 wind = vec3(0.0); uniform vec4 tint = vec4(1.0);"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("intensity", 0.6)
	for i in 200:
		mat.set_shader_parameter("intensity", 0.6)
	t.near(float(mat.get_shader_parameter("intensity")), 0.6, 0.000001,
		"repeated equivalent uniforms keep precise float value")
	mat.set_shader_parameter("intensity", 0.9)
	t.near(float(mat.get_shader_parameter("intensity")), 0.9, 0.000001,
		"real float change still propagates to material")
	var wind := Vector3(0.3, -0.1, 0.6)
	for i in 128:
		mat.set_shader_parameter("wind", wind)
	t.eq(mat.get_shader_parameter("wind"), wind,
		"repeated identical Vector3 parameters preserve the cache")
	mat.set_shader_parameter("wind", Vector3.ZERO)
	t.eq(mat.get_shader_parameter("wind"), Vector3.ZERO,
		"new Vector3 propagates normally")
	mat.set_shader_parameter("tint", Vector4(0.25, 0.9, 0.5, 1.0))
	t.eq(mat.get_shader_parameter("tint"), Vector4(0.25, 0.9, 0.5, 1.0),
		"Vector4 render uniform retains full color values")
	mat.set_shader_parameter("tint", null)
	t.eq(mat.get_shader_parameter("tint"), null,
		"clearing a uniform removes its cached override")

	t.current = "texture resources remain unmodified and rebindable"
	var tex_shader := Shader.new()
	tex_shader.code = "shader_type spatial; uniform sampler2D albedo_tex;"
	var textured := ShaderMaterial.new()
	textured.shader = tex_shader
	var pixel := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	pixel.fill(Color(0.15, 0.75, 0.3))
	var texture := ImageTexture.create_from_image(pixel)
	textured.set_shader_parameter("albedo_tex", texture)
	for i in 8:
		textured.set_shader_parameter("albedo_tex", texture)
	t.eq(textured.get_shader_parameter("albedo_tex"), texture,
		"texture reference remains intact under repeated assignments")
	pixel.fill(Color(0.9, 0.1, 0.2))
	texture.update(pixel)
	textured.set_shader_parameter("albedo_tex", texture)
	t.eq(textured.get_shader_parameter("albedo_tex"), texture,
		"rebound texture resource remains valid after its pixels change")
	textured.set_shader_parameter("albedo_tex", null)
	t.eq(textured.get_shader_parameter("albedo_tex"), null,
		"resource removal still clears the stored sampler")

	t.current = "actual 3D atmosphere uses shared ShaderMaterial setters"
	var world: String = (Atmosphere as Script).source_code
	t.check(world.contains('set_shader_parameter("sky_time"'),
		"periodic sky weather updates use the optimized native setter")
	t.check(world.contains('set_shader_parameter("sun_color"'),
		"full RGB daylight updates continue through real material path")
	var q: String = (Quality as Script).source_code
	t.check(q.contains('post_material.set_shader_parameter("blur_quality"'),
		"post processing profile benefits from duplicate-value fast path")
