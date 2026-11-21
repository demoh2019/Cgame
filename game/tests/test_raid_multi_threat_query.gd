extends RefCounted
## Multi-player encounter tactical position scoring with native EQS parity.
const Reinforcements = preload("res://scripts/shared/raid_reinforcements.gd")


class FlatWorld:
	extends RefCounted
	func zone_at(_x: float, _z: float) -> int:
		return 2
	func is_safe(_x: float, _z: float) -> bool:
		return false
	func is_water(_x: float, _z: float) -> bool:
		return false
	func height_at(_x: float, _z: float) -> float:
		return 3.0
	func blockers_near(_x: float, _z: float, _r: float) -> Array:
		return []


class Survivor:
	extends RefCounted
	var alive: bool = true


class Player:
	extends RefCounted
	var survival := Survivor.new()
	var position: Vector3
	func _init(p_position: Vector3) -> void:
		position = p_position


func run(t) -> void:
	t.current = "nearest of multiple raid threat contexts determines tactical score"
	var candidates: Array[Vector2] = [
		Vector2(1, 0), Vector2(-1, 0), Vector2(0, 10), Vector2(0, -10)]
	var players: Array[Vector2] = [Vector2.ZERO, Vector2(0, 9)]
	var reversed: Array[Vector2] = [Vector2(0, 9), Vector2.ZERO]
	var empty: Array[Vector2] = []
	var invalid: Array[Vector2] = [Vector2(INF, 0)]
	var expected: Array[Vector2] = [
		Vector2(0, -10), Vector2(1, 0), Vector2(-1, 0), Vector2(0, 10)]
	t.eq(Reinforcements.rank_sites(candidates, players, Vector2.ZERO), expected,
		"farthest point from its nearest player is selected before a crowded one")
	t.eq(Reinforcements.rank_sites(candidates, players, Vector2.ZERO, false), expected,
		"portable GDScript fallback chooses exactly the same safe points")
	t.eq(Reinforcements.rank_sites(candidates, players, Vector2.ZERO),
		Reinforcements.rank_sites(candidates, players, Vector2.ZERO, false),
		"native and portable ranking have identical candidate order")
	t.eq(Reinforcements.rank_sites(candidates, reversed, Vector2.ZERO), expected,
		"switching player insertion order does not affect rankings")
	t.eq(Reinforcements.rank_sites(candidates, empty, Vector2.ZERO), candidates,
		"empty player context preserves deterministic pre-existing candidate order")
	t.eq(Reinforcements.rank_sites(candidates, invalid, Vector2.ZERO),
		candidates, "invalid player positions never enter the scoring system")
	t.eq(Reinforcements.rank_sites(candidates, players, Vector2(NAN, 0)),
		[], "invalid query origins cannot generate positions")
	t.eq(Reinforcements.rank_sites(invalid, players, Vector2.ZERO),
		[], "nonfinite candidate coordinates are ignored")

	t.current = "Cgame multi-actor EQS and stock GDScript fallback rank the same inputs"
	if ClassDB.class_exists("EnvironmentQuery3D"):
		var query: Object = ClassDB.instantiate("EnvironmentQuery3D")
		if query != null and query.has_method("set_threat_positions"):
			var contexts := PackedVector3Array([Vector3.ZERO, Vector3(0, 40, 9)])
			query.set("candidates", PackedVector3Array([
				Vector3(1, 0, 0), Vector3(-1, 0, 0),
				Vector3(0, 0, 10), Vector3(0, 0, -10)]))
			query.set("origin", Vector3.ZERO)
			query.set("max_distance", 64.0)
			query.set("horizontal_only", true)
			query.set("use_threat", true)
			query.set("threat_positions", contexts)
			query.set("distance_weight", 0.0)
			query.set("safety_weight", 1.0)
			var result: Array = query.call("query")
			t.eq(result.size(), 4, "native EQS preserves all four safe candidates")
			t.near(float(result[0]["threat_distance"]), 10.0, 0.0001,
				"native result reports the distance to the closest threat")
			var native_positions: PackedVector3Array = query.call("query_positions")
			var native_ranked: Array[Vector2] = []
			for point in native_positions:
				native_ranked.append(Vector2(point.x, point.z))
			t.eq(native_ranked, expected,
				"native multi-context order exactly matches the portable GDScript order")
			query.set("threat_positions", PackedVector3Array())
			var cleared: PackedVector3Array = query.call("get_threat_positions")
			t.eq(cleared.size(), 0,
				"clearing multi-threat contexts restores the single-threat engine path")
		else:
			t.check(true, "pre-feature Cgame uses portable deterministic GDScript")
	else:
		t.check(true, "stock Godot uses portable deterministic GDScript")

	t.current = "real server raid reinforcement spawn sites remain safe and bounded"
	var world := FlatWorld.new()
	var near_players: Dictionary = {
		7: Player.new(Vector3(212, 3, 198)),
		2: Player.new(Vector3(203, 3, 205)),
		9: Player.new(Vector3(700, 3, 700)),
	}
	var first: Array[Vector2] = Reinforcements.sites(
		world, near_players, {}, Vector3(215, 3, 200), 1, 2)
	t.eq(first.size(), 2, "raid still finds exactly two legal add positions")
	for site in first:
		t.check(site.distance_to(Vector2(212, 198)) >= Reinforcements.MIN_PLAYER_DISTANCE,
			"ranked spawn does not bypass the closest survivor clearance")
		t.check(site.distance_to(Vector2(203, 205)) >= Reinforcements.MIN_PLAYER_DISTANCE,
			"ranked spawn does not bypass another survivor's safety exclusion")
		t.check(world.zone_at(site.x, site.y) == 2,
			"AI query only ranks previously validated dangerous-zone sites")
	t.check(first[0].distance_to(first[1]) >= Reinforcements.MIN_BETWEEN_ADDS,
		"native or script ranking cannot place reinforcements on each other")
	var reversed_players: Dictionary = {
		9: Player.new(Vector3(700, 3, 700)),
		2: Player.new(Vector3(203, 3, 205)),
		7: Player.new(Vector3(212, 3, 198)),
	}
	t.eq(Reinforcements.sites(world, reversed_players, {}, Vector3(215, 3, 200), 1, 2),
		first, "authoritative spawn order is not influenced by player dictionary ordering")
	t.eq(Reinforcements.sites(world, near_players, {}, Vector3(215, 3, 200), 0, 2),
		[], "invalid boss phases still cannot summon any adds")
