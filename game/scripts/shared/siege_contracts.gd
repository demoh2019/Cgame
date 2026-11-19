extends RefCounted
## Server-owned siege challenges for existing parties, not permanent Nakama guild wars.
## Cost is paid when declared; combat/capture remains governed by TerritoryControl.
## A victory needs a real capture event inside the announced attack window.

const DECLARE_RADIUS := 24.0
const MIN_ATTACKERS := 2
const PREPARATION_SECONDS := 20.0
const ATTACK_SECONDS := 180.0
const SITE_COOLDOWN := 300.0
const MIN_REMAINING_CONTROL := 80.0 # Preparation + worst-case fortified capture time.
const COST := {"cloth_2": 2, "silver": 25}

var active: Dictionary = {} # site id -> current challenge
var cooldowns: Dictionary = {} # site id -> next eligible time
var victories: Dictionary = {} # session party id -> successful challenges


func declare(site: Dictionary, inventory, player_position: Vector3, group_id: int,
		is_leader: bool, nearby_allies: int, now: float) -> Dictionary:
	if site.is_empty():
		return {"ok": false, "reason": "unknown_outpost"}
	if not player_position.is_finite() or not is_finite(now) or now < 0.0:
		return {"ok": false, "reason": "invalid_position"}
	var point := Vector2(float(site.get("x", NAN)), float(site.get("z", NAN)))
	if not point.is_finite() or Vector2(player_position.x, player_position.z).distance_squared_to(point) > DECLARE_RADIUS * DECLARE_RADIUS:
		return {"ok": false, "reason": "too_far"}
	if group_id <= 0 or not is_leader:
		return {"ok": false, "reason": "leader_only"}
	if nearby_allies < MIN_ATTACKERS:
		return {"ok": false, "reason": "requires_party"}
	var defender: int = int(site.get("owner", 0))
	if defender == 0 or defender == group_id or float(site.get("until", 0.0)) <= now:
		return {"ok": false, "reason": "not_enemy"}
	if float(site["until"]) - now < MIN_REMAINING_CONTROL:
		return {"ok": false, "reason": "owner_expiring"}
	var site_id: int = int(site.get("id", -1))
	if active.has(site_id):
		return {"ok": false, "reason": "already_declared"}
	if now < float(cooldowns.get(site_id, 0.0)):
		return {"ok": false, "reason": "cooldown"}
	if not inventory.has_all(COST):
		return {"ok": false, "reason": "missing_materials"}
	var before: Dictionary = inventory.to_dict()
	for item_id in COST:
		if not inventory.remove(item_id, int(COST[item_id])):
			inventory.load_dict(before)
			return {"ok": false, "reason": "missing_materials"}
	var starts: float = now + PREPARATION_SECONDS
	var expires: float = starts + ATTACK_SECONDS
	active[site_id] = {
		"site": site_id, "attacker": group_id, "defender": defender,
		"starts": starts, "expires": expires,
	}
	return {
		"ok": true, "site": site_id, "spent": COST.duplicate(),
		"preparation": PREPARATION_SECONDS, "attack_window": ATTACK_SECONDS,
	}


## Read-only client view; does not disclose account IDs or private inventories.
func public_state(outposts: Array, now: float) -> Array:
	var result: Array = []
	for entry in outposts:
		var data: Dictionary = (entry as Dictionary).duplicate()
		var war: Dictionary = active.get(int(data["id"]), {})
		data["siege_phase"] = ""
		data["siege_attacker"] = 0
		data["siege_starts_in"] = 0.0
		data["siege_ends_in"] = 0.0
		if not war.is_empty():
			data["siege_attacker"] = int(war["attacker"])
			data["siege_starts_in"] = maxf(0.0, float(war["starts"]) - now)
			data["siege_ends_in"] = maxf(0.0, float(war["expires"]) - now)
			data["siege_phase"] = "preparing" if now < float(war["starts"]) else "active"
		result.append(data)
	return result


## Must run after the normal territory tick. Only its capture events may win a war.
func tick(now: float, sites: Array, parties, capture_events: Array) -> Array:
	var announcements: Array = []
	if not is_finite(now):
		return announcements
	var site_index: Dictionary = {}
	for site in sites:
		site_index[int(site["id"])] = site
	var captured: Dictionary = {}
	for event in capture_events:
		if event.get("type") == "outpost_taken":
			captured[int(event["id"])] = int(event["owner"])
	for site_id in active.keys():
		var contract: Dictionary = active[site_id]
		var site: Dictionary = site_index.get(site_id, {})
		var attacker: int = int(contract["attacker"])
		var defender: int = int(contract["defender"])
		var status := ""
		# Actual site ownership is consulted even when a capture event was
		# lost: never award a victory without a matching capture event.
		if site.is_empty() or not parties.groups.has(attacker) or not parties.groups.has(defender):
			status = "cancelled"
		elif captured.has(site_id):
			if int(captured[site_id]) == attacker and now >= float(contract["starts"]) and now <= float(contract["expires"]):
				status = "won"
			else:
				status = "lost"
		elif int(site["owner"]) != defender:
			status = "lost"
		elif now >= float(contract["expires"]):
			status = "expired"
		if status == "":
			continue
		active.erase(site_id)
		cooldowns[site_id] = now + SITE_COOLDOWN
		if status == "won":
			victories[attacker] = int(victories.get(attacker, 0)) + 1
		announcements.append({
			"type": "siege_contract_result", "site": site_id, "result": status,
			"attacker": attacker, "defender": defender,
			"x": float(site.get("x", 0.0)), "z": float(site.get("z", 0.0)),
		})
	return announcements
