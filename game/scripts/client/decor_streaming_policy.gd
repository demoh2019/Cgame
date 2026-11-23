extends RefCounted
## Small pure scheduling policy for streamed cosmetic MultiMesh categories.
## Gameplay resources, terrain collision and authoritative objects never wait.

const CAMERA_BONUS := 0.30


static func rank(distance: float, facing: float) -> float:
	if not is_finite(distance):
		return INF
	return maxf(distance, 0.0) * (1.0 - CAMERA_BONUS * clampf(facing, -1.0, 1.0))


## Camera heading is normalized once per scheduling frame, not once per
## pending chunk. Only ground-plane distance matters for surface scenery.
static func rank_ground(delta_xz: Vector2, unit_forward_xz: Vector2) -> float:
	var distance: float = delta_xz.length()
	var facing := 0.0
	if distance > 0.0001 and unit_forward_xz.length_squared() > 0.0001:
		facing = delta_xz.dot(unit_forward_xz) / distance
	return rank(distance, facing)


## One indivisible batch always progresses, even when it exceeds a budget.
## A budget is shared by every ChunkView in the process frame.
static func can_continue(elapsed_usec: int, budget_usec: int, completed: int) -> bool:
	return completed == 0 or (elapsed_usec < budget_usec and budget_usec > 0)
