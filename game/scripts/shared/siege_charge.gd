extends RefCounted
## A physical PvP siege charge: server picks the nearest wall and owns its fuse.
## No client-provided wall id, explosive damage or detonation time.

const BarricadeBallistics = preload("res://scripts/shared/barricade_ballistics.gd")
const NoiseDecoy = preload("res://scripts/shared/noise_decoy.gd")
const RangedCover = preload("res://scripts/shared/ranged_cover.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")

const ITEM_ID := "siege_charge"
const PLANT_REACH := 3.5
const FUSE_SECONDS := 4.0
const DAMAGE := 160.0
const MAX_ACTIVE := 24
const MAX_PER_OWNER := 1
const MAX_PER_WALL := 1
const NOISE_RADIUS := NoiseDecoy.HEARING_RADIUS
const NOISE_SECONDS := 2.5


## Match a stable account across reconnections; guests use instance identity,
## never an untrusted or recycled transport peer number.
static func owner_token(player) -> String:
	return ("account:" + player.user_id) if not player.user_id.is_empty() \
		else ("session:%d" % player.get_instance_id())


## Select from real world structures. If a protected wall is nearest, the
## server does NOT silently skip it to damage an enemy wall behind it.
static func nearest_wall(world, player, walls: Dictionary) -> Dictionary:
	if player == null or not player.position.is_finite():
		return {"ok": false, "reason": "invalid_position"}
	var at: Vector2 = Vector2(player.position.x, player.position.z)
	var zone: int = world.zone_at(at.x, at.y)
	if not ZoneRisk.allows_pvp(zone):
		return {"ok": false, "reason": "safe_zone"}
	var picked: Dictionary = {}
	var best_distance: float = INF
	var best_id: int = -1
	for wall_id in walls:
		var wall: Dictionary = walls[wall_id]
		var center: Vector2 = Vector2(float(wall.get("x", NAN)), float(wall.get("z", NAN)))
		if not center.is_finite() or not is_finite(float(wall.get("hp", NAN))) \
				or float(wall.get("hp", 0.0)) <= 0.0:
			continue
		var dist: float = at.distance_to(center)
		if not is_finite(dist) or dist > PLANT_REACH:
			continue
		if dist < best_distance or (is_equal_approx(dist, best_distance) and int(wall_id) < best_id):
			best_distance = dist
			best_id = int(wall_id)
			picked = wall
	if picked.is_empty():
		return {"ok": false, "reason": "no_wall_nearby"}
	if not BarricadeBallistics.can_damage(player, picked,
			zone, world.zone_at(float(picked["x"]), float(picked["z"]))):
		return {"ok": false, "reason": "protected_wall"}
	# The wall must be the *first* physical blocker between the survivor
	# and selected position. No planting a charge through rocks or ruins.
	var direction: Vector2 = Vector2(float(picked["x"]), float(picked["z"])) - at
	if direction.length_squared() < 0.0001:
		return {"ok": false, "reason": "blocked"}
	var obstacle: Dictionary = RangedCover.first_blocker(world, at, direction,
		best_distance + Structures.RADIUS + 0.2)
	if int(obstacle.get("id", -1)) != best_id:
		return {"ok": false, "reason": "blocked"}
	return {"ok": true, "wall": best_id,
		"x": float(picked["x"]), "z": float(picked["z"])}


static func placement_reason(charges: Dictionary, wall_id: int, player) -> String:
	if charges.size() >= MAX_ACTIVE:
		return "world_limit"
	var token: String = owner_token(player)
	var own_count := 0
	var wall_count := 0
	for charge in charges.values():
		if str(charge.get("owner", "")) == token:
			own_count += 1
		if int(charge.get("wall", -1)) == wall_id:
			wall_count += 1
	if own_count >= MAX_PER_OWNER:
		return "owner_limit"
	if wall_count >= MAX_PER_WALL:
		return "wall_armed"
	return ""


## Detached charges are session-only, and only the same world-owned
## barricade at the original position can take damage after the fuse.
static func valid_detonation(world, charge: Dictionary, walls: Dictionary) -> bool:
	if not walls.has(int(charge.get("wall", -1))):
		return false
	var wall: Dictionary = walls[int(charge["wall"])]
	var x: float = float(charge.get("x", NAN))
	var z: float = float(charge.get("z", NAN))
	if not is_finite(x) or not is_finite(z):
		return false
	if absf(float(wall.get("x", INF)) - x) > 0.01 \
			or absf(float(wall.get("z", INF)) - z) > 0.01:
		return false
	if not ZoneRisk.allows_pvp(world.zone_at(x, z)):
		return false
	return float(wall.get("hp", 0.0)) > 0.0
