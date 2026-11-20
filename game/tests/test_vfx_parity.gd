extends RefCounted
## Combat/interaction VFX helpers (tracers, casings, materials, budgets, directions).

const CombatVfx = preload("res://scripts/client/combat_vfx.gd")


func run(t) -> void:
	t.current = "vfx budgets"
	for kind in ["tracer", "casing", "light", "trail", "burst", "ring", "sparkle"]:
		t.eq(CombatVfx.budget(kind, 0), 0, "%s off on Low" % kind)
		t.check(CombatVfx.budget(kind, 3) >= CombatVfx.budget(kind, 1), "%s grows with quality" % kind)
	t.eq(CombatVfx.budget("nope", 3), 0, "unknown kind")
	t.eq(CombatVfx.budget("light", 99), CombatVfx.budget("light", 3), "tier clamped high")

	t.current = "vfx directions"
	t.near(CombatVfx.dir_xz(Vector2(3, 4)).length(), 1.0, 0.001, "unit Vector2")
	t.eq(CombatVfx.dir_xz(Vector2.ZERO), Vector2.ZERO, "zero rejected")
	t.eq(CombatVfx.dir_xz(null), Vector2.ZERO, "null rejected")
	t.near(CombatVfx.dir_xz([0.0, 2.0]).y, 1.0, 0.001, "array form")
	t.near(CombatVfx.dir_xz({"x": 5.0, "z": 0.0}).x, 1.0, 0.001, "dict form")
	t.eq(CombatVfx.dir_xz(Vector2(INF, 0)), Vector2.ZERO, "non-finite rejected")
	var s := CombatVfx.spray_direction(Vector3.ZERO, Vector3(5, 0, 0))
	t.near(s.length(), 1.0, 0.001, "spray unit")
	t.check(s.x > 0.5 and s.y > 0.0, "spray away from attacker and upward")
	t.eq(CombatVfx.spray_direction(Vector3.ONE, Vector3.ONE), Vector3.UP, "coincident points spray up")

	t.current = "vfx tracer, casing, swing"
	var span := CombatVfx.tracer_span(Vector3.ZERO, Vector2(1, 0), 20.0)
	t.near(span[1].x, 20.0, 0.001, "tracer reaches range")
	t.near(span[0].x, 0.6, 0.001, "tracer starts ahead of muzzle")
	t.near(CombatVfx.tracer_span(Vector3.ZERO, Vector2(1, 0), 20.0, Vector3(7, 0, 0))[1].x, 7.0, 0.001, "tracer stops at target")
	var cv := CombatVfx.casing_velocity(Vector2(1, 0), 42)
	t.check(cv.y > 2.0, "casing flies upward")
	t.check(absf(cv.z) > 1.0, "casing ejects sideways")
	var arc := CombatVfx.swing_arc(Vector3.ZERO, Vector2(1, 0), 2.0, 0.9, 8)
	t.eq(arc.size(), 9, "arc samples")
	t.near(arc[4].x, 2.0, 0.001, "arc middle straight ahead")
	t.near(arc[0].length(), 2.0, 0.001, "arc at reach")

	t.current = "vfx materials"
	t.eq(CombatVfx.material_for("beach"), "sand", "beach sand")
	t.eq(CombatVfx.material_for("plains", "wood_log"), "wood", "wood item")
	t.eq(CombatVfx.material_for("plains", "ore_iron"), "metal", "ore item")
	t.eq(CombatVfx.material_for("mountain"), "stone", "mountain stone")
	t.eq(CombatVfx.material_for("plains"), "dirt", "default dirt")
	t.check(bool(CombatVfx.impact_profile("metal")["glow"]), "metal sparks glow")
	t.check(not bool(CombatVfx.impact_profile("wood")["glow"]), "wood chips do not glow")
	t.check(CombatVfx.impact_profile("metal")["color"] != CombatVfx.impact_profile("wood")["color"], "colours differ per material")

	t.current = "vfx landing, water, light"
	t.eq(CombatVfx.landing_strength(2.0), 0.0, "small drops silent")
	t.near(CombatVfx.landing_strength(12.0), 1.0, 0.001, "hard landing capped")
	t.check(CombatVfx.in_water(-1.0), "below water level")
	t.check(not CombatVfx.in_water(0.5), "dry ground")
	t.near(CombatVfx.flash_energy(4.0, 0.0), 4.0, 0.001, "light peaks at start")
	t.near(CombatVfx.flash_energy(4.0, 1.0), 0.0, 0.001, "light dies at end")
	t.check(CombatVfx.sparkle_color("gold_coin") != CombatVfx.sparkle_color("rock"), "sparkle per item")

	t.current = "vfx runtime nodes"
	var vfx := CombatVfx.new()
	t.check(vfx != null, "instantiates")
	vfx.free()
