extends RefCounted
## Native Forward+ screen-space contact shadows: quality and no-cost fallback.
const ContactShadows = preload("res://scripts/client/graphics_contact_shadows.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")


func run(t) -> void:
	t.current = "contact shadows only on desktop Forward+ High/Ultra"
	for method in ["gl_compatibility", "mobile", ""]:
		for tier in 4:
			t.check(not bool(ContactShadows.settings(tier, method)["enabled"]),
					"non-Forward+ renderers never run contact ray marching")
	for tier in [0, 1]:
		t.check(not bool(ContactShadows.settings(tier, "forward_plus")["enabled"]),
				"Performance and Balanced turn off the extra contact pass")
	var high: Dictionary = ContactShadows.settings(2, "forward_plus")
	var ultra: Dictionary = ContactShadows.settings(3, "forward_plus")
	t.check(bool(high["enabled"]) and bool(ultra["enabled"]),
			"high-end players get tighter shadow contacts for leaves, props and feet")
	t.check(float(high["blur"]) > 0.0 and float(high["blur"]) < float(ultra["blur"]),
			"Ultra uses a slightly softer and natural foliage contact penumbra")
	t.eq(ContactShadows.settings(-100, "forward_plus"),
			ContactShadows.settings(0, "forward_plus"),
			"invalid negative quality is clamped")
	t.eq(ContactShadows.settings(100, "forward_plus"), ultra,
			"invalid upper quality is clamped")
	t.check(bool(ProjectSettings.get_setting(
			"rendering/lights_and_shadows/contact_shadow/enabled", false)),
			"the global engine pass is compiled in for opt-in sun lights")

	t.current = "sun opt-in preserves original shadow map and PCSS quality"
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.shadow_blur = 1.33
	sun.light_angular_distance = 0.35
	ContactShadows.apply(sun, 1, "forward_plus")
	t.check(not sun.shadow_contact_shadows_allow,
			"Balanced sun cannot trigger a contact-shadow depth prepass")
	ContactShadows.apply(sun, 3, "forward_plus")
	t.check(sun.shadow_contact_shadows_allow,
			"Ultra sun is opted into screen-space contact shadows")
	t.near(sun.shadow_contact_shadows_blur, float(ultra["blur"]), 0.0001,
			"the native directional light receives the Ultra foliage blur")
	ContactShadows.apply(sun, 2, "forward_plus")
	t.near(sun.shadow_contact_shadows_blur, float(high["blur"]), 0.0001,
			"switching to High updates contact shadow softness in place")
	ContactShadows.apply(sun, 3, "gl_compatibility")
	t.check(not sun.shadow_contact_shadows_allow,
			"switching to Compatibility disables the screen effect")
	t.near(sun.shadow_blur, 1.33, 0.0001,
			"original cascade shadow filtering is unaffected")
	t.near(sun.light_angular_distance, 0.35, 0.0001,
			"existing soft-shadow PCSS stays independently controlled")
	t.check(sun.shadow_enabled, "global sun shadow budget is not overridden")
	sun.free()
	ContactShadows.apply(null, 3, "forward_plus")

	t.current = "graphics integration and cheap startup"
	var quality_code: String = (GraphicsQuality as Script).source_code
	var atmosphere_code: String = (Atmosphere as Script).source_code
	t.check(quality_code.contains(
			"GraphicsContactShadows.apply(sun, _level, str(method))"),
			"online and local graphics quality switch enables contact shadows")
	t.check(atmosphere_code.contains("sun.shadow_contact_shadows_allow = false"),
			"new worlds start with the cheap Balanced contact-shadow setting")
	t.check(quality_code.contains("sun.directional_shadow_max_distance"),
			"existing cascade distance continues to be controlled by quality")
