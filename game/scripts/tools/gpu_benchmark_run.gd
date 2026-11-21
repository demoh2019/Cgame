extends SceneTree
## Opt-in GPU benchmark + compatibility report. Runs a fixed camera path at each quality level and
## writes user://gpu_report_<timestamp>.json for the tester to send manually. Nothing is
## uploaded and no personal data is collected: only adapter name, vendor, driver/API version,
## OS name/version, renderer and the measured metrics.
##
##   godot --path game --script res://scripts/tools/gpu_benchmark_run.gd -- \
##       [--seconds=8] [--levels=0,1,2,3] [--shots=3] [--scene=res://path.tscn] [--out=user://x.json]
## Needs a real window to render (do not pass --headless): headless runs only time the
## main loop and record no GPU time or checksums. Without --scene a synthetic scene (hundreds
## of meshes, shadowed lights, particles) is built so results are comparable across machines.
## Result schema version 1; aggregation lives in gpu_matrix_db.gd. Result-schema ideas follow
## public benchmark practice (3DMark / Unity benchmark / Steam hardware survey); original code
## (MIT-compatible).

const MatrixDb = preload("res://scripts/tools/gpu_matrix_db.gd")
const GpuSettingsDb = preload("res://scripts/client/gpu_settings_db.gd")

const WARMUP_FRAMES: int = 30
const MAX_ERROR_SAMPLES: int = 5
const MESH_COUNT: int = 400
const LIGHT_COUNT: int = 12
const PARTICLE_SYSTEMS: int = 4


## Counts engine errors/warnings emitted while a level runs (Logger needs Godot 4.5+).
class ErrorLogger extends Logger:
	var errors: int = 0
	var samples: Array[String] = []
	var _mutex: Mutex = Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		if error_type != Logger.ERROR_TYPE_WARNING:
			errors += 1
			if samples.size() < MAX_ERROR_SAMPLES:
				var msg: String = rationale if not rationale.is_empty() else code
				samples.append("%s (%s:%d): %s" % [function, file.get_file(), line, msg.left(160)])
		_mutex.unlock()

	func reset() -> void:
		_mutex.lock()
		errors = 0
		samples.clear()
		_mutex.unlock()


var _logger: ErrorLogger = ErrorLogger.new()
var _env: Environment = null
var _sun: DirectionalLight3D = null
var _omni_lights: Array[OmniLight3D] = []
var _particles: Array[GPUParticles3D] = []
var _camera: Camera3D = null
var _content: Node3D = null
var _headless: bool = false


func _initialize() -> void:
	_run()


func _run() -> void:
	var args: Dictionary = _parse_args()
	var seconds: float = float(args.get("seconds", "8"))
	var shots: int = int(args.get("shots", "3"))
	var out_path: String = str(args.get("out", "user://gpu_report_%d.json" % int(Time.get_unix_time_from_system())))
	var levels: Array[int] = []
	for p in str(args.get("levels", "0,1,2,3")).split(",", false):
		levels.append(clampi(int(p), 0, GpuSettingsDb.MAX_LEVEL))
	_headless = DisplayServer.get_name() == "headless"
	OS.add_logger(_logger)
	_build_scene(str(args.get("scene", "")))
	await process_frame

	var runs: Array[Dictionary] = []
	var completed: bool = true
	for lv in levels:
		var res: Dictionary = await _run_level(lv, seconds, shots)
		runs.append(res)
	OS.remove_logger(_logger)

	var report: Dictionary = {
		"schema": MatrixDb.SCHEMA_VERSION,
		"tool": "cgame_gpu_benchmark",
		"timestamp": int(Time.get_unix_time_from_system()),
		"completed": completed,
		"headless": _headless,
		"seconds_per_level": seconds,
		"system": _system_info(),
		"runs": runs,
		"privacy": "Only adapter, vendor, driver, OS, renderer and metrics are recorded. Send this file manually.",
	}
	var errs: Array[String] = MatrixDb.validate_report(report)
	if not errs.is_empty():
		printerr("report failed self-validation: " + "; ".join(errs))
	var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		printerr("cannot write " + out_path)
		quit(1)
		return
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print("GPU report written: ", ProjectSettings.globalize_path(out_path))
	quit(0)


func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


func _system_info() -> Dictionary:
	return {
		"adapter": _or_unknown(RenderingServer.get_video_adapter_name()),
		"vendor": _or_unknown(RenderingServer.get_video_adapter_vendor()),
		"driver": _or_unknown(RenderingServer.get_video_adapter_api_version()),
		"os": OS.get_name(),
		"os_version": OS.get_version(),
		"renderer": _or_unknown(RenderingServer.get_current_rendering_driver_name()),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"engine": str(Engine.get_version_info().get("string", "")),
		"resolution": "%dx%d" % [root.size.x, root.size.y],
		"refresh_hz": DisplayServer.screen_get_refresh_rate(),
	}


# ------------------------------------------------------------------ scene

func _build_scene(scene_path: String) -> void:
	_content = Node3D.new()
	root.add_child(_content)
	if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
		var packed: Resource = load(scene_path)
		if packed is PackedScene:
			_content.add_child((packed as PackedScene).instantiate())
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = _env
	_content.add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	_content.add_child(_sun)
	_camera = Camera3D.new()
	_camera.far = 400.0
	_camera.current = true
	_content.add_child(_camera)
	if scene_path.is_empty() or _content.get_child_count() < 5:
		_build_synthetic()


func _build_synthetic() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345
	var meshes: Array[Mesh] = [BoxMesh.new(), SphereMesh.new(), CapsuleMesh.new(), TorusMesh.new()]
	var mats: Array[StandardMaterial3D] = []
	for i in 6:
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = Color.from_hsv(float(i) / 6.0, 0.6, 0.9)
		m.roughness = 0.3 + 0.1 * float(i)
		m.metallic = 0.5 if i % 2 == 0 else 0.0
		if i == 5:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color.a = 0.5
		mats.append(m)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(120.0, 120.0)
	ground.mesh = plane
	_content.add_child(ground)
	for i in MESH_COUNT:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = meshes[i % meshes.size()]
		mi.material_override = mats[i % mats.size()]
		mi.position = Vector3(rng.randf_range(-50.0, 50.0), rng.randf_range(0.5, 6.0), rng.randf_range(-50.0, 50.0))
		mi.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0.0)
		mi.scale = Vector3.ONE * rng.randf_range(0.6, 2.2)
		_content.add_child(mi)
	for i in LIGHT_COUNT:
		var l: OmniLight3D = OmniLight3D.new()
		l.omni_range = 14.0
		l.light_energy = 2.0
		l.light_color = Color.from_hsv(rng.randf(), 0.5, 1.0)
		l.position = Vector3(rng.randf_range(-35.0, 35.0), 4.0, rng.randf_range(-35.0, 35.0))
		_content.add_child(l)
		_omni_lights.append(l)
	for i in PARTICLE_SYSTEMS:
		var p: GPUParticles3D = GPUParticles3D.new()
		var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
		pm.direction = Vector3.UP
		pm.initial_velocity_min = 2.0
		pm.initial_velocity_max = 6.0
		pm.gravity = Vector3(0.0, -4.0, 0.0)
		p.process_material = pm
		p.draw_pass_1 = SphereMesh.new()
		p.amount = 2000
		p.lifetime = 3.0
		p.visibility_aabb = AABB(Vector3(-30.0, -5.0, -30.0), Vector3(60.0, 40.0, 60.0))
		p.position = Vector3(rng.randf_range(-25.0, 25.0), 0.5, rng.randf_range(-25.0, 25.0))
		_content.add_child(p)
		_particles.append(p)


func _apply_level(lv: int) -> void:
	var feat: Dictionary = GpuSettingsDb.features_for(lv)
	_env.ssao_enabled = bool(feat["ssao"])
	_env.ssr_enabled = bool(feat["ssr"])
	_env.glow_enabled = bool(feat["glow"])
	_env.volumetric_fog_enabled = bool(feat["volumetric_fog"])
	_env.sdfgi_enabled = bool(feat["sdfgi"])
	_sun.shadow_enabled = lv >= 1
	for l in _omni_lights:
		l.shadow_enabled = lv >= 2
	var msaa: int = int(feat["msaa"])
	root.msaa_3d = Viewport.MSAA_4X if msaa >= 4 else (Viewport.MSAA_2X if msaa == 2 else Viewport.MSAA_DISABLED)
	root.positional_shadow_atlas_size = 1024 * (1 + lv)


## Deterministic camera pose along the fixed path, u in 0..1.
func _camera_at(u: float) -> void:
	var a: float = u * TAU
	_camera.position = Vector3(cos(a) * 30.0, 8.0 + 3.0 * sin(a * 2.0), sin(a) * 30.0)
	_camera.look_at(Vector3(0.0, 2.0, 0.0))


# ------------------------------------------------------------------ measurement

func _compile_total() -> int:
	var total: int = 0
	for info in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		total += int(RenderingServer.get_rendering_info(info))
	return total


func _run_level(lv: int, seconds: float, shots: int) -> Dictionary:
	_apply_level(lv)
	for p in _particles:
		p.visible = true
	var vp: RID = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	_logger.reset()
	var compiles_start: int = _compile_total()
	var compiles_warm: int = compiles_start
	var frame_ms: PackedFloat64Array = PackedFloat64Array()
	var gpu_ms: PackedFloat64Array = PackedFloat64Array()
	var start: int = Time.get_ticks_usec()
	var last: int = start
	var frame: int = 0
	while true:
		await process_frame
		var now: int = Time.get_ticks_usec()
		var elapsed: float = float(now - start) / 1000000.0
		if elapsed >= seconds:
			break
		_camera_at(elapsed / seconds)
		if frame == WARMUP_FRAMES:
			compiles_warm = _compile_total()
		if frame >= WARMUP_FRAMES:
			frame_ms.append(float(now - last) / 1000.0)
			gpu_ms.append(float(RenderingServer.viewport_get_measured_render_time_gpu(vp)))
		last = now
		frame += 1
	var compiles_end: int = _compile_total()
	var checksums: Array[String] = []
	if not _headless:
		for p in _particles:
			p.visible = false
		for k in shots:
			_camera_at(float(k) / float(maxi(shots, 1)))
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var h: String = MatrixDb.dhash(root.get_texture().get_image())
			if not h.is_empty():
				checksums.append(h)
	RenderingServer.viewport_set_measure_render_time(vp, false)
	return {
		"level": lv,
		"frames": frame_ms.size(),
		"frame_ms": _stats(frame_ms),
		"gpu_ms": _stats(gpu_ms),
		"pipeline_compiles": compiles_end - compiles_start,
		"pipeline_compiles_after_warmup": compiles_end - compiles_warm,
		"checksums": checksums,
		"errors": _logger.errors,
		"error_samples": _logger.samples.duplicate(),
	}


static func _stats(vals: PackedFloat64Array) -> Dictionary:
	if vals.is_empty():
		return {"avg": 0.0, "p50": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0}
	var a: PackedFloat64Array = vals.duplicate()
	a.sort()
	var total: float = 0.0
	for v in a:
		total += v
	return {
		"avg": total / float(a.size()),
		"p50": _pct(a, 50.0), "p95": _pct(a, 95.0), "p99": _pct(a, 99.0),
		"max": a[a.size() - 1],
	}


static func _pct(sorted_vals: PackedFloat64Array, p: float) -> float:
	var pos: float = p / 100.0 * float(sorted_vals.size() - 1)
	var lo: int = int(floor(pos))
	var hi: int = mini(lo + 1, sorted_vals.size() - 1)
	return lerpf(sorted_vals[lo], sorted_vals[hi], pos - float(lo))


static func _or_unknown(s: String) -> String:
	return s if not s.strip_edges().is_empty() else "unknown"
