extends RefCounted

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Movement = preload("res://scripts/shared/movement.gd")


class FlatBlockerWorld:
	extends RefCounted
	var blocker: Dictionary = {}

	func height_at(_x: float, _z: float) -> float:
		return 0.0

	func blockers_near(x: float, z: float, radius: float) -> Array:
		if blocker.is_empty():
			return []
		if absf(float(blocker["x"]) - x) <= radius + float(blocker["radius"]) and \
				absf(float(blocker["z"]) - z) <= radius + float(blocker["radius"]):
			return [blocker]
		return []


func run(t) -> void:
	var world := WorldGen.new(42)
	t.current = "speed"
	var p := Vector3(0, WorldGen.HUB_HEIGHT, 0)
	var walked := p
	for i in 30: # One second at 30 steps per second.
		walked = Movement.step(world, walked, {"x": 1.0, "z": 0.0}, 1.0 / 30.0)
	t.near(walked.x, Defs.WALK_SPEED, 0.05, "walking covers WALK_SPEED in a second")
	t.near(walked.y, world.height_at(walked.x, walked.z), 0.001, "the player stands on the ground")
	var sprinted := p
	for i in 30:
		sprinted = Movement.step(world, sprinted, {"x": 1.0, "z": 0.0, "sprint": true}, 1.0 / 30.0)
	t.near(sprinted.x, Defs.SPRINT_SPEED, 0.05, "sprinting is faster")
	var diagonal := p
	for i in 30:
		diagonal = Movement.step(world, diagonal, {"x": 1.0, "z": 1.0}, 1.0 / 30.0)
	t.near(Vector2(diagonal.x, diagonal.z).length(), Defs.WALK_SPEED, 0.05, "diagonals are not faster")
	var oversized := Movement.step(world, p, {"x": 50.0, "z": 0.0}, 0.05)
	t.near(oversized.x, Defs.WALK_SPEED * 0.05, 0.001, "an input longer than 1 is clamped")

	t.current = "lag spikes"
	var jumped := Movement.step(world, p, {"x": 1.0, "z": 0.0}, 5.0)
	t.check(jumped.x <= Defs.WALK_SPEED * Movement.MAX_DELTA + 0.001, "one huge step cannot teleport")
	t.eq(Movement.step(world, p, {"x": 1.0, "z": 0.0}, -1.0).x, p.x, "negative time does not move")
	t.eq(Movement.step(world, p, {}, 0.05), Vector3(0, world.height_at(0, 0), 0), "no input, no move")

	t.current = "determinism"
	var inputs: Array = []
	var local := RandomNumberGenerator.new()
	local.seed = 5
	for i in 200:
		inputs.append({"x": local.randf_range(-1, 1), "z": local.randf_range(-1, 1), "sprint": local.randf() < 0.3})
	var a := p
	var b := p
	for input in inputs:
		a = Movement.step(world, a, input, 1.0 / 30.0)
		b = Movement.step(world, b, input, 1.0 / 30.0)
	t.eq(a, b, "the same inputs give the same position (the basis of client prediction)")

	t.current = "obstacles"
	# Find a tree and walk straight at it: the player must stop in front of it.
	var tree := {}
	for cx in range(1, 12):
		for cz in range(1, 12):
			for node in world.chunk(Vector2i(cx, cz))["nodes"]:
				if node["kind"] == "tree" and tree.is_empty() and not world.is_water(node["x"], node["z"] - 3.0):
					tree = node
	t.check(not tree.is_empty(), "found a tree to walk into")
	if not tree.is_empty():
		var start := Vector3(tree["x"], 0, tree["z"] - 3.0)
		start.y = world.height_at(start.x, start.z)
		var q := start
		for i in 120:
			q = Movement.step(world, q, {"x": 0.0, "z": 1.0}, 1.0 / 30.0)
		var gap := Vector2(tree["x"] - q.x, tree["z"] - q.z).length()
		t.check(gap >= Defs.PLAYER_RADIUS + float(tree["radius"]) - 0.01, "a tree stops the player (gap %f)" % gap)
		t.check(q.z < tree["z"], "the player did not pass through the tree")

	t.current = "authoritative model footprints"
	var building := {"kind": "building", "scale": 6.0, "yaw": 0.0,
		"x": 0.0, "z": 0.0, "radius": 3.72}
	# A circular 3.72 m blocker misses the visible 7 x 7 m house corners.
	t.check(Movement.overlaps_blocker(Vector2(3.2, 3.2), building),
		"house corner has a solid footprint beyond the old circular blocker")
	t.check(not Movement.overlaps_blocker(Vector2(4.1, 4.1), building),
		"outside the house and player radius is traversable")
	var wall := {"kind": "wall", "scale": 3.0, "yaw": PI / 4.0,
		"x": 0.0, "z": 0.0, "radius": 1.8}
	var turn := Basis(Vector3.UP, PI / 4.0)
	var along: Vector3 = turn * Vector3(1.8, 0.0, 0.0)
	var across: Vector3 = turn * Vector3(0.0, 0.0, 2.3)
	t.check(Movement.overlaps_blocker(Vector2(along.x, along.z), wall),
		"oriented wall remains solid near its end")
	t.check(not Movement.overlaps_blocker(Vector2(across.x, across.z), wall),
		"a thin wall does not block a clear path beside it")
	var tree := {"kind": "tree", "x": 0.0, "z": 0.0, "radius": 0.5}
	t.check(Movement.overlaps_blocker(Vector2(0.9, 0.0), tree),
		"trees retain their circular collision")

	t.current = "swept movement across small models"
	var flat := FlatBlockerWorld.new()
	flat.blocker = {"kind": "crate", "x": 0.0, "z": 0.0, "radius": 0.15}
	var jumped_crate: Vector3 = Movement.move(flat, Vector3(-1.0, 0.0, 0.0),
		Vector2.RIGHT, 30.0, 0.1)
	t.check(jumped_crate.x < -0.5,
		"fast movement cannot tunnel from one side of a narrow model to the other")
	flat.blocker = building
	var corner_hit: Vector3 = Movement.move(flat, Vector3(-5.0, 0.0, 3.2),
		Vector2.RIGHT, 30.0, 0.1)
	t.check(corner_hit.x < -3.9,
		"swept movement stops before a house corner")

	t.current = "raid and supply point-collision compatibility"
	flat.blocker = {"kind": "crate", "x": 0.0, "z": 0.0, "radius": 0.15}
	t.check(not Movement._is_free(flat, Vector2.ZERO),
		"two-argument spawn check detects a solid obstacle")
	t.check(Movement._is_free(flat, Vector2(5.0, 0.0)),
		"two-argument spawn check accepts open ground")
	t.check(not Movement._is_free(flat, Vector2.ZERO, false, [flat.blocker]),
		"locomotion can pass a precomputed blocker array")
	t.check(Movement._is_free(flat, Vector2.ZERO, false, []),
		"an intentionally empty cached blocker array does not trigger a second world query")
	flat.free()

	t.current = "water"
	# Walk toward the open water from the shore: wading is allowed, deep water is not.
	var shore := Vector3.INF
	var direction := Vector2.ZERO
	for angle in 72:
		var d := Vector2.from_angle(angle * TAU / 72.0)
		var distance := 100.0
		while distance < 2500.0 and shore == Vector3.INF:
			var point := d * distance
			if world.height_at(point.x, point.y) < Defs.WATER_LEVEL - 0.3 and world.height_at(point.x - d.x * 4.0, point.y - d.y * 4.0) > 0.5:
				shore = Vector3(point.x - d.x * 6.0, 0.0, point.y - d.y * 6.0)
				direction = d
			distance += 6.0
		if shore != Vector3.INF:
			break
	t.check(shore != Vector3.INF, "found a shore")
	if shore != Vector3.INF:
		var swimmer := Vector3(shore.x, world.height_at(shore.x, shore.z), shore.z)
		for i in 900:
			swimmer = Movement.step(world, swimmer, {"x": direction.x, "z": direction.y}, 1.0 / 30.0)
		t.check(world.height_at(swimmer.x, swimmer.z) >= Defs.WATER_LEVEL - 1.05, "the player cannot walk into deep water")
