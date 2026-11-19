extends Node3D
class_name CgameFluidBody3D
## Attach as a direct child of a RigidBody3D to opt it into fluid forces.
##
## Sample offsets are expressed in the RigidBody3D's local coordinates.
## Each sample carries an equal share of displaced_volume and drag_area.
## This is a multi-sphere approximation, not exact mesh clipping.

@export_range(0.001, 100000.0, 0.001, "or_greater") var displaced_volume: float = 1.0
@export_range(0.001, 10000.0, 0.001, "or_greater") var drag_area: float = 1.0
@export_range(0.001, 100.0, 0.001, "or_greater") var sample_radius: float = 0.5
@export_range(0.001, 100.0, 0.001, "or_greater") var angular_drag_radius: float = 0.5
@export var sample_offsets: Array[Vector3] = [Vector3(-0.5, 0.0, 0.0), Vector3(0.5, 0.0, 0.0)]


static func find_for(body: RigidBody3D) -> CgameFluidBody3D:
	for child in body.get_children():
		if child is CgameFluidBody3D:
			return child as CgameFluidBody3D
	return null


func get_offsets() -> Array[Vector3]:
	if not sample_offsets.is_empty():
		return sample_offsets
	var fallback: Array[Vector3] = [Vector3.ZERO]
	return fallback
