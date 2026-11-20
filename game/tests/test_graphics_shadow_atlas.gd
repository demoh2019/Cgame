extends RefCounted
## Deterministic shadow atlas budgets keep the same native Godot shadow pass.
## These pure tests do not allocate GPU memory or change the shared test runner.
const Atlas = preload("res://scripts/client/graphics_shadow_atlas.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")


func run(t) -> void:
	t.current = "shadow atlas scalability and render backend"
	var low: Dictionary = Atlas.plan(0, "forward_plus")
	var balanced: Dictionary = Atlas.plan(1, "forward_plus")
	var high: Dictionary = Atlas.plan(2, "forward_plus")
	var ultra: Dictionary = Atlas.plan(3, "forward_plus")
	t.eq(low, {"size": 1024, "depth_16": true},
		"Performance reserves a small sun shadow atlas")
	t.eq(balanced, {"size": 2048, "depth_16": true},
		"Balanced uses a memory-conservative 2048 atlas")
	t.eq(high, {"size": 4096, "depth_16": true},
		"High gives small sunlit scenery four times more atlas texels")
	t.eq(ultra, {"size": 4096, "depth_16": false},
		"Ultra improves depth precision without expanding beyond 4096")
	t.eq(Atlas.plan(-99, "forward_plus"), low, "negative tier clamps safely")
	t.eq(Atlas.plan(99, "forward_plus"), ultra, "high tier clamps safely")
	for method in ["gl_compatibility", "mobile", ""]:
		var fallback: Dictionary = Atlas.plan(3, method)
		t.eq(int(fallback["size"]), 2048,
			"fallback backend cannot request an oversized atlas")
		t.check(bool(fallback["depth_16"]),
			"fallback backend uses 16-bit depth to conserve GPU memory")
	for tier in 4:
		var p: Dictionary = Atlas.plan(tier, "forward_plus")
		var size: int = int(p["size"])
		t.check(size >= 1024 and size <= 4096 and (size & (size - 1)) == 0,
			"all atlas sizes are bounded powers of two")

	t.current = "atlas allocation invalidation and memory budget"
	t.check(Atlas.needs_apply({}, balanced), "first profile creates atlas")
	t.check(not Atlas.needs_apply(balanced, balanced.duplicate()),
		"applying an unchanged quality cannot reallocate GPU storage")
	t.check(Atlas.needs_apply(balanced, high),
		"High requires a larger shadow atlas")
	t.check(Atlas.needs_apply(high, ultra),
		"Ultra can request higher depth precision")
	t.check(Atlas.needs_apply(ultra, balanced),
		"downgrade releases the high-quality atlas")
	t.check(not Atlas.needs_apply(high, Atlas.plan(3, "gl_compatibility"))
		== false, "the backend change produces a real plan difference")
	var balanced_bytes: int = int(balanced["size"]) * int(balanced["size"]) * 2
	var high_bytes: int = int(high["size"]) * int(high["size"]) * 2
	var ultra_bytes: int = int(ultra["size"]) * int(ultra["size"]) * 4
	t.eq(high_bytes, balanced_bytes * 4,
		"High pays a bounded fourfold atlas pixel cost")
	t.eq(ultra_bytes, high_bytes * 2,
		"Ultra depth precision doubles its approximate depth storage")

	t.current = "connected to the playable game quality selector"
	var quality_source: String = (GraphicsQuality as Script).source_code
	var atmosphere_source: String = (Atmosphere as Script).source_code
	t.check(quality_source.contains("GraphicsShadowAtlas.apply(_level, str(method))"),
		"the player graphics selector changes the real shadow atlas")
	t.check(quality_source.contains("GraphicsLighting.apply(sun, env, _level, method)"),
		"existing cascades and fog retain their normal quality settings")
	t.check(atmosphere_source.contains("sun.shadow_enabled = _shadows_allowed"),
		"actual sun still respects Performance shadow disable")
