extends RefCounted
## Startup shader scan and HDR platform guards, without a GPU or a window.

const ShaderWarmup = preload("res://scripts/client/shader_warmup.gd")
const Hdr = preload("res://scripts/client/graphics_hdr_output.gd")


func run(t) -> void:
	t.current = "shader warmup ignores deleted resources"
	var valid_path := "res://assets/shaders/ground.gdshader"
	var missing_path := "res://assets/shaders/meadow_grass.gdshader"
	var loadable: PackedStringArray = ShaderWarmup.loadable_shader_paths(
		PackedStringArray([valid_path, missing_path]))
	t.check(loadable.has(valid_path), "tracked ground shader is still warmed")
	t.check(not loadable.has(missing_path), "stale meadow shader entry cannot trigger a load error")
	t.eq(loadable.size(), 1, "only existing shaders are retained")

	t.current = "macOS HDR reference white"
	t.check(not Hdr.can_set_reference_luminance("macOS"),
		"macOS uses the user's brightness setting")
	t.check(Hdr.can_set_reference_luminance("Windows"),
		"Windows keeps the adjustable paper white path")
	t.check(Hdr.can_set_reference_luminance("Linux"),
		"Linux keeps the adjustable paper white path")
