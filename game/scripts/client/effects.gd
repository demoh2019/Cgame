extends Node3D
const RainVfx = preload("res://scripts/client/rain_vfx.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const SnowVfx = preload("res://scripts/client/snow_vfx.gd")
const PoolScript = preload("res://addons/runtime_pool/node_pool.gd")
const BurstScene = preload("res://scripts/client/pooled_burst.tscn")
const FxPolicy = preload("res://scripts/client/fx_scalability_policy.gd")

## Short-lived particle effects (hits, deaths, pickups, level ups, dust), the rain that follows the camera, and the life
## of the wilds around the player: pollen drifting in the sun, butterflies, leaves falling in the forest, fireflies at night.

var _rain: Node3D
var _rain_quality := -1
var _snow # SnowVfx (GPUParticles3D)
var _dust_timer := 0.0
var _pollen: CPUParticles3D
var _butterflies: CPUParticles3D
var _leaves: CPUParticles3D
var _fireflies: CPUParticles3D
var _burst_pool # Native SceneNodePool or stock-compatible script fallback.
var _burst_pool_budgeted := false
var _native_fx_budget: Object = null
var _pending_bursts: Array[Dictionary] = []
var last_fx_budget_stats: Dictionary = {"requested": 0, "rendered": 0, "dropped": 0, "native": false}
const MAX_PENDING_BURSTS := 256

const BUTTERFLY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D wings : source_color, filter_linear_mipmap;
void vertex() {
	// Wings beat: the quad (lying flat, seen from above) folds toward its body line and opens again.
	float beat = abs(sin(TIME * 17.0 + MODEL_MATRIX[3].x * 1.7 + MODEL_MATRIX[3].z * 2.3));
	VERTEX.x *= mix(0.2, 1.0, beat);
	VERTEX.y += abs(VERTEX.x) * (1.0 - beat) * 0.8;
}
void fragment() {
	vec4 t = texture(wings, UV);
	ALBEDO = t.rgb * COLOR.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""


func _ready() -> void:
	# Niagara / Unity VFX-style scalability: only one precipitation emitter
	# follows the camera; GPU on modern renderers, bounded CPU on older GL.
	_rain = RainVfx.create(str(RenderingServer.get_current_rendering_method()))
	add_child(_rain)
	_snow = SnowVfx.new()
	add_child(_snow)
	# Use the native Cgame engine pool; stock Godot keeps the script fallback.
	_burst_pool = ClassDB.instantiate("SceneNodePool") if ClassDB.class_exists("SceneNodePool") else PoolScript.new()
	_burst_pool.name = "BurstPool"
	_burst_pool.template = BurstScene
	_burst_pool.prewarm_count = 12
	_burst_pool.max_idle = 24
	_burst_pool.max_active = 48
	# Avoid instantiating the whole emitter cache in one _ready() callback.
	# Older native engine builds keep their legacy prewarm behavior.
	_burst_pool_budgeted = _burst_pool.has_method("maintain_residency")
	_burst_pool.prewarm_on_ready = not _burst_pool_budgeted
	add_child(_burst_pool)
	if ClassDB.class_exists("SignificanceBudgetPlanner"):
		var planner: Object = ClassDB.instantiate("SignificanceBudgetPlanner")
		if planner != null and planner.has_method("select_effects"):
			_native_fx_budget = planner
	_build_ambience()

## A soft round dot, white with an alpha falloff, for pollen and fireflies.
static func _dot_texture() -> ImageTexture:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d: float = Vector2(float(x) - 15.5, float(y) - 15.5).length() / 15.5
			image.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 1.6))
	return ImageTexture.create_from_image(image)


## Two pairs of rounded wings around a dark body, white so the particle colour tints them.
static func _wing_texture() -> ImageTexture:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var p := Vector2(float(x) - 31.5, float(y) - 31.5)
			var upper: float = Vector2((absf(p.x) - 14.0) / 13.0, (p.y + 7.0) / 12.0).length()
			var lower: float = Vector2((absf(p.x) - 11.0) / 9.0, (p.y - 10.0) / 9.0).length()
			var color := Color(0, 0, 0, 0)
			if upper < 1.0 or lower < 1.0:
				var edge: float = 1.0 - minf(upper, lower)
				color = Color(1, 1, 1, 1).lerp(Color(0.25, 0.2, 0.18, 1), 0.0 if edge > 0.18 else 0.7)
			if absf(p.x) < 2.0 and absf(p.y) < 16.0:
				color = Color(0.15, 0.12, 0.1, 1)
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


static func _glow_material(texture: Texture2D, color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	material.albedo_color = color
	return material


func _ambient_emitter(amount: int, lifetime: float, extents: Vector3) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.preprocess = lifetime
	particles.local_coords = false
	particles.emitting = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = extents
	particles.gravity = Vector3.ZERO
	add_child(particles)
	return particles


func _build_ambience() -> void:
	var dot := _dot_texture()
	# Pollen and seeds drifting in the sunlight: tiny, warm, slowly rising and falling.
	_pollen = _ambient_emitter(160, 9.0, Vector3(28.0, 2.5, 22.0))
	var pollen_quad := QuadMesh.new()
	pollen_quad.size = Vector2(0.09, 0.09)
	pollen_quad.material = _glow_material(dot, Color(1.0, 0.95, 0.75, 0.75))
	_pollen.mesh = pollen_quad
	_pollen.direction = Vector3(1.0, 0.15, 0.4)
	_pollen.spread = 60.0
	_pollen.initial_velocity_min = 0.15
	_pollen.initial_velocity_max = 0.5
	_pollen.color_ramp = _fade_ramp(Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.9))
	# Butterflies over the meadows: flat wings seen from above, beating, in a handful of colours.
	_butterflies = _ambient_emitter(16, 7.0, Vector3(24.0, 0.6, 18.0))
	var wing_quad := PlaneMesh.new()
	wing_quad.size = Vector2(0.34, 0.34)
	var wing_material := ShaderMaterial.new()
	var wing_shader := Shader.new()
	wing_shader.code = BUTTERFLY_SHADER
	wing_material.shader = wing_shader
	wing_material.set_shader_parameter("wings", _wing_texture())
	wing_quad.material = wing_material
	_butterflies.mesh = wing_quad
	_butterflies.particle_flag_rotate_y = true
	_butterflies.angle_min = -180.0
	_butterflies.angle_max = 180.0
	_butterflies.direction = Vector3(1.0, 0.1, 0.0)
	_butterflies.spread = 180.0
	_butterflies.initial_velocity_min = 0.6
	_butterflies.initial_velocity_max = 1.4
	_butterflies.tangential_accel_min = -1.2
	_butterflies.tangential_accel_max = 1.2
	var palette := Gradient.new()
	palette.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	palette.colors = PackedColorArray([Color(1.0, 0.95, 0.85), Color(1.0, 0.8, 0.3), Color(0.55, 0.75, 1.0), Color(1.0, 0.55, 0.35), Color(0.95, 0.95, 0.6)])
	_butterflies.color_initial_ramp = palette
	# Leaves drifting down in the forest, turning as they fall.
	_leaves = _ambient_emitter(50, 7.0, Vector3(26.0, 1.0, 20.0))
	var leaf := QuadMesh.new()
	leaf.size = Vector2(0.16, 0.11)
	var leaf_material := StandardMaterial3D.new()
	leaf_material.albedo_texture = dot
	leaf_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	leaf_material.alpha_scissor_threshold = 0.3
	leaf_material.vertex_color_use_as_albedo = true
	leaf_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaf.material = leaf_material
	_leaves.mesh = leaf
	_leaves.direction = Vector3(0.3, -1.0, 0.2)
	_leaves.spread = 25.0
	_leaves.initial_velocity_min = 0.5
	_leaves.initial_velocity_max = 0.9
	_leaves.angular_velocity_min = -160.0
	_leaves.angular_velocity_max = 160.0
	_leaves.angle_min = -180.0
	_leaves.angle_max = 180.0
	var autumn := Gradient.new()
	autumn.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	autumn.colors = PackedColorArray([Color(0.45, 0.6, 0.2), Color(0.75, 0.62, 0.22), Color(0.6, 0.38, 0.18)])
	_leaves.color_initial_ramp = autumn
	# Fireflies at night: green-gold sparks that pulse, bright enough to catch the glow.
	_fireflies = _ambient_emitter(70, 6.0, Vector3(24.0, 1.4, 18.0))
	var spark := QuadMesh.new()
	spark.size = Vector2(0.16, 0.16)
	spark.material = _glow_material(dot, Color(1.0, 1.0, 1.0, 1.0))
	_fireflies.mesh = spark
	_fireflies.direction = Vector3(0.0, 0.3, 1.0)
	_fireflies.spread = 180.0
	_fireflies.initial_velocity_min = 0.2
	_fireflies.initial_velocity_max = 0.6
	var blink := Gradient.new()
	blink.offsets = PackedFloat32Array([0.0, 0.15, 0.3, 0.45, 0.6, 0.75, 1.0])
	blink.colors = PackedColorArray([Color(1.6, 1.8, 0.6, 0.0), Color(1.6, 1.8, 0.6, 1.0), Color(1.6, 1.8, 0.6, 0.15), Color(1.6, 1.8, 0.6, 1.0), Color(1.6, 1.8, 0.6, 0.2), Color(1.6, 1.8, 0.6, 0.9), Color(1.6, 1.8, 0.6, 0.0)])
	_fireflies.color_ramp = blink


static func _fade_ramp(edge: Color, middle: Color) -> Gradient:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	ramp.colors = PackedColorArray([edge, middle, middle, edge])
	return ramp


## The life around the player: `ground` is where they stand, `daylight` 0..1, `storm` 0..1, `biome` where they are.
func update_ambience(ground: Vector3, daylight: float, storm: float, biome: String) -> void:
	var calm: bool = storm < 0.3
	var wild: bool = biome != "beach" and biome != "mountain"
	_pollen.emitting = calm and daylight > 0.35
	_pollen.global_position = ground + Vector3(0, 2.0, 0)
	_butterflies.emitting = calm and daylight > 0.45 and (biome == "plains" or biome == "forest")
	_butterflies.global_position = ground + Vector3(0, 1.0, 0)
	_leaves.emitting = biome == "forest" or biome == "swamp"
	_leaves.global_position = ground + Vector3(0, 6.0, 0)
	_fireflies.emitting = calm and daylight < 0.25 and wild
	_fireflies.global_position = ground + Vector3(0, 1.0, 0)


## Rain around `center` while `intensity` > 0.
func update_rain(center: Vector3, intensity: float, snow_fraction: float = 0.0) -> void:
	# The quality tier is changed rarely; GPU amount_ratio varies smoothly
	# with weather and does not restart an active storm emitter.
	if _rain == null:
		return
	var tier: int = GraphicsQuality.level()
	if tier != _rain_quality:
		RainVfx.apply_quality(_rain, tier)
		_rain_quality = tier
	# Above the snow line the same storm falls as snow instead of rain.
	var snow: float = clampf(snow_fraction, 0.0, 1.0)
	RainVfx.update(_rain, center, intensity * (1.0 - snow))
	if _snow != null:
		_snow.update_view(center, intensity * snow, tier)


## A flat ring on the ground that widens and fades: a pulse of healing, a shock wave, a flash.
func ring(position: Vector3, color: Color, radius: float = 4.0, seconds: float = 0.7) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.86
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = color
	torus.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = torus
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	instance.global_position = position + Vector3(0, 0.15, 0)
	instance.scale = Vector3(0.3, 0.05, 0.3)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(instance, "scale", Vector3(radius, 0.05 * radius, radius), seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, seconds)
	tween.chain().tween_callback(instance.queue_free)


## Frame-gather visual descriptors before acquiring pooled particle nodes.
## Damage, audio, network event delivery and server authority are unaffected.
func _process(_delta: float) -> void:
	if _burst_pool_budgeted and is_instance_valid(_burst_pool):
		# At most 1-2 PackedScene instantiations or frees per render frame.
		# Active particle emitters count toward this target and finish naturally.
		_burst_pool.call("maintain_residency",
			FxPolicy.pool_resident_target(GraphicsQuality.level()),
			FxPolicy.pool_changes_per_frame(GraphicsQuality.level()))
	flush_bursts()


func pending_burst_count() -> int:
	return _pending_bursts.size()


func flush_bursts() -> void:
	if _pending_bursts.is_empty():
		return
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var viewer: Vector3 = camera.global_position if camera != null else Vector3.ZERO
	var distances := PackedFloat64Array()
	var priorities := PackedByteArray()
	var categories := PackedByteArray()
	var visible := PackedByteArray()
	for effect in _pending_bursts:
		distances.append(viewer.distance_to(effect["position"]) if camera != null else 0.0)
		priorities.append(int(effect["priority"]))
		categories.append(int(effect["group"]))
		# No camera during headless tests means all candidates are equivalent
		# on visibility. Do not cull a critical event merely for being behind us.
		visible.append(1 if camera == null or camera.is_position_in_frustum(effect["position"]) else 0)
	var chosen: PackedInt32Array = FxPolicy.select_visible_ranged_indices(
		distances, priorities, categories, visible, GraphicsQuality.level(), _native_fx_budget)
	var actual: int = 0
	for index in chosen:
		if _emit_burst(_pending_bursts[index]):
			actual += 1
	last_fx_budget_stats = {
		"requested": _pending_bursts.size(),
		"rendered": actual,
		"dropped": _pending_bursts.size() - actual,
		"native": _native_fx_budget != null,
	}
	_pending_bursts.clear()


func _emit_burst(effect: Dictionary) -> bool:
	if _burst_pool == null:
		return false
	var particles: CPUParticles3D = _burst_pool.acquire(self) as CPUParticles3D
	if particles == null:
		return false
	particles.global_position = effect["position"]
	particles.call("configure_burst", effect["color"], effect["count"],
		effect["speed"], effect["lifetime"], effect["size"],
		effect["gravity"], effect["up"])
	return true


## A puff of particles: `color` fades out, `speed` is the initial speed, `size` the particle size in meters.
func burst(position: Vector3, color: Color, count: int = 14, speed: float = 3.0, lifetime: float = 0.6, size: float = 0.14, gravity: float = 7.0, up: float = 0.6, priority: int = 1, group: int = 1) -> void:
	if not position.is_finite():
		return
	var effect: Dictionary = {
		"position": position, "color": color, "count": count,
		"speed": speed, "lifetime": lifetime, "size": size,
		"gravity": gravity, "up": up,
		"priority": clampi(priority, 0, 3), "group": clampi(group, 0, 3),
	}
	if _pending_bursts.size() >= MAX_PENDING_BURSTS:
		# Protect critical feedback from already queued cosmetic foot dust.
		var least: int = -1
		for i in _pending_bursts.size():
			if int(_pending_bursts[i]["priority"]) < int(effect["priority"]):
				if least < 0 or int(_pending_bursts[i]["priority"]) < int(_pending_bursts[least]["priority"]):
					least = i
		if least < 0:
			return
		_pending_bursts[least] = effect
	else:
		_pending_bursts.append(effect)



func hit_zombie(position: Vector3) -> void:
	burst(position, Color(0.45, 0.62, 0.2), 12, 3.2, 0.55, 0.09, 7.0, 0.6, 2, 1)


func zombie_died(position: Vector3) -> void:
	burst(position, Color(0.4, 0.55, 0.2), 28, 4.5, 0.9, 0.12, 7.0, 0.6, 3, 2)
	burst(position, Color(0.35, 0.33, 0.3), 12, 2.0, 1.2, 0.3, 1.0, 0.2)


func hit_player(position: Vector3) -> void:
	burst(position, Color(0.78, 0.1, 0.1), 14, 3.4, 0.5, 0.08, 7.0, 0.6, 3, 2)


func muzzle_flash(position: Vector3) -> void:
	burst(position, Color(1.0, 0.85, 0.35), 8, 5.0, 0.12, 0.1, 0.0, 0.0, 2, 2)


func gathered(position: Vector3, color: Color) -> void:
	burst(position, color, 14, 3.0, 0.7, 0.07)


func level_up(position: Vector3) -> void:
	burst(position, Color(1.0, 0.85, 0.3), 36, 4.0, 1.1, 0.07, -1.5, 1.0, 3, 3)


func loot(position: Vector3) -> void:
	burst(position, Color(1.0, 0.9, 0.5), 16, 2.5, 0.8, 0.05, -0.5, 1.0, 2, 2)


## Dust kicked up by a runner; call every frame with the measured speed.
func footsteps(position: Vector3, speed: float, delta: float) -> void:
	if speed < 4.0:
		_dust_timer = 0.0
		return
	_dust_timer -= delta
	if _dust_timer <= 0.0:
		_dust_timer = 0.16
		burst(position + Vector3(0, 0.1, 0), Color(0.55, 0.5, 0.4, 0.5), 3, 0.9, 0.4, 0.07, -0.3, 0.3, 0, 0)
