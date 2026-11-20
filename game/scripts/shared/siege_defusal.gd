extends RefCounted
## A counterplay action against a real four-second armed siege explosive.
## All targeting and wall ownership come from server state, never the RPC.
const Structures = preload("res://scripts/shared/structures.gd")
const SiegeCharge = preload("res://scripts/shared/siege_charge.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")
const RangedCover = preload("res://scripts/shared/ranged_cover.gd")

const ITEM_ID := "siege_defusal_kit"
const REACH := 3.0


static func nearest(world, player, charges: Dictionary,
		walls: Dictionary, now: float) -> Dictionary:
	if player == null or not player.position.is_finite() or not is_finite(now):
		return {"ok": false, "reason": "invalid_position"}
	var at := Vector2(player.position.x, player.position.z)
	if not ZoneRisk.allows_pvp(world.zone_at(at.x, at.y)):
		return {"ok": false, "reason": "safe_zone"}
	# The nearest physical charge is chosen first, before checking rights.
	# A forbidden adjacent charge cannot be skipped to defuse a distant one.
	var selected_id: int = -1
	var closest: float = INF
	for raw_id in charges:
		var charge: Dictionary = charges[raw_id]
		var site := Vector2(float(charge.get("x", NAN)),
			float(charge.get("z", NAN)))
		if not site.is_finite():
			continue
		var distance: float = at.distance_to(site)
		var id: int = int(raw_id)
		if distance <= REACH and (distance < closest or
				(is_equal_approx(distance, closest) and
				(selected_id < 0 or id < selected_id))):
			closest = distance
			selected_id = id
	if selected_id < 0:
		return {"ok": false, "reason": "no_armed_charge"}
	var chosen: Dictionary = charges[selected_id]
	if now >= float(chosen.get("until", -INF)):
		return {"ok": false, "reason": "fuse_expired"}
	if not SiegeCharge.valid_detonation(world, chosen, walls):
		return {"ok": false, "reason": "invalid_charge"}
	var wall_id: int = int(chosen["wall"])
	var wall: Dictionary = walls[wall_id]
	if not Structures.can_manage(wall, player.id, player.user_id):
		return {"ok": false, "reason": "not_owner"}
	if not ZoneRisk.allows_pvp(world.zone_at(float(wall["x"]), float(wall["z"]))):
		return {"ok": false, "reason": "safe_zone"}
	var toward := Vector2(float(wall["x"]), float(wall["z"])) - at
	if toward.length_squared() < 0.0001:
		return {"ok": false, "reason": "blocked"}
	# Cannot defuse through a solid rock, a ruin or a second wall.
	var first: Dictionary = RangedCover.first_blocker(world, at, toward,
		toward.length() + Structures.RADIUS + 0.2)
	if int(first.get("id", -1)) != wall_id:
		return {"ok": false, "reason": "blocked"}
	return {"ok": true, "id": selected_id, "wall": wall_id,
		"x": float(chosen["x"]), "z": float(chosen["z"])}
