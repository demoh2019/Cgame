extends RefCounted
## Session-only, server-authoritative expedition parties.
## These rules deliberately do not depend on account or client trust.

const MAX_MEMBERS := 5
const INVITE_RANGE := 14.0
const JOIN_RANGE := 18.0
const INVITE_SECONDS := 30.0
const ASSIST_RANGE := 32.0
const ASSIST_XP_FRACTION := 0.35


static func within_range(a: Vector3, b: Vector3, range_meters: float) -> bool:
	if not a.is_finite() or not b.is_finite() or range_meters <= 0.0:
		return false
	var horizontal := Vector2(a.x - b.x, a.z - b.z)
	return horizontal.length_squared() <= range_meters * range_meters


static func assist_xp(base_xp: int) -> int:
	if base_xp <= 0:
		return 0
	return maxi(1, mini(100, int(floor(float(base_xp) * ASSIST_XP_FRACTION))))


static func party_member_ids(party: Dictionary) -> Array:
	var members: Variant = party.get("members", [])
	return (members as Array).duplicate() if members is Array else []
