extends RefCounted
## Decal pool budgets/fade and reverb zone selection (Unity/Unreal parity features).

const ImpactDecals = preload("res://scripts/client/impact_decals.gd")
const ReverbZones = preload("res://scripts/client/reverb_zones.gd")


func run(t) -> void:
	t.current = "impact decal budgets and fade"
	t.eq(ImpactDecals.budget(0), 0, "Low quality draws no decals")
	t.check(ImpactDecals.budget(3) > ImpactDecals.budget(1), "budget grows with quality")
	t.eq(ImpactDecals.budget(99), ImpactDecals.budget(3), "tier is clamped")
	t.near(ImpactDecals.alpha_for_age(1.0), 1.0, 0.001, "fresh decal is opaque")
	t.near(ImpactDecals.alpha_for_age(ImpactDecals.LIFETIME), 0.0, 0.001, "expired decal is invisible")
	var mid := ImpactDecals.alpha_for_age(ImpactDecals.LIFETIME - ImpactDecals.FADE * 0.5)
	t.near(mid, 0.5, 0.001, "decal fades linearly")
	var tex := ImpactDecals.splat_texture(3)
	t.check(tex.get_image().get_pixel(32, 32).a > 0.9, "splat centre is solid")
	t.check(tex.get_image().get_pixel(0, 0).a < 0.05, "splat corner is clear")
	var pool := ImpactDecals.new()
	pool.configure(1)
	t.eq(pool.get_child_count(), ImpactDecals.budget(1), "pool preallocates its budget")
	for i in 100:
		pool.splat(Vector3.ZERO, Color.RED)
	t.eq(pool.get_child_count(), ImpactDecals.budget(1), "ring buffer never grows")
	pool.configure(0)
	t.eq(pool._pool.size(), 0, "dropping to Low releases decals")
	pool.free()

	t.current = "reverb zones"
	t.eq(ReverbZones.zone_for(true, "forest"), "underground", "underground wins")
	t.eq(ReverbZones.zone_for(false, "forest"), "forest", "forest canopy")
	t.eq(ReverbZones.zone_for(false, "plains"), "open", "open ground")
	var bus := ReverbZones.ensure_bus()
	t.eq(ReverbZones.ensure_bus(), bus, "bus is created once")
	var fx := ReverbZones.reverb(bus)
	t.check(fx != null, "SFX bus carries a reverb")
	ReverbZones.blend(fx, "underground", 1.0)
	t.near(fx.wet, ReverbZones.PRESETS["underground"]["wet"], 0.001, "full blend reaches preset")
	ReverbZones.blend(fx, "open", 0.5)
	t.check(fx.wet < 0.42 and fx.wet > 0.04, "partial blend glides")
