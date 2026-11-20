extends Node3D
## Lightweight procedural bike. Visual only: movement, ownership and damage stay on GameServer.
## No external asset pack or collision body is required.

const WHEEL_RADIUS := 0.43
const WHEEL_OFFSET := 0.72

var _wheel_pivots: Array[Node3D] = []


func _ready() -> void:
	build()
	visible = false


func build() -> void:
	if not _wheel_pivots.is_empty():
		return
	var rubber := _material(Color(0.085, 0.10, 0.12))
	var steel := _material(Color(0.57, 0.65, 0.72))
	var orange := _material(Color(0.93, 0.44, 0.13))
	var leather := _material(Color(0.19, 0.15, 0.13))
	# Each wheel is a pivot so the ring and hub spin together while the frame stays still.
	for side in [-1, 1]:
		var wheel := Node3D.new()
		wheel.name = "WheelRear" if side < 0 else "WheelFront"
		wheel.position = Vector3(0, WHEEL_RADIUS, float(side) * WHEEL_OFFSET)
		add_child(wheel)
		_wheel_pivots.append(wheel)
		var tire := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.32
		torus.outer_radius = WHEEL_RADIUS
		tire.mesh = torus
		tire.material_override = rubber
		tire.rotation.z = PI / 2.0
		wheel.add_child(tire)
		var hub := MeshInstance3D.new()
		var hub_shape := CylinderMesh.new()
		hub_shape.top_radius = 0.095
		hub_shape.bottom_radius = 0.095
		hub_shape.height = 0.18
		hub.mesh = hub_shape
		hub.material_override = steel
		hub.rotation.z = PI / 2.0
		wheel.add_child(hub)
	var back := Vector3(0, WHEEL_RADIUS, -WHEEL_OFFSET)
	var front := Vector3(0, WHEEL_RADIUS, WHEEL_OFFSET)
	var crank := Vector3(0, 0.54, -0.05)
	var saddle_joint := Vector3(0, 1.04, -0.28)
	var steering_joint := Vector3(0, 1.09, 0.45)
	_beam(back, crank, 0.05, orange)
	_beam(crank, front, 0.05, orange)
	_beam(crank, saddle_joint, 0.05, orange)
	_beam(saddle_joint, steering_joint, 0.045, orange)
	_beam(steering_joint, crank, 0.045, orange)
	_beam(steering_joint, front, 0.042, steel)
	_beam(saddle_joint, saddle_joint + Vector3(0, 0.12, 0), 0.05, steel)
	_beam(steering_joint, steering_joint + Vector3(0, 0.17, 0.03), 0.045, steel)
	# Black seat and wide handlebar make the vehicle readable from the isometric camera.
	_beam(Vector3(0, 1.18, -0.28), Vector3(0, 1.18, -0.01), 0.10, leather)
	_beam(Vector3(-0.36, 1.25, 0.48), Vector3(0.36, 1.25, 0.48), 0.043, steel)


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.81
	return material


func _beam(a: Vector3, b: Vector3, radius: float, material: StandardMaterial3D) -> void:
	var direction := b - a
	if direction.length_squared() <= 0.0001:
		return
	var segment := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = radius
	tube.bottom_radius = radius
	tube.height = direction.length()
	tube.radial_segments = 6
	segment.mesh = tube
	segment.material_override = material
	segment.position = (a + b) * 0.5
	segment.quaternion = Quaternion(Vector3.UP, direction.normalized())
	add_child(segment)


func set_riding(riding: bool, speed: float = 0.0, delta: float = 0.0) -> void:
	visible = riding
	if not riding or not is_finite(speed) or not is_finite(delta) or speed <= 0.0 or delta <= 0.0:
		return
	# Animation reads measured visual displacement only; it does not affect physics.
	var rotation_amount := clampf(speed * delta / WHEEL_RADIUS, 0.0, 4.0)
	for pivot in _wheel_pivots:
		pivot.rotation.x = wrapf(pivot.rotation.x + rotation_amount, -PI, PI)


func wheel_count() -> int:
	return _wheel_pivots.size()
