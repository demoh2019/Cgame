extends RefCounted
## Godot renderer-native specular anti-aliasing and safe tier switches.
const NativeSpecular = preload("res://scripts/client/graphics_native_specular_aa.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "renderer and graphical tier compatibility"
	for method in ["gl_compatibility", "unknown", ""]:
		for tier in 4:
			t.check(not bool(NativeSpecular.plan(tier, method)["enabled"]),
				"unsupported backend never runs the screen-space filter")
	for tier in [0, 1, 2, 3]:
		var plan: Dictionary = NativeSpecular.plan(tier, "forward_plus")
		t.check(float(plan["amount"]) >= 0.0 and float(plan["amount"]) <= 4.0,
			"native normal-variance amount stays within C++ engine bounds")
		t.check(float(plan["limit"]) >= 0.01 and float(plan["limit"]) <= 1.0,
			"roughness limit stays within engine shader bounds")
		t.eq(bool(plan["enabled"]), tier > 0,
			"Performance disables native derivative work")
	t.check(NativeSpecular.plan(3, "forward_plus")["amount"] >
		NativeSpecular.plan(2, "forward_plus")["amount"],
		"Ultra can filter finer subpixel glTF specular aliasing")
	t.check(NativeSpecular.plan(3, "forward_plus")["limit"] <
		NativeSpecular.plan(1, "forward_plus")["limit"],
		"Ultra protects small glossy highlights without globally flattening roughness")
	t.check(not bool(NativeSpecular.plan(0, "mobile")["enabled"]),
		"Mobile Performance disables additional shading work")
	t.eq(NativeSpecular.plan(3, "mobile"), NativeSpecular.plan(1, "mobile"),
		"Mobile Ultra caps its native anti-aliasing to Balanced costs")
	t.eq(NativeSpecular.plan(-100, "forward_plus"),
		NativeSpecular.plan(0, "forward_plus"), "negative level clamps")
	t.eq(NativeSpecular.plan(100, "forward_plus"),
		NativeSpecular.plan(3, "forward_plus"), "large level clamps")

	t.current = "process-global native GPU settings update only when required"
	var empty: Dictionary = {}
	var low: Dictionary = NativeSpecular.plan(0, "forward_plus")
	var balanced: Dictionary = NativeSpecular.plan(1, "forward_plus")
	var high: Dictionary = NativeSpecular.plan(2, "forward_plus")
	var ultra: Dictionary = NativeSpecular.plan(3, "forward_plus")
	t.check(NativeSpecular.needs_apply(empty, balanced),
		"first graphics application sets the renderer")
	t.check(not NativeSpecular.needs_apply(balanced, balanced.duplicate()),
		"repeated same quality does not submit redundant render commands")
	t.check(NativeSpecular.needs_apply(balanced, high),
		"upgrading visual quality reconfigures specular AA")
	t.check(NativeSpecular.needs_apply(high, ultra),
		"Ultra updates the glTF highlight stabilization strength")
	t.check(NativeSpecular.needs_apply(high, low),
		"downgrading actually disables the GPU filter")
	t.check(NativeSpecular.needs_apply(ultra,
		NativeSpecular.plan(3, "gl_compatibility")),
		"renderer fallback disables native screen-space roughness")
	t.check(RenderingServer.has_method("screen_space_roughness_limiter_set_active"),
		"the custom Godot renderer exposes its native roughness API")

	t.current = "real server calls are deduplicated and remain safe"
	NativeSpecular.apply(1, "forward_plus")
	t.eq(NativeSpecular._applied, balanced,
		"Balanced actually activates its production renderer plan")
	NativeSpecular.apply(1, "forward_plus")
	t.eq(NativeSpecular._applied, balanced,
		"repeated apply preserves renderer state")
	NativeSpecular.apply(3, "forward_plus")
	t.eq(NativeSpecular._applied, ultra,
		"Ultra applies the premium GPU filter")
	NativeSpecular.apply(3, "gl_compatibility")
	t.check(not bool(NativeSpecular._applied["enabled"]),
		"Compatibility leaves imported materials unfiltered")
	NativeSpecular.apply(2, "forward_plus")
	t.eq(NativeSpecular._applied, high, "switching back restores High")
	NativeSpecular.apply(1, "forward_plus")
	t.eq(NativeSpecular._applied, balanced,
		"restore Balanced renderer default after the test")

	t.current = "actual game applies filter alongside other PBR quality policies"
	var source: String = (Quality as Script).source_code
	t.check(source.contains("GraphicsNativeSpecularAA.apply(_level, str(method))"),
		"every in-game graphic preset reaches the native rendering backend")
	t.check(source.contains("GraphicsTextureStreaming.apply(_level, str(method))"),
		"native texture mip streaming budget remains supported")
	t.check(source.contains('global_shader_parameter_set(&"aa_specular_aa_strength"'),
		"per-material normal variance AA remains available in our custom shaders")
	t.eq(float(ProjectSettings.get_setting(
		"rendering/anti_aliasing/screen_space_roughness_limiter/amount", -1.0)),
		0.25, "startup renderer matches Balanced without a pipeline reconfiguration")
	t.near(float(ProjectSettings.get_setting(
		"rendering/anti_aliasing/screen_space_roughness_limiter/limit", -1.0)),
		0.18, 0.0001, "startup roughness cap matches the runtime profile")
