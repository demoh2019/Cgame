extends RefCounted
## A crafted one-use expedition signal shares only a real, currently marked
## mineral deposit with authenticated teammates via the existing party ping.
## No client-supplied coordinates, resource IDs, ore quantities or payouts.

const Prospecting = preload("res://scripts/shared/prospecting_chart.gd")
const Party = preload("res://scripts/shared/party.gd")
const TravelNavigation = preload("res://scripts/shared/travel_navigation.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")

const ITEM_ID := "surveyor_signal"


## Pure, nonmutating preflight: invalid scans or party cooldowns cost nothing.
static func candidate(player, parties, depleted: Dictionary, now: float) -> Dictionary:
	if player == null or not player.position.is_finite() or not is_finite(now):
		return {"ok": false, "reason": "invalid_state"}
	if not Prospecting.active(player.prospect_mark, now, depleted):
		return {"ok": false, "reason": "no_active_survey"}
	var public: Dictionary = Prospecting.public_mark(player.prospect_mark, now, depleted)
	if public.is_empty():
		return {"ok": false, "reason": "invalid_survey"}
	var target := Vector2(float(public["x"]), float(public["z"]))
	if not TravelNavigation.valid_destination(target, WorldGen.WORLD_RADIUS):
		return {"ok": false, "reason": "invalid_survey"}
	var group_id: int = parties.group_of(player.id)
	if group_id == 0 or not parties.groups.has(group_id):
		return {"ok": false, "reason": "not_in_party"}
	var group: Dictionary = parties.groups[group_id]
	if (group["members"] as Array).size() < 2 or not (group["members"] as Array).has(player.id):
		return {"ok": false, "reason": "need_party"}
	if now < float(group.get("ping_last_at", -INF)) + Party.PING_COOLDOWN:
		return {"ok": false, "reason": "cooldown"}
	return {"ok": true, "x": target.x, "z": target.y,
		"node_id": int(player.prospect_mark["id"]),
		"until": float(player.prospect_mark["until"]),
		"material": str(public["kind"]), "tier": int(public["tier"])}


## Must be called immediately after preflight and inventory debit on the
## authoritative server; mark_ping repeats the party/cooldown validation.
static func broadcast(parties, peer_id: int, selection: Dictionary, now: float) -> Dictionary:
	if not bool(selection.get("ok", false)):
		return {"ok": false, "reason": "invalid_survey"}
	var outcome: Dictionary = parties.mark_ping(peer_id,
		Vector2(float(selection["x"]), float(selection["z"])), now)
	if not bool(outcome.get("ok", false)):
		return outcome
	var group: Dictionary = parties.groups[parties.group_of(peer_id)]
	var ping: Dictionary = group["ping"]
	ping["source"] = "survey"
	ping["material"] = str(selection["material"])
	ping["tier"] = int(selection["tier"])
	ping["node_id"] = int(selection["node_id"]) # Server-only, never replicated.
	ping["expires"] = minf(float(ping["expires"]), float(selection["until"]))
	return {"ok": true, "seconds": maxf(0.0, float(ping["expires"]) - now),
		"material": str(ping["material"]), "tier": int(ping["tier"])}


## Any survivor harvesting a signalled node closes the squad waypoint in the
## same authoritative tick, even when the surveyor is not the harvester.
static func clear_depleted(parties, node_id: int) -> void:
	for group in parties.groups.values():
		var ping: Dictionary = group.get("ping", {})
		if str(ping.get("source", "")) == "survey" and int(ping.get("node_id", -1)) == node_id:
			group.erase("ping")
