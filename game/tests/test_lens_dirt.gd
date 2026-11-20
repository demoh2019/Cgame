extends RefCounted
## Lens dirt bloom mask.
const LensDirt = preload("res://scripts/client/lens_dirt.gd")


func run(t) -> void:
	t.current = "lens dirt on High/Ultra Forward+"
	t.eq(LensDirt.strength(1, "forward_plus"), 0.0, "Balanced has a clean lens")
	t.eq(LensDirt.strength(3, "gl_compatibility"), 0.0, "Compatibility skips it")
	t.check(LensDirt.strength(3, "forward_plus") > LensDirt.strength(2, "forward_plus"), "Ultra dirtier")
	var env := Environment.new()
	LensDirt.apply(env, 3, "forward_plus")
	t.check(env.glow_map != null and env.glow_map_strength > 0.0, "mask applied")
	LensDirt.apply(env, 0, "forward_plus")
	t.eq(env.glow_map_strength, 0.0, "and removed on Performance")
