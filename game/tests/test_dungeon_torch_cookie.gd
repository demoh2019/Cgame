extends RefCounted
## Cinematic torch cookies reuse the existing Forward+ local light/shadow budget.
const Cookie = preload("res://scripts/client/dungeon_torch_cookie.gd")
const Budget = preload("res://scripts/client/dungeon_light_budget.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "renderer-aware candle and torch projector budget"
	for tier in [0, 1]:
		t.check(not Cookie.projector_enabled(tier, "forward_plus", true),
			"low-end renders do not allocate any projector texture")
	for method in ["gl_compatibility", "mobile", ""]:
		t.check(not Cookie.projector_enabled(3, method, true),
			"unsupported renderer never uses a panoramic light cookie")
	t.check(not Cookie.projector_enabled(3, "forward_plus", false),
		"shadowless torch cannot use a projector according to Godot")
	t.check(Cookie.projector_enabled(2, "forward_plus", true),
		"High reuses its existing single shadowed torch")
	t.check(Cookie.projector_enabled(3, "forward_plus", true),
		"Ultra reuses its two shadowed torches")
	t.eq(int(Budget.settings(2)["shadow_lights"]), 1,
		"High shadow caster budget stays one existing light")
	t.eq(int(Budget.settings(3)["shadow_lights"]), 2,
		"Ultra shadow caster budget stays two existing lights")
	t.check(Cookie.shadow_distance(2) < Cookie.shadow_distance(3),
		"High casts shadows in a smaller camera radius")
	t.check(Cookie.shadow_distance(3) < float(Budget.settings(3)["radius"]),
		"Ultra shadows stop before the full local-light influence radius")
	t.eq(Cookie.shadow_mode(2), OmniLight3D.SHADOW_DUAL_PARABOLOID,
		"High uses lower-cost dual paraboloid omni shadows")
	t.eq(Cookie.shadow_mode(3), OmniLight3D.SHADOW_CUBE,
		"Ultra preserves accurate cubemap contact shadows")
	t.check(Quality.profile(0)["shadows"] == false,
		"Performance remains fully shadow-free")

	t.current = "panoramic cookie is seamless, soft and deterministic"
	for y in [0.0, 0.1, 0.5, 0.83, 1.0]:
		t.near(Cookie.intensity_at(Vector2(0.0, y)),
			Cookie.intensity_at(Vector2(1.0, y)), 0.00001,
			"horizontal panorama seam wraps without a light stripe")
	for x in [0.0, 0.13, 0.72, 1.0]:
		t.near(Cookie.intensity_at(Vector2(x, 0.0)), 0.95, 0.00001,
			"north-pole angles collapse to the same light intensity")
		t.near(Cookie.intensity_at(Vector2(x, 1.0)), 0.95, 0.00001,
			"south pole avoids radial sampling artifacts")
	t.eq(Cookie.intensity_at(Vector2.INF), 1.0,
		"invalid procedural sampling leaves full safe illumination")
	var shadow_min: float = 2.0
	var shadow_max: float = 0.0
	for y in 13:
		for x in 21:
			var v: float = Cookie.intensity_at(Vector2(float(x) / 20.0,
				float(y) / 12.0))
			shadow_min = minf(shadow_min, v)
			shadow_max = maxf(shadow_max, v)
	t.check(shadow_min >= 0.72 and shadow_max <= 1.0,
		"projected torch occlusion never crushes visibility")
	t.check(shadow_max - shadow_min > 0.06,
		"light projector introduces genuine angular detail")

	t.current = "one native projector across hundreds of streamed torches"
	var light := OmniLight3D.new()
	Cookie.apply(light, 0, "forward_plus", false)
	t.eq(light.light_projector, null,
		"low quality never generates an unneeded texture")
	light.shadow_enabled = true
	Cookie.apply(light, 2, "forward_plus", true)
	var shared: Texture2D = light.light_projector
	t.check(shared != null, "shadowed High torch receives native projector")
	if shared != null:
		t.eq(shared.get_width(), Cookie.WIDTH,
			"cookie holds only 128 horizontal texels")
		t.eq(shared.get_height(), Cookie.HEIGHT,
			"cookie holds only 64 vertical texels")
	t.eq(light.omni_shadow_mode, OmniLight3D.SHADOW_DUAL_PARABOLOID,
		"High applies cheap shadow mapping to the actual Godot light")
	var other := OmniLight3D.new()
	other.shadow_enabled = true
	Cookie.apply(other, 3, "forward_plus", true)
	t.check(other.light_projector == shared,
		"multiple rooms share exactly the same ImageTexture")
	t.eq(other.omni_shadow_mode, OmniLight3D.SHADOW_CUBE,
		"Ultra actual Godot light uses high fidelity cube shadows")
	Cookie.apply(light, 1, "forward_plus", false)
	t.eq(light.light_projector, null,
		"live quality downgrade releases projector from the light")
	Cookie.apply(other, 3, "gl_compatibility", false)
	t.eq(other.light_projector, null,
		"renderer downgrade unbinds unsupported projector")
	light.free()
	other.free()

	t.current = "existing dungeon manager owns and gates projector updates"
	var manager: String = (Budget as Script).source_code
	t.check(manager.contains("DungeonTorchCookie.apply(light, _quality, renderer, cast)"),
		"only actively selected room lights receive projector state")
	t.check(manager.contains("DungeonTorchCookie.shadow_distance(_quality)"),
		"native projected light remains inside bounded camera range")
	t.check(manager.contains("DungeonTorchCookie.apply(light, _quality, renderer, false)"),
		"streamed-out torches release their projector")
	t.check(manager.contains("updated.size() < int(profile[\"shadow_lights\"])"),
		"global one/two shadow caster cap is still authoritative")
