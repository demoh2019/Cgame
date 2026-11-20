extends RefCounted
## Camera-local rain rendering, shared by every multiplayer client.
## GPU simulation on modern renderers, conservative CPU fallback on GL.
## No gameplay collision, networking, resource generation or world writes.

const GPU_COUNTS := [160, 460, 850, 1350]
const CPU_COUNTS := [55, 110, 210, 320]
const LIFE := 0.9
const BOX := Vector3(26.0, 0.5, 26.0)
const BOUNDS := AABB(Vector3(-27.0, -39.0, -27.0), Vector3(54.0, 43.0, 54.0))


static func use_gpu(rendering_method: String) -> bool:
	return rendering_method == "forward_plus" or rendering_method == "mobile"


## Bound resident particle storage to a quality tier, not to the per-frame
## weather value. Modifying a GPU emitter's amount while active restarts it.
static func budget(level: int, rendering_method: String) -> Dictionary:
	var tier := clampi(level, 0, 3)
	var gpu := use_gpu(rendering_method)
	return {
		"gpu": gpu,
		"amount": GPU_COUNTS[tier] if gpu else CPU_COUNTS[tier],
		"lifetime": LIFE,
		"box": BOX,
	}


## Light drizzle yields few streaks, full storm uses the tier's entire cap.
static func density(intensity: float) -> float:
	if not is_finite(intensity):
		return 0.0
	return clampf((intensity - 0.035) / 0.83, 0.0, 1.0)


static func _streak_mesh() -> QuadMesh:
	# A camera-facing quad is two triangles, not the 12 triangles of a box.
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.018, 0.87)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(0.73, 0.84, 0.98, 0.5)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mesh.material = material
	return mesh


static func _fade_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.7, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.95),
		Color(1.0, 1.0, 1.0, 0.85),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	return gradient


static func create(rendering_method: String) -> Node3D:
	var mesh := _streak_mesh()
	if use_gpu(rendering_method):
		var particles := GPUParticles3D.new()
		particles.name = "CameraRainGPU"
		particles.amount = GPU_COUNTS[1]
		particles.lifetime = LIFE
		particles.preprocess = LIFE
		particles.fixed_fps = 30
		particles.interpolate = true
		particles.one_shot = false
		particles.local_coords = false
		particles.emitting = false
		particles.draw_pass_1 = mesh
		particles.visibility_aabb = BOUNDS
		particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		process.emission_box_extents = BOX
		process.direction = Vector3(0.12, -1.0, 0.05)
		process.spread = 3.0
		process.gravity = Vector3.ZERO
		process.initial_velocity_min = 30.0
		process.initial_velocity_max = 38.0
		var ramp := GradientTexture1D.new()
		ramp.gradient = _fade_gradient()
		process.color_ramp = ramp
		particles.process_material = process
		return particles
	var fallback := CPUParticles3D.new()
	fallback.name = "CameraRainCPU"
	fallback.amount = CPU_COUNTS[1]
	fallback.lifetime = LIFE
	fallback.preprocess = LIFE
	fallback.one_shot = false
	fallback.local_coords = false
	fallback.emitting = false
	fallback.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fallback.emission_box_extents = BOX
	fallback.direction = Vector3(0.12, -1.0, 0.05)
	fallback.spread = 3.0
	fallback.gravity = Vector3.ZERO
	fallback.initial_velocity_min = 30.0
	fallback.initial_velocity_max = 38.0
	fallback.color_ramp = _fade_gradient()
	fallback.mesh = mesh
	fallback.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fallback.visibility_aabb = BOUNDS
	return fallback


## Called only when the active profile changes, not each weather frame.
static func apply_quality(particles: Node3D, level: int) -> void:
	if particles == null:
		return
	var backend := "forward_plus" if particles is GPUParticles3D else "gl_compatibility"
	var count: int = int(budget(level, backend)["amount"])
	if particles is GPUParticles3D:
		var gpu := particles as GPUParticles3D
		if gpu.amount != count:
			gpu.amount = count
	elif particles is CPUParticles3D:
		var cpu := particles as CPUParticles3D
		if cpu.amount != count:
			cpu.amount = count


## Position follows the camera; existing particles stay in world coordinates,
## so sprinting never drags all the streaks along with the player.
static func update(particles: Node3D, center: Vector3, intensity: float) -> void:
	if particles == null:
		return
	particles.global_position = center + Vector3(0.0, 18.0, 0.0)
	var share := density(intensity)
	if particles is GPUParticles3D:
		var gpu := particles as GPUParticles3D
		gpu.amount_ratio = share
		gpu.emitting = share > 0.001
	elif particles is CPUParticles3D:
		var cpu := particles as CPUParticles3D
		# Older GL devices use fewer CPU particles. Alpha alone makes a
		# drizzle lighter instead of rebuilding CPU emission buffers per frame.
		cpu.color = Color(1.0, 1.0, 1.0, maxf(0.12, share))
		cpu.emitting = share > 0.001
