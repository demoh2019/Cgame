extends RefCounted
## GPU precipitation rendering and Compatibility fallback. Requires no storm,
## network transport, external assets or dedicated graphics hardware.

const RainVfx = preload("res://scripts/client/rain_vfx.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const Effects = preload("res://scripts/client/effects.gd")
const LocalClient = preload("res://scripts/client/client_main.gd")
const OnlineClient = preload("res://scripts/client/online_main.gd")


func run(t) -> void:
	t.current = "renderer-aware rain simulation budgets"
	t.check(RainVfx.use_gpu("forward_plus"), "Forward+ renders storm rain on GPU")
	t.check(RainVfx.use_gpu("mobile"), "Mobile renderer supports GPU rain")
	t.check(not RainVfx.use_gpu("gl_compatibility"),
		"Compatibility renderer keeps CPU rain on older graphics devices")
	t.check(not RainVfx.use_gpu("broken_backend"),
		"unknown rendering method fails safely to CPU")
	var previous_gpu := 0
	var previous_cpu := 0
	for level in 4:
		var modern: Dictionary = RainVfx.budget(level, "forward_plus")
		var fallback: Dictionary = RainVfx.budget(level, "gl_compatibility")
		t.check(int(modern["amount"]) > previous_gpu, "GPU rain cap scales with quality")
		t.check(int(fallback["amount"]) > previous_cpu, "CPU rain cap scales with quality")
		t.check(int(fallback["amount"]) <= int(modern["amount"]),
			"CPU fallback costs less than modern GPU rain")
		previous_gpu = int(modern["amount"])
		previous_cpu = int(fallback["amount"])
	t.check(int(RainVfx.budget(3, "gl_compatibility")["amount"]) < 700,
		"even CPU Ultra uses fewer particles than the old 700-drop emitter")
	t.eq(RainVfx.budget(-100, "forward_plus"),
		RainVfx.budget(0, "forward_plus"), "negative tier is clamped")
	t.eq(RainVfx.budget(999, "mobile"),
		RainVfx.budget(3, "mobile"), "out-of-range tier is clamped")

	t.current = "drizzle strength and invalid weather input"
	t.near(RainVfx.density(0.0), 0.0, 0.0001, "clear sky emits no rain")
	t.near(RainVfx.density(0.035), 0.0, 0.0001, "zero drizzle is silent")
	t.check(RainVfx.density(0.4) > 0.0 and
		RainVfx.density(0.4) < RainVfx.density(0.8), "rain gets denser smoothly")
	t.near(RainVfx.density(1.0), 1.0, 0.0001, "storm fills the selected cap")
	t.eq(RainVfx.density(-100.0), 0.0, "negative intensity never emits")
	t.eq(RainVfx.density(NAN), 0.0, "invalid NaN weather is discarded")
	t.eq(RainVfx.density(INF), 0.0, "infinite intensity is discarded")

	t.current = "live Godot GPU emitter with explicit culling bounds"
	var gpu := RainVfx.create("forward_plus") as GPUParticles3D
	t.check(gpu != null, "the GPU node is really instantiated")
	if gpu != null:
		t.check(gpu.draw_pass_1 is QuadMesh, "two-triangle billboard replaces box streaks")
		t.check(gpu.process_material is ParticleProcessMaterial,
			"GPU particles have a real Godot particle simulation material")
		t.check(gpu.visibility_aabb.size.y >= 40.0,
			"camera-local rain remains inside a correctly sized GPU culling bound")
		t.check(not gpu.local_coords, "drops do not follow the camera after spawning")
		t.eq(gpu.fixed_fps, 30, "GPU rain uses a bounded simulation rate")
		t.check(gpu.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"thin rain does not rasterize shadow maps")
		RainVfx.apply_quality(gpu, 3)
		t.eq(gpu.amount, int(RainVfx.budget(3, "forward_plus")["amount"]),
			"changing quality sets the hard allocated GPU particle budget")
		var count_before: int = gpu.amount
		RainVfx.update(gpu, Vector3(12.0, 18.0, 24.0), 0.55)
		t.eq(gpu.amount, count_before,
			"changing weather changes ratio, never restarts or reallocates particle capacity")
		t.check(gpu.emitting and gpu.amount_ratio > 0.0 and gpu.amount_ratio < 1.0,
			"rain intensity controls GPU emission continuously")
		t.near(gpu.global_position.y, 36.0, 0.0001,
			"rain starts above the camera view")
		RainVfx.update(gpu, Vector3.ZERO, 0.0)
		t.check(not gpu.emitting, "GPU emitter stops when the storm ends")
		gpu.free()

	t.current = "Compatibility fallback remains cheaper and visible"
	var cpu := RainVfx.create("gl_compatibility") as CPUParticles3D
	t.check(cpu != null, "Compatibility creates a real CPU particle fallback")
	if cpu != null:
		t.check(cpu.mesh is QuadMesh, "CPU fallback reuses cheap billboard geometry")
		t.check(not cpu.local_coords, "CPU rain drops stay in world space")
		RainVfx.apply_quality(cpu, 0)
		t.eq(cpu.amount, int(RainVfx.budget(0, "gl_compatibility")["amount"]),
			"Performance loads the minimum CPU particle budget")
		RainVfx.update(cpu, Vector3.ZERO, 0.35)
		t.check(cpu.emitting and cpu.color.a > 0.0 and cpu.color.a < 1.0,
			"CPU drizzle is faded instead of rebuilding particle buffers")
		RainVfx.update(cpu, Vector3.ZERO, 0.0)
		t.check(not cpu.emitting, "CPU emitter stops when clear")
		cpu.free()

	t.current = "storm rain is integrated into both playable clients"
	t.check((GraphicsQuality as Script).source_code.contains("static func level()"),
		"the rain effect can read the existing quality preference")
	var effects: String = (Effects as Script).source_code
	t.check(effects.contains("RainVfx.create("),
		"multiplayer uses the GPU rain emitter with compatibility fallback")
	t.check(effects.contains("RainVfx.apply_quality("),
		"multiplayer rain responds to quality changes")
	t.check(effects.contains("RainVfx.update("),
		"multiplayer rain responds to the real storm each frame")
	var online: String = (OnlineClient as Script).source_code
	t.check(online.contains("effects.update_rain("),
		"multiplayer frame loop still feeds real-world storm strength")
	var offline: String = (LocalClient as Script).source_code
	t.check(offline.contains("RainVfx.create(") and
		offline.contains("RainVfx.update(_rain_vfx,"),
		"local preview also renders storm rain with the same GPU budgets")
	t.check(offline.contains("RainVfx.apply_quality(_rain_vfx, GraphicsQuality.level())"),
		"offline quality hotkey refreshes its rain cap")
