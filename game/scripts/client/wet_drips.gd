extends Node3D
## After-rain drips (RDR2 detail): when you leave a downpour, water keeps
## dripping from clothes and hair for about a minute, thinning out as you dry.
## CPU particles on the local character only; off on Performance.

const DRY_SECONDS := 60.0

var _soak := 0.0 # Seconds of dripping left.
var _drops: CPUParticles3D


## Soak timer update: rain (storm > 0.3, not sheltered) refills it, dry air drains it.
static func next_soak(soak: float, storm: float, sheltered: bool, delta: float) -> float:
	if storm > 0.3 and not sheltered:
		return DRY_SECONDS
	return maxf(0.0, soak - delta)


## Drips only once the rain has stopped (or you are under cover) and you are still wet.
static func drip_rate(soak: float, storm: float, sheltered: bool) -> float:
	if soak <= 0.0 or (storm > 0.3 and not sheltered):
		return 0.0
	return clampf(soak / DRY_SECONDS, 0.0, 1.0)


func _ready() -> void:
	_drops = CPUParticles3D.new()
	_drops.amount = 24
	_drops.lifetime = 0.7
	_drops.emitting = false
	_drops.local_coords = false
	_drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_drops.emission_box_extents = Vector3(0.28, 0.6, 0.18)
	_drops.position.y = 1.0
	_drops.direction = Vector3.DOWN
	_drops.spread = 5.0
	_drops.initial_velocity_min = 0.2
	_drops.initial_velocity_max = 0.6
	_drops.gravity = Vector3(0, -9.8, 0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, 0.05)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	quad.material = m
	_drops.mesh = quad
	_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_drops)


func update_view(storm: float, sheltered: bool, level: int, delta: float) -> void:
	_soak = next_soak(_soak, storm, sheltered, delta)
	var rate: float = drip_rate(_soak, storm, sheltered) if level >= 1 else 0.0
	_drops.emitting = rate > 0.02
	if _drops.emitting:
		_drops.color = Color(0.8, 0.88, 1.0, 0.55 * rate) # CPUParticles3D has no amount_ratio.
