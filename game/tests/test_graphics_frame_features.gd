extends RefCounted
## Frame pacing, foveated VRS, HDR output and area-light softness tiers.

const Pacing = preload("res://scripts/client/graphics_frame_pacing.gd")
const Foveated = preload("res://scripts/client/graphics_foveated_shading.gd")
const Hdr = preload("res://scripts/client/graphics_hdr_output.gd")
const ShaderWarmup = preload("res://scripts/client/shader_warmup.gd")
const AreaLights = preload("res://scripts/client/graphics_area_lights.gd")


func run(t) -> void:
	t.current = "frame pacing"
	t.eq(Pacing.settings(0, 144.0)["max_fps"], 72, "Performance halves high refresh panels")
	t.eq(Pacing.settings(1, 60.0)["max_fps"], 60, "Balanced caps at refresh")
	t.eq(Pacing.settings(3, 120.0)["vsync"], DisplayServer.VSYNC_MAILBOX, "Ultra uses mailbox")
	t.eq(Pacing.settings(0, 0.0)["max_fps"], 60, "unknown refresh falls back to 60")

	t.current = "foveated shading"
	t.check(bool(Foveated.settings(0, "forward_plus")["enabled"]), "Performance uses VRS")
	t.check(not bool(Foveated.settings(3, "forward_plus")["enabled"]), "Ultra shades full rate")
	t.check(not bool(Foveated.settings(0, "gl_compatibility")["enabled"]), "Compatibility has no VRS")
	var map: Image = Foveated.build_map(Vector2i(40, 24), 0.4, 0.7)
	t.eq(map.get_pixel(20, 12), Foveated.RATE_1X1, "center is full rate")
	t.eq(map.get_pixel(0, 0), Foveated.RATE_4X4, "corners are coarsest")
	var vp := SubViewport.new()
	vp.size = Vector2i(320, 160)
	t.check(Foveated.apply(vp, 0, "forward_plus"), "VRS texture applied")
	t.eq(vp.vrs_mode, Viewport.VRS_TEXTURE, "viewport in texture mode")
	t.check(not Foveated.apply(vp, 3, "forward_plus"), "Ultra disables VRS")
	t.eq(vp.vrs_mode, Viewport.VRS_DISABLED, "viewport VRS off")
	vp.free()

	t.current = "hdr output"
	t.check(Hdr.wanted(3, "forward_plus", true), "Ultra on HDR monitor outputs HDR")
	t.check(not Hdr.wanted(3, "forward_plus", false), "SDR monitor stays SDR")
	t.check(not Hdr.wanted(1, "forward_plus", true), "Balanced stays SDR")
	t.check(not Hdr.wanted(3, "gl_compatibility", true), "Compatibility stays SDR")
	t.check(not Hdr.can_set_reference_luminance("macOS"), "macOS manages HDR reference white through brightness")
	t.check(Hdr.can_set_reference_luminance("Windows"), "Windows keeps manual HDR paper white")
	t.check(Hdr.can_set_reference_luminance("Linux"), "Linux keeps manual HDR paper white")

	t.current = "shader warmup missing resource filtering"
	var valid_path := "res://assets/shaders/ground.gdshader"
	var stale_path := "res://assets/shaders/meadow_grass.gdshader"
	var loadable: PackedStringArray = ShaderWarmup.loadable_shader_paths(
		PackedStringArray([valid_path, stale_path]))
	t.check(loadable.has(valid_path), "real shaders remain in the warmup set")
	t.check(not loadable.has(stale_path), "removed meadow shader does not cause startup resource errors")

	t.current = "area lights"
	t.eq(AreaLights.size_for(3, 0.35), 0.35, "Ultra keeps emitter radius")
	t.eq(AreaLights.size_for(1, 0.35), 0.0, "Balanced skips PCSS")
	t.eq(AreaLights.filter_quality(0), RenderingServer.SHADOW_QUALITY_HARD, "Performance hard shadows")
	var lamp := OmniLight3D.new()
	AreaLights.configure(3, null)
	AreaLights.register(lamp, 0.2)
	t.near(lamp.light_size, 0.2, 0.0001, "registered light gets its size")
	t.check(lamp.is_in_group(AreaLights.GROUP), "light joins the area group")
	lamp.free()
