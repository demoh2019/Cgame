extends RefCounted
## Native lens effects budget. No GPU required: Environment stores the values headless.

const GraphicsLens = preload("res://scripts/client/graphics_lens.gd")


func run(t) -> void:
	t.current = "native lens effects"
	for tier in 2:
		var low: Dictionary = GraphicsLens.settings(tier, "forward_plus")
		t.eq(float(low["chromatic_aberration"]), 0.0, "tier %d skips chromatic aberration" % tier)
		t.eq(float(low["film_grain"]), 0.0, "tier %d skips film grain" % tier)
		t.eq(float(low["lens_flare"]), 0.0, "tier %d skips lens flare" % tier)
	for method in ["gl_compatibility", "mobile"]:
		var other: Dictionary = GraphicsLens.settings(3, method)
		t.eq(float(other["film_grain"]), 0.0, "%s has no native lens pass" % method)
	var high: Dictionary = GraphicsLens.settings(2, "forward_plus")
	var ultra: Dictionary = GraphicsLens.settings(3, "forward_plus")
	t.check(float(high["chromatic_aberration"]) > 0.0 and float(high["film_grain"]) > 0.0, "High enables lens finish")
	t.check(float(ultra["chromatic_aberration"]) >= float(high["chromatic_aberration"]), "Ultra fringes at least as much as High")
	t.check(float(ultra["chromatic_aberration"]) <= 0.6 and float(ultra["film_grain"]) <= 0.3, "lens effects stay subtle")
	var env := Environment.new()
	t.check("lens_film_grain" in env, "engine exposes Environment.lens_film_grain")
	GraphicsLens.apply(env, 3, "forward_plus")
	t.near(float(env.get("lens_chromatic_aberration")), float(ultra["chromatic_aberration"]), 0.001, "Ultra applies chromatic aberration")
	t.near(float(env.get("lens_film_grain")), float(ultra["film_grain"]), 0.001, "Ultra applies film grain")
	t.near(float(env.get("lens_flare")), float(ultra["lens_flare"]), 0.001, "Ultra applies lens flare")
	t.check(float(ultra["lens_flare"]) <= 1.0, "lens flare stays subtle")
	GraphicsLens.apply(env, 0, "forward_plus")
	t.eq(float(env.get("lens_film_grain")), 0.0, "Performance turns grain back off")
	env.set("lens_film_grain", 5.0)
	t.eq(float(env.get("lens_film_grain")), 1.0, "engine clamps film grain to 1")
