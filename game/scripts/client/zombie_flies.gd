extends Node3D
## Flies buzzing around the nearest zombies (DayZ / Days Gone rot detail): a small
## pool of swirling particle swarms re-assigned to the closest infected 5x a
## second. Daytime and dry weather only; off on Performance/Balanced.

const POOL := 4
const RADIUS := 16.0

var _swarms: Array[CPUParticles3D] = []
var _targets: Array = []
var _pick_left := 0.0


static func swarm_count(level: int, daylight: float, storm: float) -> int:
	if level < 2 or daylight < 0.3 or storm > 0.3:
		return 0
	return POOL if level >= 3 else 2


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.025)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.03, 0.03, 0.03)
	quad.material = m
	for i in POOL:
		var p := CPUParticles3D.new()
		p.amount = 10
		p.lifetime = 2.5
		p.preprocess = 2.0
		p.local_coords = true
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.35
		p.direction = Vector3(1, 0, 0)
		p.spread = 180.0
		p.initial_velocity_min = 0.6
		p.initial_velocity_max = 1.2
		p.gravity = Vector3.ZERO
		p.tangential_accel_min = 2.5
		p.tangential_accel_max = 4.0
		p.radial_accel_min = -2.0 # Pulled back towards the head: a tight, buzzing cloud.
		p.radial_accel_max = -1.0
		p.mesh = quad
		p.emitting = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_swarms.append(p)
		_targets.append(null)


func update_view(entities: Node, player: Vector3, daylight: float, storm: float, level: int, delta: float) -> void:
	var want: int = swarm_count(level, daylight, storm)
	_pick_left -= delta
	if _pick_left <= 0.0:
		_pick_left = 0.2
		var near: Array = [] if want == 0 or entities == null else entities.call("nearest_of_kind", player, "zombie", want, RADIUS)
		for i in POOL:
			_targets[i] = near[i] if i < near.size() else null
	for i in POOL:
		var target = _targets[i]
		var swarm := _swarms[i]
		if target == null or not is_instance_valid(target):
			swarm.emitting = false
			continue
		swarm.global_position = (target as Node3D).global_position + Vector3(0, 1.75, 0)
		swarm.emitting = true
