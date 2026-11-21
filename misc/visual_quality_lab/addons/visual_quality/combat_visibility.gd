extends RefCounted
class_name WorldCombatVisibility3D
## Physics-space line of sight for streamed combat actors. Call from the
## physics tick (not a GUI/input event) when using threaded physics.
## The mask matches cover and actors; hitting the intended target is allowed.


static func has_clear_path(world: World3D, origin: Vector3, destination: Vector3,
		source: Node3D = null, target: Node3D = null, collision_mask: int = 1) -> bool:
	if world == null or not origin.is_finite() or not destination.is_finite():
		return false
	if origin.distance_squared_to(destination) <= 0.0001:
		return true
	var excluded: Array[RID] = []
	if is_instance_valid(source) and source is CollisionObject3D:
		excluded.append((source as CollisionObject3D).get_rid())
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin, destination, collision_mask, excluded)
	query.collide_with_areas = false
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	return hit_is_clear(hit, target)


## Pure classifier: helps test filters without a physics world.
static func hit_is_clear(hit: Dictionary, target: Node3D = null) -> bool:
	if hit.is_empty():
		return true
	if not is_instance_valid(target):
		return false
	var collider: Variant = hit.get("collider")
	if not is_instance_valid(collider):
		return false
	if collider == target:
		return true
	return collider is Node and target.is_ancestor_of(collider)
