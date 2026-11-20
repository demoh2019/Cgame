extends RefCounted
## Shallow water's spectral light transport must be renderer-independent,
## bounded by profile, and skip extra GPU texture reads.

const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const WaterRefraction = preload("res://scripts/client/water_refraction.gd")


func run(t) -> void:
	t.current = "sunlit water scattering scales with selected quality"
	var expected: Array[float] = [0.0, 0.13, 0.38, 0.72]
	var last: float = -1.0
	for quality in 4:
		var preset: Dictionary = VisualProfiles.settings(quality)
		var strength: float = float(preset["shallow_scattering_strength"])
		t.near(strength, expected[quality], 0.00001,
			"preset uses an artist-tuned, bounded water scattering strength")
		t.check(strength >= last and strength <= 1.0,
			"shallow subsurface scattering is monotonic and bounded")
		last = strength
	t.eq(VisualProfiles.settings(0)["shallow_scattering_strength"], 0.0,
		"Performance skips even the shallow-water scattering branch")
	var copy: Dictionary = VisualProfiles.settings(3)
	copy["shallow_scattering_strength"] = 0.0
	t.check(float(VisualProfiles.settings(3)["shallow_scattering_strength"]) > 0.5,
		"client profile reads cannot mutate stored Ultra settings")

	t.current = "shared sun light is updated only at existing cached-sky cadence"
	var project: String = FileAccess.get_file_as_string("res://project.godot")
	t.check(project.contains("aa_sun_to_light={") and
		project.contains("aa_sun_radiance={"),
		"real Godot global shader uniforms are registered before shader creation")
	var atmosphere: String = (Atmosphere as Script).source_code
	t.check(atmosphere.contains('global_shader_parameter_set(&"aa_sun_to_light"') and
		atmosphere.contains('global_shader_parameter_set(&"aa_sun_radiance"'),
		"the atmosphere publishes the real sun's energy and direction")
	t.check(atmosphere.contains("solar_radiance * smoothstep(0.02, 0.28, daylight)"),
		"moonlight cannot cause false bright solar scattering at night")
	var at: int = atmosphere.find('global_shader_parameter_set(&"aa_sun_radiance"')
	var sky: int = atmosphere.find("if _sky_refresh_elapsed >= _sky_refresh_interval:")
	t.check(sky >= 0 and at > sky,
		"solar uniforms use the already throttled sky lighting update")
	t.check(atmosphere.contains("sun.global_transform.basis.z.normalized()"),
		"the same sun direction is used by environment lighting")

	t.current = "existing PBR water uses spectral transport without new samples"
	var shader: String = FileAccess.get_file_as_string(
		"res://assets/shaders/water.gdshader")
	t.check(shader.contains("global uniform vec3 aa_sun_to_light;") and
		shader.contains("global uniform vec3 aa_sun_radiance;"),
		"all renderer variants share the current physical sun radiance")
	t.check(shader.contains("uniform float shallow_scattering_strength = 0.0;"),
		"low-end shader starts with the scattering feature off")
	var start: int = shader.find("if (shallow_scattering_strength > 0.001")
	var end: int = shader.find("#ifdef WATER_REFRACTION", start)
	t.check(start >= 0 and end > start,
		"scattering lives before the separate expensive SSR refraction branch")
	if start >= 0 and end > start:
		var optical: String = shader.substr(start, end - start)
		t.check(optical.contains("(1.0 - transmission * transmission) * transmission"),
			"water reuses existing Beer-Lambert absorption rather than extra exponentials")
		t.check(optical.contains("(1.0 - foam)") and
			optical.contains("smoothstep(4.2, 8.0, thickness)"),
			"opaque foam and deep offshore water suppress visible scattering")
		t.check(optical.contains("dot(to_eye") and
			optical.contains("aa_sun_to_light"),
			"view-angle anisotropy responds to the real sun")
		t.check(not optical.contains("texture(") and
			not optical.contains("textureLod(") and not optical.contains("= exp("),
			"scattering adds zero GPU texture lookups or exponentials")
	t.check(shader.contains("spectral_transmission") and
		shader.contains("fresnel") and shader.contains("foam"),
		"prior physical absorption, sky Fresnel and shoreline foam are intact")
	t.check(WaterRefraction.enabled(3, "forward_plus") and
		not WaterRefraction.enabled(3, "gl_compatibility"),
		"expensive screen refraction remains independent and backend-gated")

	t.current = "real game's live quality selector binds the water material"
	var quality: String = (GraphicsQuality as Script).source_code
	t.check(quality.contains('water_shader.set_shader_parameter("shallow_scattering_strength"'),
		"the shader's new value is changed at runtime for every quality switch")
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/water.gdshader")
	for tier in 4:
		var strength: float = float(VisualProfiles.settings(tier)["shallow_scattering_strength"])
		material.set_shader_parameter("shallow_scattering_strength", strength)
		t.near(float(material.get_shader_parameter("shallow_scattering_strength")),
			strength, 0.00001, "actual material accepts the artist's scattering budget")
