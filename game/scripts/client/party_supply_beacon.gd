extends RefCounted
## Validate one transient supply location before showing it in the client map,
## 3D world or HUD. Server events are trusted for their origin, but every
## snapshot must re-check group membership and the event's expiration.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const TravelNavigation = preload("res://scripts/shared/travel_navigation.gd")
const PartySupplyRequest = preload("res://scripts/shared/party_supply_request.gd")


static func read(signal_state: Dictionary, viewer_id: int, party: Dictionary, now: float) -> Dictionary:
	if not is_finite(now) or str(signal_state.get("type", "")) != "party_supply_request":
		return {}
	var source_id: int = int(signal_state.get("peer", -1))
	var group_id: int = int(party.get("id", 0))
	if viewer_id <= 0 or group_id <= 0 or source_id <= 0 or source_id == viewer_id:
		return {}
	if int(signal_state.get("group", 0)) != group_id:
		return {}
	var members: Array = party.get("members", [])
	if not members.has(source_id) or not members.has(viewer_id):
		return {}
	var expires: float = float(signal_state.get("expires", -INF))
	if not is_finite(expires) or expires <= now or expires > now + PartySupplyRequest.ALERT_SECONDS + 1.0:
		return {}
	var need: String = str(signal_state.get("need", ""))
	if not PartySupplyRequest.valid_need(need):
		return {}
	var level: float = float(signal_state.get("level", -1))
	if not is_finite(level) or level < 0.0 or level > PartySupplyRequest.NEED_THRESHOLD:
		return {}
	var position := Vector2(float(signal_state.get("x", INF)), float(signal_state.get("z", INF)))
	if not TravelNavigation.valid_destination(position, WorldGen.WORLD_RADIUS):
		return {}
	return {"type": "party_supply_request", "group": group_id, "peer": source_id,
		"x": position.x, "z": position.y, "need": need, "level": int(level),
		"name": str(signal_state.get("name", "Survivor")), "expires": expires}
