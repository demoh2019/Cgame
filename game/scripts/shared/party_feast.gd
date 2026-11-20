extends RefCounted
## Server-controlled shared camp meal. Never accept client-reported party members,
## positions, fire status, food quantity, meal tier, or recovery bonuses.

const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")
const HeartyMeal = preload("res://scripts/shared/hearty_meal.gd")
const COOLDOWN := 20.0
const MAX_HEIGHT_DIFFERENCE := 2.5


static func near_fire(camp: Dictionary, position: Vector3, now: float) -> bool:
	if not position.is_finite() or not is_finite(now):
		return false
	if camp.is_empty():
		return false
	var fire_x: float = float(camp.get("x", INF))
	var fire_y: float = float(camp.get("y", INF))
	var fire_z: float = float(camp.get("z", INF))
	var expires: float = float(camp.get("expires", -INF))
	if not is_finite(fire_x) or not is_finite(fire_y) or not is_finite(fire_z):
		return false
	if not is_finite(expires) or expires <= now:
		return false
	if absf(position.y - fire_y) > MAX_HEIGHT_DIFFERENCE:
		return false
	var offset := Vector2(position.x - fire_x, position.z - fire_z)
	return offset.length_squared() <= FieldCampfire.WARM_RADIUS * FieldCampfire.WARM_RADIUS


## Choose a real active server campfire, never a site or ID sent by the client.
static func camp_for(campfires: Dictionary, position: Vector3, now: float) -> Dictionary:
	for fire in campfires.values():
		if fire is Dictionary and near_fire(fire, position, now):
			return fire
	return {}


static func food_tier(item_id: String) -> int:
	return HeartyMeal.tier_for_food(item_id)
