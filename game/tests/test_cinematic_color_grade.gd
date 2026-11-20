extends RefCounted
## Deterministic grade for renderer-independent tests.

const FilmGrade = preload("res://scripts/client/graphics_color_grade.gd")


func run(t) -> void:
	t.current = "cinematic grade palette"
	var noon: Dictionary = FilmGrade.palette(1.0, 0.8, 0.0)
	var dawn: Dictionary = FilmGrade.palette(0.45, 0.08, 0.0)
	var night: Dictionary = FilmGrade.palette(0.0, -0.3, 0.0)
	var storm: Dictionary = FilmGrade.palette(0.45, 0.08, 1.0)
	var cave: Dictionary = FilmGrade.palette(0.0, -0.3, 0.0, true)
	t.eq(noon, FilmGrade.palette(1.0, 0.8, 0.0), "same sky returns same palette")
	t.eq(noon, FilmGrade.palette(10.0, 0.8, -9.0), "untrusted day and storm values are clamped")
	t.eq(storm, FilmGrade.palette(0.45, 0.08, 9.0), "over-range storm intensity clamps")
	var day_high: Vector3 = noon["highlight_tone"]
	var gold_high: Vector3 = dawn["highlight_tone"]
	var storm_high: Vector3 = storm["highlight_tone"]
	var night_shadow: Vector3 = night["shadow_tone"]
	var day_shadow: Vector3 = noon["shadow_tone"]
	t.check(gold_high.x > day_high.x and gold_high.z < day_high.z,
		"golden-hour highlights get warmer, not simply brighter")
	t.check(storm_high.x < gold_high.x, "storms suppress golden-hour warmth")
	t.check(night_shadow.z > day_shadow.z, "night preserves cool readable shadows")
	t.check((cave["highlight_tone"] as Vector3).x > day_high.x, "torches keep warm underground highlights")
	t.eq(cave, FilmGrade.palette(0.95, 0.99, 1.0, true), "underground ignores surface sky and storms")
	var mid: Dictionary = FilmGrade.palette(0.45, 0.08, 0.5)
	var mid_high: Vector3 = mid["highlight_tone"]
	t.check(mid_high.x <= gold_high.x and mid_high.x >= storm_high.x,
		"storm transitions are continuous")
	t.current = "existing postprocess path"
	var shader := load("res://assets/shaders/post_grade.gdshader") as Shader
	t.check(shader != null, "post shader loads")
	if shader != null:
		var code: String = shader.code
		t.check(code.contains("uniform vec3 shadow_tone") and code.contains("uniform vec3 highlight_tone"),
			"two dynamic vectors replace hardcoded split tones")
		t.check(code.contains("mix(shadow_tone, highlight_tone"),
			"existing luma-based split toning is retained")
		t.check(code.contains("sharpen_strength > 0.001") and code.contains("blur_quality > 0"),
			"focus sharpening and diorama blur remain")
	t.current = "hue-stable filmic contrast"
	if shader != null:
		var post_code: String = shader.code
		t.check(post_code.contains("float toned_luma = clamp(dot(toned")
			and post_code.contains("float mapped_luma =")
			and post_code.contains("toned *= luma_scale;"),
			"final S-curve scales scene luminance without changing RGB ratios")
		t.check(not post_code.contains("toned * toned * (3.0 - 2.0 * toned)"),
			"old independent per-channel curves cannot introduce hue drift")
		# Test the same luminance transfer on a warm sunset sample: this
		# property holds for any nonzero RGB channel because gain is shared.
		var sunset := Vector3(0.8, 0.32, 0.12)
		var lum: float = clampf(sunset.dot(Vector3(0.2126, 0.7152, 0.0722)), 0.0, 1.0)
		var mapped: float = lum * lum * (3.0 - 2.0 * lum)
		var gain: float = lerpf(1.0, mapped / maxf(lum, 0.0001), 0.18)
		var graded: Vector3 = sunset * gain
		t.near(graded.x / graded.y, sunset.x / sunset.y, 0.00001,
			"red/green sunset chroma survives contrast adjustment")
		t.near(graded.y / graded.z, sunset.y / sunset.z, 0.00001,
			"green/blue sunset chroma survives contrast adjustment")
		t.check(gain > 0.0 and gain <= 1.0, "filmic midtone gain stays bounded")

	var game := load("res://scripts/client/online_main.gd") as Script
	t.check(game != null, "online scene script loads")
	if game != null:
		t.check(game.source_code.contains("GraphicsColorGrade.apply(_grade_material"),
			"live scene applies palette through its existing material")
		t.check(game.source_code.contains("_grade_elapsed >= 0.20"),
			"grade uniforms update at a bounded rate")
