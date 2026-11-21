extends CPUParticles3D
## A one-shot VFX emitter with resources allocated only once per pooled instance.

var _pool: Node
var _remaining: float = 0.0
var _sphere: SphereMesh
var _material: StandardMaterial3D


func on_pool_created() -> void:
	if _sphere != null:
		return
	emitting = false
	one_shot = true
	explosiveness = 0.95
	spread = 80.0
	scale_amount_min = 0.7
	scale_amount_max = 1.3
	_sphere = SphereMesh.new()
	_sphere.radial_segments = 6
	_sphere.rings = 3
	_material = StandardMaterial3D.new()
	_sphere.material = _material
	mesh = _sphere
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	color_ramp = fade
	set_process(false)


func on_pool_acquired(pool: Node) -> void:
	_pool = pool
	_remaining = 0.0
	emitting = false
	set_process(false)


func configure_burst(color: Color, count: int, speed: float, seconds: float, size: float, gravity_strength: float, upward: float) -> void:
	on_pool_created()
	amount = maxi(count, 1)
	lifetime = maxf(seconds, 0.01)
	direction = Vector3(0.0, upward, 0.0)
	initial_velocity_min = speed * 0.5
	initial_velocity_max = speed
	gravity = Vector3(0.0, -gravity_strength, 0.0)
	_sphere.radius = maxf(size, 0.001)
	_sphere.height = maxf(size, 0.001) * 2.0
	_material.albedo_color = color
	var glow: bool = color.get_luminance() > 0.7
	_material.emission_enabled = glow
	_material.emission = color
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if glow else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_remaining = lifetime + 0.5
	emitting = true
	restart()
	set_process(true)


func on_pool_released() -> void:
	emitting = false
	set_process(false)
	_remaining = 0.0
	_pool = null


func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining > 0.0:
		return
	if is_instance_valid(_pool):
		_pool.call("release", self)
	else:
		queue_free()
