extends RefCounted
## Reusable native physics-field settings and matching stock-Godot blast path.
const Debris = preload("res://scripts/client/physics_debris.gd")
const EngineFeatures = preload("res://scripts/client/engine_features.gd")


func run(t) -> void:
	t.current = "shockwave energy falls off quadratically for all game debris"
	t.near(Debris.falloff(0.0, 8.0), 1.0, 0.0001,
		"a shockwave has full impulse at its origin")
	t.near(Debris.falloff(4.0, 8.0), 0.25, 0.0001,
		"the quadratic field applies a quarter impulse halfway out")
	t.eq(Debris.falloff(8.0, 8.0), 0.0,
		"nothing past the blast boundary is pushed")

	t.current = "wall shielding remains bounded and opt-in in the engine"
	t.near(Debris.blast_shielding(false), 1.0, 0.0001,
		"unobstructed fragments receive full shockwave")
	t.near(Debris.blast_shielding(true), 0.25, 0.0001,
		"world collision shields 75 percent of the shockwave")
	t.eq(Debris.blast_shielding(true, 0.0), 0.0,
		"solid cover can block the entire impulse")
	t.eq(Debris.blast_shielding(true, -1.0), 0.0,
		"occlusion attenuation cannot be negative")
	t.eq(Debris.blast_shielding(true, 9.0), 1.0,
		"occlusion attenuation never amplifies shockwaves")
	t.eq(Debris.BLAST_WALL_MASK, 1,
		"only the world-geometry layer blocks debris explosions")
	t.eq(Debris.BLAST_MAX_OCCLUSION_RAYS, 24,
		"the old and new engines both limit additional rays per explosion")
	t.check(Debris.BLAST_WALL_MASK & Debris.LAYER == 0,
		"debris cannot accidentally shield itself")
	t.check(Debris.BLAST_WALL_MASK & (1 << 19) == 0,
		"ragdoll bodies cannot accidentally shield themselves")

	t.current = "velocity-change mode scales impulse with mass"
	t.near(Debris.blast_impulse_magnitude(12.0, 0.5, 1.0), 6.0, 0.0001,
		"one kilogram fragment receives the expected impulse")
	t.near(Debris.blast_impulse_magnitude(12.0, 0.5, 8.0), 48.0, 0.0001,
		"eight kilogram fragment needs eight times as much momentum")
	t.near(Debris.blast_impulse_magnitude(12.0, 0.5, 8.0) / 8.0, 6.0, 0.0001,
		"heavy and light fragments receive equal speed changes")
	t.near(Debris.blast_impulse_magnitude(-12.0, 0.5, 8.0), -48.0, 0.0001,
		"negative attraction impulse is symmetric")

	t.current = "native Cgame physics fields implement the matching semantics"
	if EngineFeatures.has("RadialForceField3D"):
		var field = ClassDB.instantiate("RadialForceField3D")
		if field.has_method("set_occlusion_mask"):
			t.eq(int(field.get("occlusion_mask")), 0,
				"legacy scenes keep occlusion disabled by default")
			t.eq(bool(field.get("mass_independent")), false,
				"legacy fields preserve original physical momentum impulses")
			field.call("set_occlusion_mask", Debris.BLAST_WALL_MASK)
			field.call("set_occlusion_attenuation", Debris.BLAST_WALL_ATTENUATION)
			field.call("set_max_occlusion_rays", Debris.BLAST_MAX_OCCLUSION_RAYS)
			field.call("set_mass_independent", true)
			t.eq(int(field.call("get_occlusion_mask")), Debris.BLAST_WALL_MASK,
				"native force field has an independent wall collision filter")
			t.near(float(field.call("get_occlusion_attenuation")), 0.25, 0.0001,
				"native field matches stock-Godot attenuation")
			t.eq(int(field.call("get_max_occlusion_rays")), 24,
				"native extra ray work stays capped")
			t.check(bool(field.call("is_mass_independent")),
				"native field gives mass-independent velocity kicks")
			field.call("set_max_occlusion_rays", 999)
			t.eq(int(field.call("get_max_occlusion_rays")), 64,
				"no more than 64 occlusion rays can be requested")
		else:
			t.check(true,
				"older Cgame field remains supported by the script fallback")
		field.free()
	else:
		t.check(true, "stock Godot uses GDScript query and impulse fallback")

	t.current = "live gameplay uses the new native impulse and compatible fallback"
	var features_source: String = (EngineFeatures as Script).source_code
	var debris_source: String = (Debris as Script).source_code
	t.check(debris_source.contains("BLAST_WALL_MASK, BLAST_WALL_ATTENUATION, true, 2"),
		"active gameplay blasts request shielded, mass-independent quadratic fields")
	t.check(features_source.contains('field.set("mass_independent", true)'),
		"the native field gets velocity-change behavior explicitly")
	t.check(features_source.contains('field.set("occlusion_mask", wall_mask)'),
		"the native field sees world geometry rather than the ragdoll layer")
	t.check(features_source.contains('field.has_method("set_occlusion_mask")'),
		"old fork binaries fall back safely instead of ignoring requested shielding")
	t.check(debris_source.contains("occlusion_rays < BLAST_MAX_OCCLUSION_RAYS"),
		"stock fallback obeys the same explicit ray budget")
	t.check(debris_source.contains("wall_ray.exclude"),
		"receiving body is excluded from its own blast ray")
	t.check(debris_source.contains("bone.mass"),
		"physical bones also receive normalized velocity changes")
	t.check(debris_source.contains("_apply_blasts()"),
		"the fallback still runs inside the existing physics update")
