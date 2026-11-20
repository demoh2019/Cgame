extends GPUParticles3D
## Raindrop splashes on the ground around the player (RDR2 / Ghost of Tsushima):
## in a downpour the ground "boils" with tiny bouncing droplets. One camera-local
## GPU emitter on a flat box at the player's ground height; density follows rain.

const AMOUNTS := [0, 120, 260, 420]


## Splash density (0..1) for rain intensity; drizzle barely splashes.
static func density(storm: float, sheltered: bool) -> float:
	if sheltered:
		return 0.0
	return clampf((storm - 0.25) / 0.6, 0.0, 1.0)


func _init() -> void:
	amount = 260
	lifetime = 0.35
	emitting = false
	local_coords = false
	visibility_aabb = AABB(Vector3(-14, -2, -14), Vector3(28, 4, 28))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(12, 0.05, 12)
	pm.direction = Vector3.UP
	pm.spread = 35.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(0.85, 0.9, 1.0, 0.55))
	fade.set_color(1, Color(0.85, 0.9, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	process_material = pm
	var drop := QuadMesh.new()
	drop.size = Vector2(0.025, 0.05)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = m
	draw_pass_1 = drop
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func update_view(ground_center: Vector3, storm: float, sheltered: bool, level: int) -> void:
	var cap: int = AMOUNTS[clampi(level, 0, 3)]
	var d: float = density(storm, sheltered)
	if cap == 0 or d <= 0.01:
		emitting = false
		return
	if amount != cap:
		amount = cap
	global_position = ground_center + Vector3(0, 0.05, 0)
	amount_ratio = d
	emitting = true
