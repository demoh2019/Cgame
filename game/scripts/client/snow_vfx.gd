extends GPUParticles3D
## Altitude snowfall (RDR2 mountain passes): above the terrain snow line the same
## weather falls as slow, swirling flakes instead of rain. One camera-following
## GPU emitter; amount_ratio follows weather so it never restarts mid-storm.

const SNOW_LINE_START := 82.0 # metres; matches the terrain snow cap blend (88..108).
const SNOW_LINE_FULL := 96.0
const AMOUNTS := [0, 400, 900, 1500] # per quality tier; Performance off


## 0 = rain, 1 = snow, from the ground height under the player.
static func snow_fraction(ground_height: float) -> float:
	return clampf((ground_height - SNOW_LINE_START) / (SNOW_LINE_FULL - SNOW_LINE_START), 0.0, 1.0)


func _init() -> void:
	amount = 900
	lifetime = 6.0
	preprocess = 3.0
	emitting = false
	local_coords = false
	visibility_aabb = AABB(Vector3(-25, -20, -25), Vector3(50, 40, 50))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 1, 22)
	pm.direction = Vector3.DOWN
	pm.spread = 10.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0, -0.6, 0)
	# Turbulence gives the lazy, swirling fall that separates snow from rain.
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.4
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	process_material = pm
	var flake := QuadMesh.new()
	flake.size = Vector2(0.06, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.95, 0.97, 1.0, 0.85)
	m.albedo_texture = _flake_texture()
	flake.material = m
	draw_pass_1 = flake
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _flake_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 16
	tex.height = 16
	return tex


func update_view(center: Vector3, intensity: float, level: int) -> void:
	var cap: int = AMOUNTS[clampi(level, 0, 3)]
	if cap == 0 or intensity <= 0.01:
		emitting = false
		return
	if amount != cap:
		amount = cap
	global_position = center + Vector3(0, 12.0, 0)
	amount_ratio = clampf(intensity, 0.0, 1.0)
	emitting = true
