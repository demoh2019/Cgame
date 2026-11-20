extends RefCounted
## Storm-driven fuel burn is server-authoritative and replicated only nearby.
const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")
const Weather = preload("res://scripts/shared/weather.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Net = preload("res://scripts/shared/net.gd")


func run(t) -> void:
	t.current = "storm fuel burn is bounded and deterministic"
	t.near(FieldCampfire.storm_extra_fuel(4.0, {"condition": "storm", "sheltered": false}),
		4.0, 0.001, "storm doubles fuel use")
	t.near(FieldCampfire.storm_extra_fuel(4.0, {"condition": "clear"}), 0.0,
		0.001, "clear weather has no fuel penalty")
	t.near(FieldCampfire.storm_extra_fuel(4.0, {"condition": "storm", "sheltered": true}),
		0.0, 0.001, "shelter removes storm penalty")
	for bad in [-1.0, 0.0, INF, NAN]:
		t.near(FieldCampfire.storm_extra_fuel(bad, {"condition": "storm"}), 0.0,
			0.001, "invalid simulation tick cannot burn fuel")
	t.current = "authoritative storm exhausts a temporary campfire"
	var world := WorldGen.new(198)
	var sim := GameServer.new(world, 198)
	var position := Vector2(730.0, 700.0)
	var near = sim.add_player(1, "Near camp")
	var far = sim.add_player(2, "Far camp")
	near.position = Vector3(position.x, world.height_at(position.x, position.y), position.y)
	far.position = Vector3(930.0, world.height_at(930.0, 700.0), 700.0)
	var storm_time := -1.0
	var clear_time := -1.0
	for phase in range(100):
		var sample := float(phase) * Weather.CHANGE_SECONDS + 1.0
		var condition: String = str(Weather.conditions(world, position.x, position.y,
			sample).get("condition", ""))
		if condition == "storm" and storm_time < 0.0:
			storm_time = sample
		elif condition == "clear" and clear_time < 0.0:
			clear_time = sample
		if storm_time >= 0.0 and clear_time >= 0.0:
			break
	t.check(storm_time >= 0.0 and clear_time >= 0.0,
		"both kinds of weather occur in the deterministic timeline")
	if storm_time < 0.0 or clear_time < 0.0:
		return
	sim.time = storm_time
	var id := 3901
	var fuel_before: Dictionary = near.inventory.to_dict()
	sim.campfires[id] = {"id": id, "x": position.x, "y": near.position.y,
		"z": position.y, "expires": sim.time + 0.75, "owner": 1}
	t.check(FieldCampfire.has_warmth(sim.campfires, near.position, sim.time),
		"fresh campfire provides warmth")
	sim._tick_world(1.0)
	t.check(not sim.campfires.has(id), "extra storm fuel use puts the fire out")
	t.check(not FieldCampfire.has_warmth(sim.campfires, near.position, sim.time),
		"extinguished fire loses shelter immediately")
	t.eq(near.inventory.to_dict(), fuel_before, "weather cannot spend backpack items")
	var found := false
	var doused: Dictionary = {}
	for event in sim.events:
		if event.get("type", "") == "campfire_doused":
			found = true
			doused = event
	t.check(found, "nearby clients can be notified of storm burnout")
	if found:
		var net := Net.new()
		net.role = "server"
		net.sim = sim
		t.check(net._event_visible_to(doused, 1), "nearby survivor sees event")
		t.check(not net._event_visible_to(doused, 2), "distant player does not")
		net.free()
	t.current = "clear weather retains ordinary burn duration"
	sim.events.clear()
	sim.time = clear_time
	sim.campfires[id] = {"id": id, "x": position.x, "y": near.position.y,
		"z": position.y, "expires": sim.time + 2.0, "owner": 1}
	sim._tick_world(1.0)
	t.check(sim.campfires.has(id), "fire survives an ordinary clear-weather tick")
	t.near(float(sim.campfires[id]["expires"]) - sim.time, 2.0,
		0.001, "clear weather cannot consume extra fuel")
	t.eq(sim.events.size(), 0, "no false storm notification")
