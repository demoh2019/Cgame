extends RefCounted

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Movement = preload("res://scripts/shared/movement.gd")


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
