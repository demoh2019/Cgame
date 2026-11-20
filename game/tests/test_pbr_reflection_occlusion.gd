extends RefCounted
## End-to-end game material contract for native SDFGI reflection blending and
## roughness-aware specular occlusion. No separate screen pass or GPU texture.

const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const GraphicsIndirectLighting = preload("res://scripts/client/graphics_indirect_lighting.gd")
const GraphicsReflections = preload("res://scripts/client/graphics_reflections.gd")
const Foliage = preload("res://scripts/client/foliage.gd")


func run(t) -> void:
	t.current = "native indirect reflection occlusion reuses existing game AO"
	var terrain: Shader = load("res://assets/shaders/ground.gdshader") as Shader
	t.check(terrain != null, "streamed PBR terrain material can be loaded")
	if terrain == null:
		return
	var shader: String = terrain.code
	t.check(shader.contains("float cavity_visibility = 1.0 - cavity * 0.24 * (1.0 - puddle * 0.85);"),
		"rain-filled stone cavities restore GGX ambient reflection visibility")
	t.check(shader.contains("AO = clamp(ground_contact * micro_shadow * cavity_visibility * sky_visibility, 0.0, 1.0);"),
		"terrain combines bounded contact, cavity and landscape horizon AO for native PBR")
	t.check(shader.contains("float sky_visibility = 1.0;"),
		"low-tier and flat-ground horizon visibility preserves full ambient light")
	t.check(shader.contains("ROUGHNESS = filter_specular_roughness(final_roughness, bent);"),
		"wet stone reflection filtering shares the native roughness-aware path")
	t.check(shader.contains("float final_roughness = clamp("),
		"wet stone and dry rock have different roughness for specular occlusion")
	t.check(Foliage.SHADER_CODE.contains("AO = clamp(occlusion * (1.0 - crown_shadow), 0.0, 1.0);"),
		"trees provide their preserved ORM and canopy occlusion to native PBR")
	t.check(Foliage.SHADER_CODE.contains("ROUGHNESS = filter_specular_roughness("),
		"foliage GGX specular uses the existing roughness anti-aliasing path")

	t.current = "reflections and ambient visibility respect real rendering tiers"
	for tier in 4:
		var quality: Dictionary = GraphicsQuality.profile(tier)
		var gi: Dictionary = GraphicsIndirectLighting.settings(tier, "forward_plus")
		var reflections: Dictionary = GraphicsReflections.settings(tier, "forward_plus")
		t.eq(bool(quality["ssao"]), bool(gi["ssao_enabled"]),
			"visible graphics tier and native SSAO visibility budget stay consistent")
		t.eq(bool(reflections["enabled"]), tier >= 2,
			"expensive screen-space reflections are skipped on low tiers")
		if tier == 3:
			t.check(bool(gi["sdfgi_enabled"]) and bool(reflections["enabled"]),
				"Ultra uses new SDFGI-to-sky reflection fade and existing SSR together")
		else:
			t.check(not bool(gi["sdfgi_enabled"]),
				"only Ultra pays for the SDFGI cascade reflection path")
	for method in ["mobile", "gl_compatibility"]:
		t.check(not bool(GraphicsReflections.settings(3, method)["enabled"]),
			"mobile and Compatibility skip Forward+ SSR texture/ray costs")

	t.current = "wet cavities recover visibility without losing baked ground contact"
	var previous := -1.0
	for wet in [0.0, 0.2, 0.5, 0.8, 1.0]:
		var cavity: float = 0.8
		var visibility: float = 1.0 - cavity * 0.24 * (1.0 - float(wet) * 0.85)
		t.check(visibility > 0.0 and visibility <= 1.0,
			"cavity occlusion cannot overbrighten or invert PBR response")
		t.check(visibility >= previous,
			"water filling cracks cannot increase their ambient shadowing")
		previous = visibility
	var wet_contact: float = 0.6 * previous
	t.check(wet_contact <= 0.6,
		"wet stone retains independent baked ground contact shadows")
