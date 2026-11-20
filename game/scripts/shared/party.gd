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
const RallyStandard = preload("res://scripts/shared/rally_standard.gd")
# Party-only temporary rendezvous; server position, never client coordinates.
const RALLY_SECONDS := 45.0
const RALLY_COOLDOWN := 12.0
const READY_SECONDS := 30.0
const READY_RESULT_SECONDS := 10.0
const READY_COOLDOWN := 8.0


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


## Validate a free-standing tactical marker before taking a real crafted item.
func standard_reason(peer_id: int, position: Vector3, now: float) -> String:
	var group_id: int = group_of(peer_id)
	if group_id == 0 or not groups.has(group_id):
		return "not_in_party"
	if int(groups[group_id]["leader"]) != peer_id:
		return "leader_only"
	if not position.is_finite() or not is_finite(now):
		return "invalid_position"
	var group: Dictionary = groups[group_id]
	var marker: Dictionary = group.get("standard", {})
	if not marker.is_empty() and now < float(marker["expires"]):
		return "already_active"
	if now - float(group.get("standard_last_at", -INF)) < RallyStandard.COOLDOWN:
		return "cooldown"
	return ""


func raise_standard(peer_id: int, position: Vector3, now: float) -> Dictionary:
	var reason: String = standard_reason(peer_id, position, now)
	if reason != "":
		return {"ok": false, "reason": reason}
	var group: Dictionary = groups[group_of(peer_id)]
	group["standard_last_at"] = now
	group["standard"] = {"by": peer_id, "x": position.x, "y": position.y,
		"z": position.z, "placed_at": now, "expires": now + RallyStandard.DURATION}
	return {"ok": true, "seconds": RallyStandard.DURATION}


## A party member can only benefit from its own current group marker.
func standard_at(peer_id: int, position: Vector3, now: float, delta: float = 0.0) -> Dictionary:
	var group_id: int = group_of(peer_id)
	if group_id == 0 or not groups.has(group_id):
		return {}
	var marker: Dictionary = groups[group_id].get("standard", {})
	if marker.is_empty() or float(marker["expires"]) <= now - maxf(0.0, delta):
		return {}
	var source := Vector3(float(marker["x"]), float(marker["y"]), float(marker["z"]))
	if not RallyStandard.within_range(source, position):
		return {}
	if not groups[group_id]["members"].has(int(marker["by"])):
		return {}
	return marker


## Remove a temporary standard if the owner dies or leaves the party.
func clear_standard_by(peer_id: int) -> void:
	var group_id: int = group_of(peer_id)
	if group_id == 0 or not groups.has(group_id):
		return
	var group: Dictionary = groups[group_id]
	var deployed: Dictionary = group.get("standard", {})
	if not deployed.is_empty() and int(deployed.get("by", -1)) == peer_id:
		group.erase("standard")


## Party-only, short-lived consent check before an expedition or raid.
## A leader starts it; nobody can vote for another member or pass a deadline.
func start_ready_check(peer_id: int, now: float) -> Dictionary:
	if not is_finite(now):
		return {"ok": false, "reason": "invalid_time"}
	var group_id: int = group_of(peer_id)
	if group_id == 0 or not groups.has(group_id):
		return {"ok": false, "reason": "not_in_party"}
	var group: Dictionary = groups[group_id]
	if int(group["leader"]) != peer_id:
		return {"ok": false, "reason": "leader_only"}
	if group["members"].size() < 2:
		return {"ok": false, "reason": "need_party"}
	var active: Dictionary = group.get("ready_check", {})
	if not active.is_empty() and now < float(active["expires"]) and str(active["result"]) == "pending":
		return {"ok": false, "reason": "in_progress"}
	if now < float(group.get("ready_cooldown_until", -INF)):
		return {"ok": false, "reason": "cooldown"}
	var votes: Dictionary = {}
	for member_id in group["members"]:
		votes[int(member_id)] = "pending"
	group["ready_check"] = {"expires": now + READY_SECONDS,
		"result": "pending", "votes": votes}
	group["ready_cooldown_until"] = now + READY_COOLDOWN
	return {"ok": true, "seconds": READY_SECONDS}


func answer_ready_check(peer_id: int, is_ready: bool, now: float) -> Dictionary:
	if not is_finite(now):
		return {"ok": false, "reason": "invalid_time"}
	var group_id: int = group_of(peer_id)
	if group_id == 0 or not groups.has(group_id):
		return {"ok": false, "reason": "not_in_party"}
	var group: Dictionary = groups[group_id]
	var check: Dictionary = group.get("ready_check", {})
	if check.is_empty():
		return {"ok": false, "reason": "no_check"}
	if now >= float(check["expires"]):
		group.erase("ready_check")
		return {"ok": false, "reason": "expired"}
	if str(check["result"]) != "pending":
		return {"ok": false, "reason": "finished"}
	var votes: Dictionary = check["votes"]
	if not votes.has(peer_id):
		return {"ok": false, "reason": "not_in_party"}
	if str(votes[peer_id]) != "pending":
		return {"ok": false, "reason": "already_responded"}
	votes[peer_id] = "ready" if is_ready else "not_ready"
	var complete: bool = not is_ready
	if is_ready:
		complete = true
		for status in votes.values():
			if str(status) != "ready":
				complete = false
				break
	if complete:
		check["result"] = "all_ready" if is_ready else "not_ready"
		check["expires"] = now + READY_RESULT_SECONDS
	return {"ok": true, "ready": is_ready, "result": str(check["result"])}


## Death immediately revokes raid readiness for the entire current group.
func cancel_ready_check_for(peer_id: int) -> void:
	var group_id: int = group_of(peer_id)
	if group_id != 0 and groups.has(group_id):
		groups[group_id].erase("ready_check")


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
	# Membership changes invalidate old consent, including completed results.
	group.erase("ready_check")
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
	group.erase("ready_check")
	# An abandoned standard cannot buff former teammates or a new leader.
	var raised: Dictionary = group.get("standard", {})
	if not raised.is_empty() and int(raised.get("by", -1)) == peer_id:
		group.erase("standard")
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
	for group_id in groups.keys():
		var group: Dictionary = groups[group_id]
		var active: Dictionary = group.get("ready_check", {})
		if not active.is_empty() and now >= float(active["expires"]):
			group.erase("ready_check")


func state_for(peer_id: int, now: float = 0.0) -> Dictionary:
	var group_id: int = group_of(peer_id)
	if group_id == 0 or not groups.has(group_id):
		return {"id": 0, "leader": 0, "members": [], "rally": {}, "standard": {},
			"ready_check": {}, "invite_from": int(invites.get(peer_id, {}).get("from", 0))}
	var group: Dictionary = groups[group_id]
	var marker: Dictionary = group.get("rally", {})
	var shared_marker := {}
	if not marker.is_empty() and now < float(marker["expires"]):
		# Never expose the marker to nonmembers or stale clients.
		shared_marker = {"x": float(marker["x"]), "y": float(marker["y"]),
			"z": float(marker["z"]),
			"remaining": maxf(0.0, float(marker["expires"]) - now)}
	var source_standard: Dictionary = group.get("standard", {})
	var public_standard: Dictionary = {}
	if not source_standard.is_empty() and now < float(source_standard["expires"]):
		public_standard = {"x": float(source_standard["x"]),
			"y": float(source_standard["y"]), "z": float(source_standard["z"]),
			"remaining": maxf(0.0, float(source_standard["expires"]) - now),
			"cooldown": maxf(0.0, float(group.get("standard_last_at", now)) +
				RallyStandard.COOLDOWN - now)}
	var public_ready: Dictionary = {}
	var ready: Dictionary = group.get("ready_check", {})
	if not ready.is_empty() and now < float(ready["expires"]):
		var visible_votes: Array = []
		var votes: Dictionary = ready["votes"]
		for member_id in group["members"]:
			visible_votes.append({"id": int(member_id),
				"status": str(votes.get(int(member_id), "pending"))})
		public_ready = {"result": str(ready["result"]),
			"remaining": maxf(0.0, float(ready["expires"]) - now),
			"votes": visible_votes}
	return {"id": group_id, "leader": int(group["leader"]),
		"members": (group["members"] as Array).duplicate(), "rally": shared_marker,
		"standard": public_standard, "ready_check": public_ready,
		"invite_from": int(invites.get(peer_id, {}).get("from", 0))}
