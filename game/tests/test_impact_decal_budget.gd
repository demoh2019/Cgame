extends RefCounted
## Runtime impact decals: stable opacity, pool-reuse safety, and quality budgets.
const ImpactDecals = preload("res://scripts/client/impact_decals.gd")


func run(t) -> void:
	t.current = "renderer-specific pooled impact decal budget"
	t.eq(ImpactDecals.budget(0), 0, "low preset creates no decals")
	t.eq(ImpactDecals.budget(3), 96, "ultra retains its 96 visual impact slots")
	t.eq(ImpactDecals.effective_budget(3, "gl_compatibility"), 0,
		"Compatibility renderer never creates invisible projection objects")
	t.eq(ImpactDecals.effective_budget(3, "forward_plus"), 96,
		"Forward+ uses normal quality-dependent projection capacity")
	t.eq(ImpactDecals.effective_budget(1, "mobile"), 24,
		"Mobile retains a bounded pool for supported decal projects")
	t.check(ImpactDecals.draw_distance(1) < ImpactDecals.draw_distance(3),
		"distant projected splats have a per-tier fill-rate cap")

	t.current = "fade is constant until expiry and quantized only after"
	t.eq(ImpactDecals.alpha_for_age(-2.0), 1.0,
		"a freshly allocated entry is opaque")
	t.eq(ImpactDecals.display_alpha(0.0), 1.0,
		"fresh splats never lose visibility")
	t.eq(ImpactDecals.display_alpha(ImpactDecals.LIFETIME - ImpactDecals.FADE), 1.0,
		"the stable phase never fades during the first 34 seconds")
	t.near(ImpactDecals.display_alpha(ImpactDecals.LIFETIME - 3.0), 0.5, 0.003,
		"fade midpoint is visually equivalent to the old continuous alpha")
	t.eq(ImpactDecals.display_alpha(ImpactDecals.LIFETIME), 0.0,
		"expired impacts become fully transparent")
	var last: float = 1.0
	for i in 301:
		var a: float = ImpactDecals.display_alpha(
			ImpactDecals.LIFETIME - ImpactDecals.FADE + float(i) * ImpactDecals.FADE / 300.0)
		t.check(a >= 0.0 and a <= last + 0.000001,
			"8-bit visual fade decreases monotonically without flicker")
		last = a

	t.current = "pooled slots reset alpha immediately on reuse"
	var decals := ImpactDecals.new()
	var reusable := Decal.new()
	decals.add_child(reusable)
	decals._pool.append(reusable)
	decals._born.append(-INF)
	reusable.albedo_mix = 0.15
	decals.splat(Vector3(2.0, 0.5, 3.0), Color(0.3, 0.2, 0.1, 0.8), 1.0)
	t.eq(reusable.albedo_mix, 1.0, "reused slots cannot flash with stale faded opacity")
	t.check(reusable.visible, "splat immediately enables the recycled decal")
	t.eq(decals._next, 0, "single-slot ring buffer wraps without reallocations")
	t.eq(decals._born[0], 0.0, "reused slot gets the current visual lifetime")
	decals.free()

	t.current = "real game uses no-op plateau and resets upon quality changes"
	var source: String = (ImpactDecals as Script).source_code
	t.check(source.contains('decal.distance_fade_enabled = true'),
		"projectors disable distant overdraw while preserving near-world detail")
	t.check(source.contains('decal.albedo_mix = 1.0'),
		"a pooled hit or explosion visibly starts at full opacity")
	t.check(source.contains('elif age > LIFETIME - FADE:'),
		"unchanging opaque decades do not update the renderer every frame")
	t.check(source.contains('if quality != _level or method != _method:'),
		"changing renderer or quality applies the new bound to live decal pools")
