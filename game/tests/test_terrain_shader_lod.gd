extends RefCounted
## Terrain material complexity must scale with distance while remaining compatible with the game's renderer.

const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "terrain texture LOD profiles"
	t.check(ProjectSettings.has_setting("shader_globals/aa_terrain_detail_radius"), "detail radius GPU uniform is registered")
	var config: Dictionary = ProjectSettings.get_setting("shader_globals/aa_terrain_detail_radius", {})
	t.eq(str(config.get("type", "")), "float", "terrain LOD radius is a float")
	t.near(float(config.get("value", -1.0)), 42.0, 0.001, "initial terrain quality is balanced")
	var previous := 0.0
	for level in GraphicsQuality.NAMES.size():
		var p: Dictionary = GraphicsQuality.profile(level)
		var radius: float = float(p.get("terrain_detail_radius", -1.0))
		t.check(radius >= 20.0 and radius <= 120.0, "terrain LOD distance has sane bounds for %s" % GraphicsQuality.NAMES[level])
		t.check(radius > previous, "%s quality increases detail radius" % GraphicsQuality.NAMES[level])
		previous = radius

	t.current = "terrain shading cost"
	var shader := load("res://assets/shaders/ground.gdshader") as Shader
	t.check(shader != null, "textured terrain shader is loadable")
	if shader != null:
		var code: String = shader.code
		t.check(code.contains("global uniform float aa_terrain_detail_radius;"), "global radius is shared across all chunks")
		t.check(code.contains("smoothstep(aa_terrain_detail_radius"), "distance transition blends rather than popping")
		t.check(code.contains("CAMERA_POSITION_WORLD.xz"), "LOD follows the active camera")
		t.check(code.contains("if (near_weight > 0.001)"), "distant albedo does not fetch near detail")
		t.check(code.contains("if (detail_fade > 0.001)"), "distant normal maps are not sampled")
		t.check(code.contains("textureGrad(albedo_layers") and code.contains("textureGrad(normal_layers"), "conditional samples have stable explicit mip gradients")
		t.check(code.contains("dFdx(p / tile_meters)") and code.contains("dFdy(p / tile_meters)"), "mip gradients are evaluated before dynamic branches")
		t.check(code.contains("aa_weather_wetness"), "rain-wet materials remain supported")
		t.check(code.contains("site_patches"), "roads and city ground are still layered")

	var controller := load("res://scripts/client/graphics_quality.gd") as Script
	t.check(controller != null, "gameplay graphics controller is available")
	if controller != null:
		t.check(controller.source_code.contains('global_shader_parameter_set(&"aa_terrain_detail_radius"'), "graphics preset changes update the terrain GPU global")
