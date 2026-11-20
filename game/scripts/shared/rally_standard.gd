extends RefCounted
## A single temporary, material-paid squad standard. Only the verified party
## leader may deploy it; there is no client-controlled position or buff power.

const ITEM_ID := "field_standard"
const DURATION := 90.0
const COOLDOWN := 120.0
const RADIUS := 11.0
const MAX_VERTICAL_DISTANCE := 3.0
const STAMINA_PER_SECOND := 1.4
const ENERGY_PER_SECOND := 0.8


static func within_range(marker: Vector3, position: Vector3) -> bool:
	if not marker.is_finite() or not position.is_finite():
		return false
	if absf(marker.y - position.y) > MAX_VERTICAL_DISTANCE:
		return false
	var delta := Vector2(marker.x - position.x, marker.z - position.z)
	return delta.length_squared() <= RADIUS * RADIUS


static func bonus_seconds(now: float, delta: float, placed: float, expires: float) -> float:
	if not is_finite(now) or not is_finite(delta) or not is_finite(placed) or not is_finite(expires):
		return 0.0
	if delta <= 0.0 or expires <= placed:
		return 0.0
	# Prevent a large simulation step from granting benefits before placement
	# or after expiry. The server's simulation clock controls all values.
	return maxf(0.0, minf(now, expires) - maxf(now - delta, placed))
