extends RefCounted
## Look values are deterministic, safe for all renderers, and alter no gameplay.
const Grade = preload("res://scripts/client/cinematic_color_grade.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")


func run(t) -> void:
	t.current = "ACES scene-referred cinematic grading"
	var midday: Dictionary = Grade.look(1.0, 0.9, 0.0)
	var sunrise: Dictionary = Grade.look(0.5, 0.12, 0.0)
	var moonlight: Dictionary = Grade.look(0.0, -0.9, 0.0)
	var storm: Dictionary = Grade.look(1.0, 0.9, 1.0)
	t.check(float(midday["saturation"]) > float(moonlight["saturation"]),
			"sunlit world is more colorful than a moonlit world")
	t.check(float(midday["contrast"]) > float(storm["contrast"]),
			"overcast lighting softens scene contrast")
	t.check(float(midday["saturation"]) > float(storm["saturation"]),
			"rain shifts the palette to natural desaturated colors")
	t.check(float(moonlight["exposure"]) > float(midday["exposure"]),
			"moonlight avoids crushed shadows")
	t.check(float(sunrise["glow_intensity"]) > float(midday["glow_intensity"]),
			"golden hour has slightly more pronounced highlights")
	t.eq(Grade.look(-100.0, -1.0, 0.0), Grade.look(0.0, -1.0, 0.0),
			"negative daylight inputs are clamped")
	t.eq(Grade.look(2.0, 1.0, 200.0), Grade.look(1.0, 1.0, 1.0),
			"overbright daylight and weather inputs are clamped")

	t.current = "native Godot Environment integration"
	var env := Environment.new()
	Grade.apply(env, 1.0, 0.9, 0.0)
	t.near(env.tonemap_exposure, float(midday["exposure"]), 0.0001,
			"the actual tonemap receives computed film exposure")
	t.near(env.adjustment_contrast, float(midday["contrast"]), 0.0001,
			"the actual native Environment gets cinematic contrast")
	t.near(env.adjustment_saturation, float(midday["saturation"]), 0.0001,
			"native ACES grading receives saturation")
	t.near(env.glow_intensity, float(midday["glow_intensity"]), 0.0001,
			"existing bloom intensity is adjusted without enabling an expensive pass")
	Grade.apply(env, 1.0, 0.9, 1.0)
	t.near(env.adjustment_saturation, float(storm["saturation"]), 0.0001,
			"weather switches color grading directly on the live environment")
	Grade.apply(null, 1.0, 0.9, 1.0)
	t.check((Atmosphere as Script).source_code.contains(
			"CinematicColorGrade.apply(environment, daylight, sun_height, storm)"),
			"the shared online and local atmosphere uses the grade each update")
