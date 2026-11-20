extends Node3D
## Short-lived particle effects (hits, deaths, pickups, level ups, dust) and the rain that follows the camera.

var _rain: CPUParticles3D
var _rain_amount := 0.0
var _dust_timer := 0.0


func _ready() -> void:
	_rain = CPUParticles3D.new()
	_rain.amount = 700
	_rain.lifetime = 0.9
	_rain.preprocess = 0.9
	_rain.emitting = false
	_rain.local_coords = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(26.0, 0.5, 26.0)
	_rain.direction = Vector3(0.12, -1.0, 0.05)
	_rain.spread = 3.0
	_rain.gravity = Vector3.ZERO
	_rain.initial_velocity_min = 30.0
	_rain.initial_velocity_max = 38.0
	var streak := BoxMesh.new()
	streak.size = Vector3(0.012, 0.9, 0.012)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.75, 0.82, 0.92, 0.5)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak.material = material
	_rain.mesh = streak
	add_child(_rain)


## Rain around `center` while `intensity` > 0.
func update_rain(center: Vector3, intensity: float) -> void:
	_rain_amount = intensity
	_rain.emitting = intensity > 0.05
	_rain.global_position = center + Vector3(0, 18.0, 0)


## A puff of particles: `color` fades out, `speed` is the initial speed, `size` the particle size in meters.
func burst(position: Vector3, color: Color, count: int = 14, speed: float = 3.0, lifetime: float = 0.6, size: float = 0.14, gravity: float = 7.0, up: float = 0.6) -> void:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.amount = count
	particles.lifetime = lifetime
	particles.explosiveness = 0.95
	particles.direction = Vector3(0, up, 0)
	particles.spread = 80.0
	particles.initial_velocity_min = speed * 0.5
	particles.initial_velocity_max = speed
	particles.gravity = Vector3(0, -gravity, 0)
	particles.scale_amount_min = 0.7
	particles.scale_amount_max = 1.3
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = color.get_luminance() > 0.7
	material.emission = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if color.get_luminance() > 0.7 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mesh.material = material
	particles.mesh = mesh
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	particles.color_ramp = fade
	add_child(particles)
	particles.global_position = position
	particles.emitting = true
	get_tree().create_timer(lifetime + 0.5).timeout.connect(particles.queue_free)


func hit_zombie(position: Vector3) -> void:
	burst(position, Color(0.45, 0.62, 0.2), 12, 3.2, 0.55, 0.09)


func zombie_died(position: Vector3) -> void:
	burst(position, Color(0.4, 0.55, 0.2), 28, 4.5, 0.9, 0.12)
	burst(position, Color(0.35, 0.33, 0.3), 12, 2.0, 1.2, 0.3, 1.0, 0.2)


func hit_player(position: Vector3) -> void:
	burst(position, Color(0.78, 0.1, 0.1), 14, 3.4, 0.5, 0.08)


func muzzle_flash(position: Vector3) -> void:
	burst(position, Color(1.0, 0.85, 0.35), 8, 5.0, 0.12, 0.1, 0.0, 0.0)


func gathered(position: Vector3, color: Color) -> void:
	burst(position, color, 14, 3.0, 0.7, 0.07)


func level_up(position: Vector3) -> void:
	burst(position, Color(1.0, 0.85, 0.3), 36, 4.0, 1.1, 0.07, -1.5, 1.0)


func loot(position: Vector3) -> void:
	burst(position, Color(1.0, 0.9, 0.5), 16, 2.5, 0.8, 0.05, -0.5, 1.0)


## Dust kicked up by a runner; call every frame with the measured speed.
func footsteps(position: Vector3, speed: float, delta: float) -> void:
	if speed < 4.0:
		_dust_timer = 0.0
		return
	_dust_timer -= delta
	if _dust_timer <= 0.0:
		_dust_timer = 0.16
		burst(position + Vector3(0, 0.1, 0), Color(0.55, 0.5, 0.4, 0.5), 3, 0.9, 0.4, 0.07, -0.3, 0.3)
