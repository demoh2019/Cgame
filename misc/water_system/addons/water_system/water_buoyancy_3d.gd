extends Node3D
class_name WaterBuoyancy3D
## Place under a RigidBody3D. Water samples generate upward forces at
## local float points, with optional velocity drag.

@export var enabled: bool = true
@export var water_surface_path: NodePath
@export var sample_points: PackedVector3Array = PackedVector3Array([
	Vector3(-0.5, 0, -0.5),
	Vector3(0.5, 0, -0.5),
	Vector3(-0.5, 0, 0.5),
	Vector3(0.5, 0, 0.5)
])
@export_range(0.0, 100000.0, 1.0) var lift_per_meter: float = 35.0
@export_range(0.01, 100.0, 0.01) var max_submergence: float = 2.0
@export_range(0.0, 1000.0, 0.1) var water_drag: float = 4.0


func compute_point_force(
		world_position: Vector3, water_height: float, velocity: Vector3) -> Vector3:
	if not world_position.is_finite() or not is_finite(water_height) or not velocity.is_finite():
		return Vector3.ZERO
	if not is_finite(lift_per_meter) or not is_finite(max_submergence) or not is_finite(water_drag):
		return Vector3.ZERO
	if lift_per_meter < 0.0 or max_submergence <= 0.0 or water_drag < 0.0:
		return Vector3.ZERO
	var depth := clampf(water_height - world_position.y, 0.0, max_submergence)
	if depth <= 0.0:
		return Vector3.ZERO
	var ratio := depth / max_submergence
	var lift := Vector3.UP * lift_per_meter * depth
	return lift - velocity * water_drag * ratio


func _physics_process(_delta: float) -> void:
	if not enabled:
		return
	var body := get_parent() as RigidBody3D
	if body == null or water_surface_path.is_empty():
		return
	var water := get_node_or_null(water_surface_path) as WaterSurface3D
	if water == null:
		return
	for local_point in sample_points:
		var world_point: Vector3 = to_global(local_point)
		var sample: Dictionary = water.sample_at(world_point)
		if not sample["ok"]:
			continue
		var offset := world_point - body.global_position
		var velocity_at_point := body.linear_velocity + body.angular_velocity.cross(offset)
		var force := compute_point_force(world_point, float(sample["height"]), velocity_at_point)
		if not force.is_zero_approx():
			body.apply_force(force, offset)
