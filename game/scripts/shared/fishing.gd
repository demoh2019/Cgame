extends RefCounted
## Shore fishing rules shared by server and tests. The client may only ask
## the server to start casting: it cannot choose catch, tier or duration.
## The rod is a carried tool, not an equippable weapon.

const Defs = preload("res://scripts/shared/defs.gd")

const CAST_SECONDS := 5.0
const COOLDOWN_SECONDS := 2.0
const CATCH_ID := "raw_fish"
const WATER_DISTANCES := [2.0, 2.8, 3.6]
const WATER_SAMPLES := 16
const MAX_CATCH := 2


static func water_near(world, position: Vector3) -> Vector2:
	if not position.is_finite() or world.is_water(position.x, position.z):
		return Vector2.INF # No casting from deep water or forged coordinates.
	for distance in WATER_DISTANCES:
		for sample in WATER_SAMPLES:
			var radians := TAU * float(sample) / float(WATER_SAMPLES)
			var point := Vector2(position.x, position.z) + Vector2.from_angle(radians) * float(distance)
			if world.is_water(point.x, point.y):
				return point
	return Vector2.INF


static func validate_start(world, player_position: Vector3, backpack) -> Dictionary:
	if backpack.best_tool("fishing") == "":
		return {"ok": false, "reason": "need_rod"}
	var water := water_near(world, player_position)
	if water == Vector2.INF:
		return {"ok": false, "reason": "need_water"}
	if backpack.free_space_for(CATCH_ID) <= 0:
		return {"ok": false, "reason": "no_space"}
	return {"ok": true, "water_x": water.x, "water_z": water.y,
		"seconds": CAST_SECONDS}
