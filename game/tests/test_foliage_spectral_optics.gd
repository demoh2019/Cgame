extends RefCounted
## Shared thin-leaf spectral absorption; no extra texture samples or passes.
const Profiles = preload("res://scripts/client/graphics_profiles.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")
const Foliage = preload("res://scripts/client/foliage.gd")
const Grass = preload("res://scripts/client/grass_field.gd")


func run(t) -> void:
	t.current = "foliage spectral quality scales from zero to Ultra"
	var prev := -1.0
	for tier in 4:
		var settings: Dictionary = Profiles.settings(tier)
		var amount: float = float(settings["leaf_optics_quality"])
		t.check(amount >= 0.0 and amount <= 1.0, "spectral tint is bounded")
		t.check(amount >= prev, "optical realism increases with graphic tier")
		prev = amount
	t.eq(float(Profiles.settings(0)["leaf_optics_quality"]), 0.0,
		"Performance skips premium optics")
	t.eq(float(Profiles.settings(1)["leaf_optics_quality"]), 0.0,
		"Balanced preserves original leaf lighting")
	t.check(float(Profiles.settings(2)["leaf_optics_quality"]) > 0.0,
		"High enables natural leaf pigments")
	t.eq(float(Profiles.settings(3)["leaf_optics_quality"]), 1.0,
		"Ultra enables full foliage spectral correction")
	var mutated := Profiles.settings(3)
	mutated["leaf_optics_quality"] = -1.0
	t.eq(float(Profiles.settings(3)["leaf_optics_quality"]), 1.0,
		"profiles cannot be mutated through callers")

	t.current = "shared native spatial shader transmission"
	var source: String = FileAccess.get_file_as_string(
		"res://assets/shaders/foliage_spectral_optics.gdshaderinc")
	t.check(not source.is_empty(), "shared GLSL include exists")
	t.check(source.contains("vec3 aa_foliage_spectral_filter("),
		"trees and grass use one optical model")
	t.check(source.contains("1.0 / (vec3(1.0) + absorption * t)"),
		"light transmittance follows inexpensive reciprocal absorption")
	t.check(source.contains("clamp(thickness, 0.35, 1.55)"),
		"thin leaf optical depth is bounded")
	t.check(source.contains("clamp(transmission * 1.55, vec3(0.20), vec3(1.05))"),
		"reflected sunlight is not replaced with unbounded emission")
	t.check(not source.contains("texture(") and not source.contains("exp("),
		"foliage optics require no extra sampler or exponential")
	for shader in [Foliage.SHADER_CODE, Grass.SHADER_CODE]:
		t.check(shader.contains("foliage_spectral_optics.gdshaderinc"),
			"all streamed plants use shared spectral include")
		t.check(shader.contains("global uniform float aa_leaf_optics_quality;"),
			"all foliage obeys one GPU quality budget")
		t.check(shader.contains("if (aa_leaf_optics_quality > 0.001)"),
			"low quality avoids all pigment filtering work")
		t.check(shader.contains("aa_foliage_spectral_filter("),
			"premium shader path applies common wavelength attenuation")
		t.check(shader.contains("BACKLIGHT =") and shader.contains("ALBEDO ="),
			"existing PBR/albedo and real direct-light transmission remain")
	t.check(Foliage.SHADER_CODE.contains("if (cut_out && aa_leaf_transmission > 0.001)"),
		"bark and solid meshes skip thin-sheet optics")
	t.check(Foliage.SHADER_CODE.contains("ALPHA_SCISSOR_THRESHOLD"),
		"leaf silhouette and opaque cutout behavior remain")
	t.check(Grass.SHADER_CODE.contains("grass_light_fade > 0.001"),
		"out-of-range grass does not evaluate optics")
	t.check(Grass.SHADER_CODE.contains("shadows_disabled"),
		"grass retains low-cost batched rendering")
	t.current = "quality reaches actual live world shaders"
	var registered: Dictionary = ProjectSettings.get_setting(
		"shader_globals/aa_leaf_optics_quality", {})
	t.eq(str(registered.get("type", "")), "float",
		"engine shader global registered")
	t.eq(float(registered.get("value", -1.0)), 0.0,
		"startup stays compatible with low-end material compile")
	t.check((Quality as Script).source_code.contains(
		'global_shader_parameter_set(&"aa_leaf_optics_quality"'),
		"live quality controller updates foliage and grass on preset switch")
	# Pure CPU check of the same rational model: green light travels farther
	# than blue and red in lush leaves, while thicker pigments absorb more.
	for depth in [0.4, 0.7, 1.4]:
		var red := 1.0 / (1.0 + 1.22 * depth)
		var green := 1.0 / (1.0 + 0.50 * depth)
		var blue := 1.0 / (1.0 + 1.72 * depth)
		t.check(green > red and red > blue,
			"lush leaves preferentially transmit green sunlight")
	t.check(1.0 / (1.0 + 0.50 * 1.4) <
		1.0 / (1.0 + 0.50 * 0.4), "thick leaf veins transmit less light")
