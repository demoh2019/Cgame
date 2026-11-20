extends RefCounted
## Party-only preview of a courier destination; no wallet or account details.
const TravelNavigation = preload("res://scripts/shared/travel_navigation.gd")


static func shared_route(peer_id: int, players: Dictionary, parties) -> Dictionary:
	var group_id: int = parties.group_of(peer_id)
	if group_id <= 0 or not parties.groups.has(group_id):
		return {}
	var group: Dictionary = parties.groups[group_id]
	var members: Array = group["members"]
	if members.size() < 2 or not members.has(peer_id):
		return {}
	var ordered: Array = members.duplicate()
	ordered.sort()
	var leader: int = int(group["leader"])
	if ordered.has(leader):
		ordered.erase(leader)
		ordered.push_front(leader)
	for id in ordered:
		var courier = players.get(int(id))
		if courier == null or not courier.survival.alive or courier.caravan_state.is_empty():
			continue
		var job: Dictionary = courier.caravan_view
		var target: Vector2 = TravelNavigation.target(job, "dst_x", "dst_z")
		if not target.is_finite():
			continue
		return {"owner": int(id), "name": courier.name,
			"dst_x": target.x, "dst_z": target.y,
			"destination": str(job.get("destination", "")),
			"cargo": str(job.get("cargo", "")),
			"quantity": int(job.get("quantity", 0))}
	return {}


## Validate both current group and original alarm group at delivery time.
static func can_receive_alert(event: Dictionary, peer: int, players: Dictionary,
		parties) -> bool:
	var courier: int = int(event.get("peer", 0))
	if not players.has(courier) or not players.has(peer):
		return false
	if peer == courier:
		return true
	var group_id: int = int(event.get("group", 0))
	if group_id <= 0 or not parties.groups.has(group_id):
		return false
	var members: Array = parties.groups[group_id]["members"]
	return parties.group_of(courier) == group_id and parties.group_of(peer) == group_id \
		and members.has(courier) and members.has(peer)
