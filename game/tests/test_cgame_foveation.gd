extends RefCounted
## Engine foveated rendering (Metal rasterization rate maps in Forward+): API surface, presets, A/B tooling.
const AbBenchmark = preload("res://scripts/client/ab_benchmark.gd")


func run(t) -> void:
	t.current = "RenderingDevice exposes desktop rasterization rate maps"
	for method in ["rasterization_rate_map_create", "rasterization_rate_map_get_physical_size",
			"rasterization_rate_map_get_axis_mapping", "texture_update_from_buffer"]:
		t.check(ClassDB.class_has_method("RenderingDevice", method), "RenderingDevice.%s" % method)

	t.current = "presets: cheaper tiers shade the screen edges at a lower rate"
	var quality: String = FileAccess.get_file_as_string("res://scripts/client/graphics_quality.gd")
	t.check(quality.contains("[0.5, 0.6, 1.0, 1.0][clampi(_level, 0, 3)]"),
		"Performance 0.5, Balanced 0.6, High/Ultra full rate")
	t.check(quality.contains("ProjectSettings.has_setting(\"rendering/vrs/cgame_foveation_edge_rate\")"),
		"only set where the renderer defines the setting (not on headless or Compatibility)")

	t.current = "scene shader rebuilds screen positions under a rate map"
	var scene: String = FileAccess.get_file_as_string("res://../servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl")
	if scene.is_empty():
		t.check(true, "engine sources not next to the project (packaged checkout)")
	else:
		t.check(scene.contains("uvec2 cluster_pos = uvec2(cgame_screen_frag_coord(gl_FragCoord.xy))"),
			"light clusters are looked up by screen position, not the smaller physical one")
		t.check(scene.contains("vec2 screen_uv = cgame_screen_frag_coord(gl_FragCoord.xy)"), "SCREEN_UV too")

	t.current = "same-scene A/B tool parses its spec"
	OS.set_environment("CGAME_AB", "")
	t.check(AbBenchmark.from_environment() == null, "no spec, no node")
	OS.set_environment("CGAME_AB", "rendering/does/not/exist:1:2")
	t.check(AbBenchmark.from_environment() == null, "unknown setting is refused")
	OS.set_environment("CGAME_AB", "rendering/anti_aliasing/quality/use_debanding:false:true")
	var node: Node = AbBenchmark.from_environment()
	t.check(node != null and node.values == [false, true], "values are parsed as Variants")
	if node != null:
		node.free()
	OS.set_environment("CGAME_AB", "")
