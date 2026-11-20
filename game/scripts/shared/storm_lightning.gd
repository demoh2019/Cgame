extends RefCounted
## Server-generated, telegraphed environmental lightning during real storms.
## Hit checks use the actual survivor position at impact, never RPC coordinates.
const Weather = preload("res://scripts/shared/weather.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const WARNING_SECONDS := 2.8
const CHECK_INTERVAL := 55.0
const RETRY_INTERVAL := 10.0
const RADIUS := 4.0
const DAMAGE := 16.0
const MAX_OFFSET := 1.8


static func create_warning(world, position: Vector3, now: float) -> Dictionary:
	if not position.is_finite() or not is_finite(now) or now < 0.0 or \
			world.is_safe(position.x, position.z) or \
			world.zone_at(position.x, position.z) < 1:
		return {}
	var conditions: Dictionary = Weather.conditions(world, position.x, position.z, now)
	if str(conditions.get("condition", "")) != "storm" or \
			bool(conditions.get("sheltered", false)):
		return {}
	var cell_x: int = floori(position.x / 32.0)
	var cell_z: int = floori(position.z / 32.0)
	var epoch: int = floori(now / CHECK_INTERVAL)
	var seed: int = WorldGen.mix(cell_x, cell_z, int(world.world_seed), epoch + 9141)
	var angle: float = TAU * float(seed % 360) / 360.0
	var at: Vector2 = Vector2(position.x, position.z) + \
		Vector2.from_angle(angle) * MAX_OFFSET
	if world.is_water(at.x, at.y) or world.is_safe(at.x, at.y):
		return {}
	return {"x": at.x, "z": at.y, "y": world.height_at(at.x, at.y),
		"at": now + WARNING_SECONDS, "radius": RADIUS}


static func strike_valid(world, strike: Dictionary, now: float) -> bool:
	if strike.is_empty() or not is_finite(now):
		return false
	for key in ["x", "z", "y", "at"]:
		if not strike.has(key) or not (strike[key] is float or strike[key] is int) or \
				not is_finite(float(strike[key])):
			return false
	if now < float(strike["at"]):
		return false
	var x: float = float(strike["x"])
	var z: float = float(strike["z"])
	if world.is_safe(x, z) or world.is_water(x, z):
		return false
	var conditions: Dictionary = Weather.conditions(world, x, z, now)
	return str(conditions.get("condition", "")) == "storm" and \
		not bool(conditions.get("sheltered", false))


static func in_blast(center: Vector2, position: Vector3) -> bool:
	return center.is_finite() and position.is_finite() and \
		center.distance_squared_to(Vector2(position.x, position.z)) <= RADIUS * RADIUS
