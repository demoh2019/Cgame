extends RefCounted
## Bounded sharpening in the existing post pass: no extra draw calls or GPU resources.

const Quality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "postprocess sharpening budgets"
	t.near(Quality.post_sharpen_strength(0, "gl_compatibility", false), 0.0, 0.0001, "Performance does not add post sampling")
	t.near(Quality.post_sharpen_strength(1, "gl_compatibility", false), 0.0, 0.0001, "Balanced does not add post sampling")
	t.check(Quality.post_sharpen_strength(2, "gl_compatibility", false) > 0.0, "High sharpens the central band")
	t.check(Quality.post_sharpen_strength(3, "gl_compatibility", false) > Quality.post_sharpen_strength(2, "gl_compatibility", false), "Ultra enhances detail further")
	t.near(Quality.post_sharpen_strength(3, "forward_plus", true), 0.0, 0.0001, "Adaptive FSR2 is never double-sharpened")
	t.near(Quality.post_sharpen_strength(2, "forward_plus", true), 0.0, 0.0001, "High auto FSR2 disables spatial sharpening")
	t.check(Quality.post_sharpen_strength(3, "forward_plus", false) > 0.0, "Manual native Forward+ Ultra retains sharpening")
	t.near(Quality.post_sharpen_strength(-8, "gl_compatibility", false), 0.0, 0.0001, "Level clamps low")
	t.near(Quality.post_sharpen_strength(999, "gl_compatibility", false), Quality.post_sharpen_strength(3, "gl_compatibility", false), 0.0001, "Level clamps high")
	t.current = "sharpen shader cost and stability"
	var shader := load("res://assets/shaders/post_grade.gdshader") as Shader
	t.check(shader != null, "postprocess shader loads")
	if shader != null:
		var src: String = shader.code
		t.check(src.contains("uniform float sharpen_strength"), "sharpen budget is a uniform")
		t.check(src.contains("sharpen_strength > 0.001 && sharp_focus > 0.001"), "zero-strength presets skip four texture taps")
		t.check(src.contains("SCREEN_PIXEL_SIZE"), "kernel stays pixel-sized at different resolutions")
		t.check(src.contains("max_neighbor") and src.contains("min_neighbor"), "local neighborhood bounds limit ringing")
		t.check(src.contains("1.0 - smoothstep(0.24, 0.70, local_contrast)"), "high-contrast edges receive less sharpening")
		t.check(src.contains("blur_quality > 0"), "existing variable-cost diorama blur remains")
	var controller: Script = load("res://scripts/client/graphics_quality.gd") as Script
	if controller != null:
		t.check(controller.source_code.contains('set_shader_parameter("sharpen_strength"'), "postprocess material receives quality-specific sharpen")
