extends RefCounted
## High fidelity lunar disc follows the moonlit directional-light vector.

func run(t) -> void:
	t.current = "day-night sky and cached radiance compatibility"
	var shader := load("res://assets/shaders/sky.gdshader") as Shader
	t.check(shader != null, "sky shader compiles and imports")
	if shader == null:
		return
	var code: String = shader.code
	t.check(code.contains("lunar_visibility") and code.contains("lunar_disc"),
		"night has a distinct lunar disc, not the daytime sun")
	t.check(code.contains("lunar_halo"), "moon has a broad low-cost atmospheric corona")
	t.check(code.contains("sun_direction"), "lunar and solar light reuse the cached direction")
	t.check(code.contains("use_cached_radiance && !AT_CUBEMAP_PASS"),
		"Performance sky remains cached and cannot sample itself")
	t.check(not code.contains("return;"), "Godot sky processor never returns early")
