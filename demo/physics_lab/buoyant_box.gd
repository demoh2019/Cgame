extends RigidBody3D
## An optional *example* hydrodynamic force, not a built-in fluid solver.
## Uses an approximate submerged fraction for an axis-aligned box.

@export var water_surface_y: float = 2.6
@export var box_height: float = 1.4
@export var displaced_volume: float = 2.744
@export var fluid_density: float = 1.5
@export var water_drag: float = 2.0

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    # The station keeps the boxes axis-aligned: tilted boxes need an exact
    # clipped-volume calculation to be physically accurate.
    var center_y: float = state.transform.origin.y
    var depth: float = water_surface_y - (center_y - box_height * 0.5)
    var submerged: float = clampf(depth / box_height, 0.0, 1.0)
    if submerged <= 0.0:
        return
    var gravity: Vector3 = state.total_gravity
    var g: float = gravity.length()
    if g < 0.0001:
        return
    var buoyancy: Vector3 = -gravity.normalized() * (fluid_density * displaced_volume * g * submerged)
    state.apply_central_force(buoyancy)
    state.apply_central_force(-state.linear_velocity * water_drag * submerged)
    state.apply_torque(-state.angular_velocity * water_drag * submerged)
