extends RefCounted
## Reusable *game-side* attack visibility helper.
## Raycasts honor physics collision layer 1 (world obstacles and the survivor).
## This is not a navigation mesh or an AI engine API.

const WORLD_MASK := 1
const MIN_RAY_LENGTH_SQUARED := 0.000001


static func first_blocker(space: PhysicsDirectSpaceState3D, from: Vector3,
        to: Vector3, source: CollisionObject3D,
        allowed_target: CollisionObject3D = null) -> Dictionary:
    # Fail closed for non-finite vectors; avoid undefined physics queries.
    if not from.is_finite() or not to.is_finite():
        return {"invalid": true}
    if from.distance_squared_to(to) <= MIN_RAY_LENGTH_SQUARED:
        return {}
    var ignored: Array[RID] = []
    if is_instance_valid(source):
        ignored.append(source.get_rid())
    var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK, ignored)
    query.collide_with_areas = false
    var hit: Dictionary = space.intersect_ray(query)
    if not hit.is_empty() and hit.get("collider") == allowed_target:
        return {}
    return hit


static func clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
        source: CollisionObject3D, allowed_target: CollisionObject3D = null) -> bool:
    return first_blocker(space, from, to, source, allowed_target).is_empty()
