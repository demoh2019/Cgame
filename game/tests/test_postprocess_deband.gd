extends RefCounted
## Texture-free final color debanding on High/Ultra; one existing composite.

const Quality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "staged GPU deband budgets"
	var prev := -1.0
	for tier in 4:
		var value: float = float(Quality.profile(tier).get("deband_strength", -1.0))
		t.check(is_finite(value) and value >= 0.0 and value <= 1.0,
			"GPU dither never exceeds one final-display color step")
		t.check(value >= prev, "higher tier never reduces debanding")
		prev = value
	t.eq(Quality.profile(0)["deband_strength"], 0.0,
		"Performance skips all dither math")
	t.eq(Quality.profile(1)["deband_strength"], 0.0,
		"Balanced skips all dither math")
	t.check(float(Quality.profile(2)["deband_strength"]) > 0.0,
		"High enables subtle gradient debanding")
	t.eq(Quality.profile(3)["deband_strength"], 1.0,
		"Ultra enables exact one-display-step dithering")
	t.eq(Quality.profile(-100)["deband_strength"], 0.0,
		"invalid lower quality remains low")
	t.eq(Quality.profile(999)["deband_strength"], 1.0,
		"invalid upper quality clamps to Ultra")

	t.current = "interleaved gradient noise lives after the existing color grade"
	var shader := load("res://assets/shaders/post_grade.gdshader") as Shader
	t.check(shader != null, "actual existing filmic post shader loads")
	if shader == null:
		return
	var code: String = shader.code
	t.check(code.contains("uniform float deband_strength = 0.0"),
		"legacy post materials default to no added grain")
	t.check(code.contains("deband_strength > 0.001"),
		"low-end presets skip the noise path")
	t.check(code.contains("floor(FRAGCOORD.xy)"),
		"stable display pixel coordinates avoid camera-swimming noise")
	t.check(code.contains("52.9829189") and code.contains("0.06711056"),
		"Jimenez interleaved-gradient sequence uses no noise texture")
	t.check(code.contains("fwidth(luma)") and code.contains("flatness"),
		"flat gradients receive dithering while strong silhouettes are protected")
	t.check(code.contains("/ 255.0"),
		"grain remains below the output quantization step")
	t.check(code.contains("COLOR = vec4(color, 1.0)"),
		"existing final post composite remains intact")
	t.check(code.find("float jitter =") > code.find("color *= 1.0 - edge * vignette"),
		"debanding is applied after the vignette and color grade")
	t.check(not code.contains("noise_tex") and not code.contains("dither_tex"),
		"no additional noise image needs VRAM or texture sampling")
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("deband_strength", Quality.profile(2)["deband_strength"])
	t.near(float(material.get_shader_parameter("deband_strength")), 0.8, 0.0001,
		"shader material receives the actual High preset value")
	var quality_source: String = (Quality as Script).source_code
	t.check(quality_source.contains(
		'set_shader_parameter("deband_strength", float(p["deband_strength"]))'),
		"runtime selection and Auto quality drive the live post material")
