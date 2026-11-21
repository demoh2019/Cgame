extends Node3D
## A driftwood raft under a survivor paddling across deep water: lashed logs that rock on the swell.

var _logs: Node3D
static var _wood: StandardMaterial3D
static var _rope: StandardMaterial3D


func _ready() -> void:
	if _wood == null:
		_wood = StandardMaterial3D.new()
		_wood.albedo_color = Color(0.46, 0.34, 0.22)
		_wood.roughness = 0.95
		_rope = StandardMaterial3D.new()
		_rope.albedo_color = Color(0.7, 0.62, 0.42)
	_logs = Node3D.new()
	add_child(_logs)
	for i in 5:
		var log := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.13 + 0.02 * float(i % 2)
		cyl.bottom_radius = cyl.top_radius
		cyl.height = 2.5 - 0.15 * float(i % 3)
		cyl.radial_segments = 8
		log.mesh = cyl
		log.material_override = _wood
		log.rotation.x = PI * 0.5
		log.position = Vector3(-0.56 + 0.28 * float(i), 0.0, 0.05 * float(i % 2))
		_logs.add_child(log)
	for z in [-0.8, 0.8]:
		var lash := MeshInstance3D.new()
		var band := BoxMesh.new()
		band.size = Vector3(1.5, 0.05, 0.08)
		lash.mesh = band
		lash.material_override = _rope
		lash.position = Vector3(0.0, 0.12, z)
		_logs.add_child(lash)
	visible = false


## Shown while paddling; rocks gently with time.
func set_rafting(on: bool) -> void:
	visible = on
	if on and _logs != null:
		var t: float = Time.get_ticks_msec() * 0.001
		_logs.rotation = Vector3(sin(t * 1.3) * 0.05, 0.0, cos(t * 1.1) * 0.06)
		_logs.position.y = sin(t * 1.7) * 0.05
