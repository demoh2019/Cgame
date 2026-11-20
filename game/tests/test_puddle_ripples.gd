extends RefCounted
## Shader-only rain ripple regressions: requires no GPU, gameplay server, or
## extra textures. Both terrain renderers must share the same time and world
## coordinates and skip expensive detail when far/dry/on Performance.

const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")


func run(t) -> void:
	t.current = "puddle ripple quality budgets"
	t.check(ProjectSettings.has_setting("shader_globals/aa_puddle_ripple_strength"),
		"puddle ripple strength must exist before terrain shaders compile")
	var setting: Dictionary = ProjectSettings.get_setting(
		"shader_globals/aa_puddle_ripple_strength", {})
	t.eq(str(setting.get("type", "")), "float",
		"puddle ripple strength is a single GPU-wide scalar")
	t.near(float(setting.get("value", -1.0)), 0.22, 0.001,
		"balanced quality is the registered safe default")
	var previous: float = -1.0
	for level in range(4):
		var value: float = float(GraphicsQuality.profile(level).get(
			"puddle_ripple_strength", -1.0))
		t.check(value >= 0.0 and value <= 1.0,
			"rain ripple quality is bounded at tier %d" % level)
		t.check(value >= previous,
			"puddle ripples scale monotonically to Ultra")
		previous = value
	t.eq(GraphicsQuality.profile(0)["puddle_ripple_strength"], 0.0,
		"Performance skips procedural ripple calculations")
	t.eq(GraphicsQuality.profile(3)["puddle_ripple_strength"], 1.0,
		"Ultra enables complete ripple normal strength")
	t.eq(GraphicsQuality.profile(-99)["puddle_ripple_strength"],
		GraphicsQuality.profile(0)["puddle_ripple_strength"],
		"negative graphics level is clamped")
	t.eq(GraphicsQuality.profile(999)["puddle_ripple_strength"],
		GraphicsQuality.profile(3)["puddle_ripple_strength"],
		"oversized graphics level is clamped")
	var controller: String = (GraphicsQuality as Script).source_code
	t.check(controller.contains(
		"global_shader_parameter_set(&\"aa_puddle_ripple_strength\""),
		"one quality update changes every streamed chunk without node iteration")

	t.current = "textureless and seam-free procedural rings"
	var include_path := "res://assets/shaders/puddle_ripples.gdshaderinc"
	t.check(FileAccess.file_exists(include_path),
		"the shared puddle ripple function exists in the project")
	var rings: String = FileAccess.get_file_as_string(include_path)
	t.check(rings.contains(
		"vec2 aa_puddle_ripple_tilt(vec2 world_xz, float seconds)"),
		"ripple effect is reusable by both shader pipelines")
	t.check(rings.contains("vec2 cell = floor(world_xz / CELL);"),
		"ring centers are aligned to world space across chunk edges")
	t.check(rings.contains("float age = fract(seconds *"),
		"individual rings animate using GPU shader time")
	t.check(rings.contains("float edge_fade = 1.0 - smoothstep("),
		"ripples fade inside each tile and do not snap at cell seams")
	t.check(rings.contains("float phase = fract(h.x * h.y);"),
		"ring phases differ deterministically across neighboring cells")
	t.check(not rings.contains("texture(") and not rings.contains("textureLod("),
		"no extra albedo, normal, or screen-space texture fetch is required")
	t.check(not rings.contains("sin(") and not rings.contains("cos("),
		"impact waves use only arithmetic and smoothstep, no trig in pixels")

	t.current = "PBR textured terrain integrates near-field ripple normals"
	var ground := load("res://assets/shaders/ground.gdshader") as Shader
	t.check(ground != null, "the real PBR ground shader is loadable")
	if ground != null:
		var shader: String = ground.code
		t.check(shader.contains("global uniform float aa_puddle_ripple_strength;"),
			"PBR terrain consumes the shared GPU quality parameter")
		t.check(shader.contains("#include \"res://assets/shaders/puddle_ripples.gdshaderinc\""),
			"PBR ground uses the same seamless ripple function")
		t.check(shader.contains("puddle > 0.05"),
			"ripples run only on surfaces that have actual wet puddles")
		t.check(shader.contains("camera_distance < aa_terrain_detail_radius"),
			"far terrain does not calculate high-frequency impacts")
		t.check(shader.contains("aa_puddle_ripple_tilt(p, TIME)"),
			"ring placement is world-aligned and time-animated")
		t.check(shader.contains("bent = normalize(bent + vec3(ripple_tilt.x"),
			"ripple curvature changes actual physically lit surface normals")
		t.check(shader.contains("filter_specular_roughness(final_roughness, bent)"),
			"terrain retains existing specular anti-aliasing with ripples")
		t.check(shader.contains("textureGrad(normal_layers"),
			"normal map and world-space cliffs remain physically lit")

	t.current = "Compatibility painted terrain uses the same ripple field"
	var fallback: String = ChunkView.GROUND_SHADER
	t.check(fallback.contains("global uniform float aa_puddle_ripple_strength;"),
		"painted shader has the same preset parameter")
	t.check(fallback.contains("#include \"res://assets/shaders/puddle_ripples.gdshaderinc\""),
		"painted terrain imports the shared procedural wave")
	t.check(fallback.contains("distance_to_camera < aa_terrain_detail_radius"),
		"low-end renderer skips distant ripple work")
	t.check(fallback.contains("aa_puddle_ripple_tilt(p, TIME)"),
		"both terrain materials share identical impact rings")
	t.check(fallback.contains("NORMAL = normalize(NORMAL + view_tilt"),
		"fallback uses correct camera-space normal mapping")
	t.check(fallback.contains("puddle > 0.05"),
		"procedural terrain does not spend ripple work on dry land")
