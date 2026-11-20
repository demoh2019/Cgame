extends RefCounted
## Grass blade light transmission is a zero-sample lighting addition.
## It cannot change gameplay, tuft geometry or network state.

const Grass = preload("res://scripts/client/grass_field.gd")
const Profiles = preload("res://scripts/client/graphics_profiles.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "quality-aware thin grass backlighting"
	var amounts: Array[float] = []
	for level in 4:
		var p: Dictionary = Profiles.settings(level)
		var strength: float = float(p.get("grass_transmission", -1.0))
		t.check(strength >= 0.0 and strength <= 0.5,
			"grass light transmission stays bounded on %s" % Quality.NAMES[level])
		amounts.append(strength)
	t.near(amounts[0], 0.0, 0.0001, "Performance skips extra lighting")
	t.check(amounts[1] > amounts[0], "Balanced adds subtle lit grass tips")
	t.check(amounts[2] > amounts[1], "High lights foliage tips more")
	t.check(amounts[3] > amounts[2], "Ultra retains maximum detail")
	t.near(float(Profiles.settings(-20)["grass_transmission"]), amounts[0], 0.0001,
		"negative preset is safely clamped")
	t.near(float(Profiles.settings(100)["grass_transmission"]), amounts[3], 0.0001,
		"high preset is safely clamped")

	t.current = "shader source preserves cheap batching"
	var shader: String = Grass.SHADER_CODE
	t.check(shader.contains("global uniform float aa_grass_transmission;"),
		"grass has one shared global uniform")
	t.check(shader.contains("varying float grass_light_fade;"),
		"grass uses vertex-computed distance fade")
	t.check(shader.contains("grass_light_fade = shrink;"),
		"grass tip light fades with existing camera geometry fade")
	t.check(shader.contains("if (aa_grass_transmission > 0.001 && grass_light_fade > 0.001)"),
		"low tiers and invisible distant plants skip backlight math")
	t.check(shader.contains("BACKLIGHT = color * leaf_tip_mask"),
		"direct-light transmission reuses existing blade color")
	t.check(not shader.contains("SSS_STRENGTH"),
		"no expensive screen-space subsurface blur is enabled")
	t.check(shader.contains("render_mode cull_disabled") and shader.contains("shadows_disabled"),
		"existing two-sided, cheap grass render mode is preserved")
	t.check(shader.contains("if (shrink > 0.001)") and
		shader.contains("aa_vegetation_wind"),
		"wind remains quality-correct")
	t.check(shader.contains("ALBEDO = apply_cloud_shadow(") and
		shader.contains("aa_weather_wetness"),
		"grass retains weather and cloud shading")
	var settings: Dictionary = ProjectSettings.get_setting(
		"shader_globals/aa_grass_transmission", {})
	t.eq(str(settings.get("type", "")), "float", "global registered as float")
	t.near(float(settings.get("value", -1.0)), 0.0, 0.0001,
		"before loading graphics preset the shader costs nothing extra")
	t.check((Quality as Script).source_code.contains(
		'global_shader_parameter_set(&"aa_grass_transmission"'),
		"quality manager publishes backlight budget")
