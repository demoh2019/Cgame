extends RefCounted
## Session-only survivor parties, inspired by classic cooperative MMORPGs.
## Every mutation is invoked by the authoritative GameServer; clients may
## request a target peer but cannot choose a leader, member list, or rewards.

const MAX_MEMBERS := 5
const INVITE_SECONDS := 30.0
const INVITE_RANGE := 16.0
const ASSIST_RANGE := 28.0
const ASSIST_WINDOW := 20.0
const ASSIST_XP_RATE := 0.5
# Party-only temporary rendezvous; server position, never client coordinates.
const RALLY_SECONDS := 45.0
const RALLY_COOLDOWN := 12.0


## Only the server invokes this after a confirmed infected kill.
static func assist_xp(base_xp: int) -> int:
	if base_xp <= 0:
		return 0
	return maxi(1, mini(100, int(floor(float(base_xp) * ASSIST_XP_RATE))))


static func in_assist_range(first: Vector3, second: Vector3) -> bool:
	if not first.is_finite() or not second.is_finite():
		return false
	var offset := Vector2(first.x - second.x, first.z - second.z)
	return offset.length_squared() <= ASSIST_RANGE * ASSIST_RANGE

var groups: Dictionary = {} # group id -> {"leader": peer, "members": [peers]}
var group_by_peer: Dictionary = {} # peer id -> group id
var invites: Dictionary = {} # invited peer -> {"from": id, "group": id, "expires": time}
var _next_id: int = 0


## The leader marks their own authoritative location. Party members see
## exactly one active marker; ungrouped and unrelated clients never receive it.
func mark_rally(peer_id: int, position: Vector3, now: float) -> Dictionary:
	var group_id: int = group_of(peer_id)
	if group_id == 0 or not groups.has(group_id):
		return {"ok": false, "reason": "not_in_party"}
	var group: Dictionary = groups[group_id]
	if int(group["leader"]) != peer_id:
		return {"ok": false, "reason": "leader_only"}
	if not position.is_finite() or not is_finite(now):
		return {"ok": false, "reason": "invalid_position"}
	var previous: float = float(group.get("rally_last_at", -INF))
	if now - previous < RALLY_COOLDOWN:
		return {"ok": false, "reason": "cooldown"}
	group["rally_last_at"] = now
	group["rally"] = {
		"x": position.x, "y": position.y, "z": position.z,
		"expires": now + RALLY_SECONDS,
	}
	return {"ok": true, "seconds": RALLY_SECONDS}


func members_of(peer_id: int) -> Array:
	var group_id: int = int(group_by_peer.get(peer_id, 0))
	if group_id == 0 or not groups.has(group_id):
		return []
	return (groups[group_id]["members"] as Array).duplicate()


func group_of(peer_id: int) -> int:
	return int(group_by_peer.get(peer_id, 0))


func invite(from_id: int, to_id: int, now: float) -> Dictionary:
	if from_id <= 0 or to_id <= 0 or from_id == to_id:
		return {"ok": false, "reason": "invalid_target"}
	if group_by_peer.has(to_id):
		return {"ok": false, "reason": "target_in_party"}
	var group_id: int = group_of(from_id)
	if group_id != 0:
		var group: Dictionary = groups[group_id]
		if int(group["leader"]) != from_id:
			return {"ok": false, "reason": "leader_only"}
		if group["members"].size() >= MAX_MEMBERS:
			return {"ok": false, "reason": "party_full"}
	# A target cannot be spammed by replacing an active invitation.
	var current: Dictionary = invites.get(to_id, {})
	if not current.is_empty() and now < float(current["expires"]):
		return {"ok": false, "reason": "already_invited"}
	if group_id == 0:
		_next_id += 1
		group_id = _next_id
		groups[group_id] = {"leader": from_id, "members": [from_id]}
		group_by_peer[from_id] = group_id
	invites[to_id] = {"from": from_id, "group": group_id,
		"expires": now + INVITE_SECONDS}
	return {"ok": true, "group": group_id, "to": to_id,
		"expires": now + INVITE_SECONDS}


func accept(target_id: int, now: float) -> Dictionary:
	var offer: Dictionary = invites.get(target_id, {})
	if offer.is_empty():
		return {"ok": false, "reason": "no_invite"}
	invites.erase(target_id)
	if now >= float(offer["expires"]):
		return {"ok": false, "reason": "expired"}
	if group_by_peer.has(target_id):
		return {"ok": false, "reason": "already_in_party"}
	var group_id: int = int(offer["group"])
	var source: int = int(offer["from"])
	if not groups.has(group_id) or group_of(source) != group_id:
		return {"ok": false, "reason": "party_gone"}
	var group: Dictionary = groups[group_id]
	if int(group["leader"]) != source:
		return {"ok": false, "reason": "leader_changed"}
	if group["members"].size() >= MAX_MEMBERS:
		return {"ok": false, "reason": "party_full"}
	group["members"].append(target_id)
	group_by_peer[target_id] = group_id
	return {"ok": true, "group": group_id, "leader": source}


func decline(target_id: int) -> Dictionary:
	if not invites.has(target_id):
		return {"ok": false, "reason": "no_invite"}
	invites.erase(target_id)
	return {"ok": true}


func leave(peer_id: int) -> Dictionary:
	var group_id: int = group_of(peer_id)
	if group_id == 0 or not groups.has(group_id):
		return {"ok": false, "reason": "not_in_party"}
	var group: Dictionary = groups[group_id]
	var members: Array = group["members"]
	members.erase(peer_id)
	group_by_peer.erase(peer_id)
	# Invitations to disconnected leaders and disbanded parties are invalid.
	for target in invites.keys():
		var offer: Dictionary = invites[target]
		if int(offer["from"]) == peer_id:
			invites.erase(target)
	if group["members"].size() < 2:
		for remaining in group["members"]:
			group_by_peer.erase(remaining)
		groups.erase(group_id)
		for target in invites.keys():
			if int(invites[target]["group"]) == group_id:
				invites.erase(target)
		return {"ok": true, "disbanded": true}
	if int(group["leader"]) == peer_id:
		group["leader"] = int(group["members"][0])
		# Pending invitations were signed by a different leader.
		for target in invites.keys():
			if int(invites[target]["group"]) == group_id:
				invites.erase(target)
	return {"ok": true, "group": group_id, "leader": int(group["leader"])}


func kick(leader_id: int, target_id: int) -> Dictionary:
	var group_id: int = group_of(leader_id)
	if group_id == 0 or not groups.has(group_id):
		return {"ok": false, "reason": "not_in_party"}
	if int(groups[group_id]["leader"]) != leader_id:
		return {"ok": false, "reason": "leader_only"}
	if leader_id == target_id or group_of(target_id) != group_id:
		return {"ok": false, "reason": "invalid_target"}
	return leave(target_id)


func disconnect_peer(peer_id: int) -> void:
	invites.erase(peer_id)
	if group_by_peer.has(peer_id):
		leave(peer_id)


func expire(now: float) -> void:
	for target in invites.keys():
		if now >= float(invites[target]["expires"]):
			invites.erase(target)


func state_for(peer_id: int, now: float = 0.0) -> Dictionary:
	var group_id: int = group_of(peer_id)
	if group_id == 0 or not groups.has(group_id):
		return {"id": 0, "leader": 0, "members": [], "rally": {},
			"invite_from": int(invites.get(peer_id, {}).get("from", 0))}
	var group: Dictionary = groups[group_id]
	var marker: Dictionary = group.get("rally", {})
	var shared_marker := {}
	if not marker.is_empty() and now < float(marker["expires"]):
		# Never expose the marker to nonmembers or stale clients.
		shared_marker = {"x": float(marker["x"]), "y": float(marker["y"]),
			"z": float(marker["z"]),
			"remaining": maxf(0.0, float(marker["expires"]) - now)}
	return {"id": group_id, "leader": int(group["leader"]),
		"members": (group["members"] as Array).duplicate(), "rally": shared_marker,
		"invite_from": int(invites.get(peer_id, {}).get("from", 0))}
