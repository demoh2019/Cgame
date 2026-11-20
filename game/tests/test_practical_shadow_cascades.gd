extends RefCounted
## Premium practical cascade shadow splits, with unchanged low-end fallback.
const Practical = preload("res://scripts/client/practical_shadow_cascades.gd")
const GraphicsLighting = preload("res://scripts/client/graphics_lighting.gd")


func run(t) -> void:
	t.current = "practical sun cascade quality budgets"
	for tier in [0, 1]:
		t.check(not bool(Practical.plan(tier, "forward_plus", 140.0)["enabled"]),
			"Performance and Balanced retain the original stable shadow splits")
	for renderer in ["mobile", "gl_compatibility", ""]:
		t.check(not bool(Practical.plan(3, renderer, 140.0)["enabled"]),
			"unsupported rendering backends never change their cascades")
	var high: Dictionary = Practical.plan(2, "forward_plus", 110.0)
	var ultra: Dictionary = Practical.plan(3, "forward_plus", 140.0)
	t.check(bool(high["enabled"]) and bool(ultra["enabled"]),
		"High and Ultra enable bounded PSSM distribution")
	t.check(float(high["lambda"]) > float(ultra["lambda"]),
		"High concentrates two existing cascades toward the near field")
	t.eq(float(ultra["near"]), Practical.NEAR_PLANE,
		"camera near clip policy remains deterministic")
	t.check(float(ultra["far"]) == 140.0,
		"native splitter receives actual far cascade range")
	for invalid in [NAN, INF, -1.0, 0.0, 8193.0]:
		t.check(not bool(Practical.plan(3, "forward_plus", invalid)["enabled"]),
			"invalid shadow distance cannot reach GPU shadow allocations")
	t.check(not Practical.try_apply(null, 3, "forward_plus"),
		"missing sun is safe for local preview and scene transitions")

	t.current = "real sun uses native practical splits when available"
	var sun := DirectionalLight3D.new()
	sun.directional_shadow_max_distance = 140.0
	GraphicsLighting.apply(sun, null, 3, "forward_plus")
	t.eq(sun.directional_shadow_mode,
		DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		"Ultra retains its existing four-cascade shadow draw budget")
	t.check(sun.directional_shadow_blend_splits,
		"native split blending still reduces transition seams")
	var native: bool = sun.has_method("configure_practical_shadow_cascades")
	if native:
		t.check(sun.directional_shadow_split_1 < 0.12,
			"practical near split sharpens detailed player shadows")
		t.check(sun.directional_shadow_split_1 < sun.directional_shadow_split_2
			and sun.directional_shadow_split_2 < sun.directional_shadow_split_3,
			"native cascade boundaries are strictly ordered")
		t.check(sun.directional_shadow_split_3 < 0.54,
			"near-field foliage gets more of the existing atlas area")
		var stable: float = sun.directional_shadow_split_1
		GraphicsLighting.apply(sun, null, 3, "forward_plus")
		t.near(sun.directional_shadow_split_1, stable, 0.00001,
			"reapplying same preset does not revert native cascade boundaries")
		t.check(not bool(sun.call("configure_practical_shadow_cascades", NAN, 140.0, 0.62)),
			"invalid native input is rejected without changing light state")
		t.near(sun.directional_shadow_split_1, stable, 0.00001,
			"failed plan is transactional and does not damage split layout")
	else:
		t.near(sun.directional_shadow_split_1, 0.12, 0.0001,
			"stock Godot keeps legacy Ultra cascade split")
	GraphicsLighting.apply(sun, null, 2, "forward_plus")
	t.eq(sun.directional_shadow_mode,
		DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		"High still renders two cascades, not four")
	if native:
		t.check(sun.directional_shadow_split_1 < 0.23,
			"native two-cascade plan allocates more nearby shadow detail")
	else:
		t.near(sun.directional_shadow_split_1, 0.23, 0.0001,
			"stock Godot High split is backward compatible")
	GraphicsLighting.apply(sun, null, 1, "gl_compatibility")
	t.near(sun.directional_shadow_split_1, 0.23, 0.0001,
		"renderer fallback restores original Balanced shadow distribution")
	t.check(not Practical.try_apply(sun, 3, "mobile"),
		"mobile renderer cannot activate expensive premium CSM")
	sun.free()

	t.current = "production lighting pipeline connects the new policy"
	var source: String = (GraphicsLighting as Script).source_code
	t.check(source.contains("PracticalShadowCascades.try_apply(sun, level, rendering_method)"),
		"the live graphics quality controller uses native CSM API")
	t.check(source.contains('sun.directional_shadow_split_1 = float(profile["shadow_split_1"])'),
		"legacy fixed cascade boundaries remain a full fallback")
