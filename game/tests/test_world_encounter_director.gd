extends RefCounted
## Regression tests for authoritative, pressure-aware world incidents.
## Loaded by res://tests/run_all.gd; no network connection is required.

const Director = preload("res://scripts/shared/world_encounter_director.gd")
const WorldIncidents = preload("res://scripts/shared/world_incidents.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func run(t) -> void:
	t.current = "encounter budget: global cap, zone, health and nearby pressure"
	t.eq(Director.spawn_budget(0, 0, 1.0, 0), 7,
		"quiet green zone retains meaningful encounters")
	t.eq(Director.spawn_budget(0, 0, 1.0, 3), 10,
		"black-zone base wave stays bounded")
	t.eq(Director.spawn_budget(0, 8, 1.0, 3), 4,
		"a nearby pack reduces reinforcement pressure")
	t.eq(Director.spawn_budget(0, 12, 1.0, 3), 2,
		"crowded regions admit only tiny reinforcements")
	t.eq(Director.spawn_budget(0, 20, 1.0, 3), 0,
		"hard local crowd cap blocks additional incidents")
	t.eq(Director.spawn_budget(0, 0, 0.20, 3), 2,
		"a badly wounded survivor receives an easier wave")
	t.eq(Director.spawn_budget(0, 0, 0.50, 3), 4,
		"half-health survivor receives reduced pressure")
	t.eq(Director.spawn_budget(0, 0, NAN, 3), 0,
		"nonfinite survivor health cannot mint an encounter")
	t.eq(Director.spawn_budget(-1, 0, 1.0, 3), 0,
		"invalid global count fails closed")
	t.eq(Director.spawn_budget(WorldIncidents.MAX_ACTIVE_INFECTED, 0, 1.0, 3), 0,
		"full server refuses new enemies")
	t.eq(Director.spawn_budget(WorldIncidents.MAX_ACTIVE_INFECTED - 1, 0, 1.0, 3), 1,
		"only one remaining global slot may be used")

	t.current = "deterministic roster cropping and bounded respite"
	var roster: Array = ["howler", "runner", "walker", "brute"]
	t.eq(Director.bounded_roster(roster, 2), ["howler", "runner"],
		"first scripted encounter unit stays in front")
	t.eq(Director.bounded_roster(roster, -1), [],
		"invalid negative cap cannot spawn enemies")
	t.eq(roster.size(), 4, "roster cropping does not mutate original")
	t.near(Director.respite_seconds(100.0, 0, 1.0), 100.0, 0.001,
		"calm scene keeps original cooldown")
	t.near(Director.respite_seconds(100.0, 8, 1.0), 120.0, 0.001,
		"pressure extends the cooldown")
	t.near(Director.respite_seconds(100.0, 12, 0.20), 175.0, 0.001,
		"wounded survivor in dense crowd gets bounded recovery")
	t.eq(Director.respite_seconds(NAN, 0, 1.0), 0.0,
		"nonfinite timers cannot escape the guard")

	t.current = "nearby infected: only living neighbors count"
	var enemies: Dictionary = {}
	enemies[1] = Zombie.new(1, "walker", Vector3(2.0, 0.0, 0.0))
	enemies[2] = Zombie.new(2, "runner", Vector3(200.0, 0.0, 0.0))
	enemies[3] = Zombie.new(3, "walker", Vector3(3.0, 0.0, 0.0))
	enemies[3].state = Zombie.State.DEAD
	t.eq(Director.nearby_infected(enemies, Vector3.ZERO), 1,
		"dead and faraway infected do not count as local pressure")
	t.eq(Director.nearby_infected(enemies, Vector3.INF), Director.LOCAL_HARD_CAP,
		"invalid source positions fail closed")

	t.current = "integration: authoritative GameServer refuses saturated crowds"
	var world := WorldGen.new(17417)
	var server := GameServer.new(world, 17417)
	var survivor = server.add_player(81, "Explorer")
	survivor.position = Vector3(350.0, world.height_at(350.0, 350.0), 350.0)
	t.check(not world.is_safe(survivor.position.x, survivor.position.z),
		"test survivor is outside safe hub")
	for i in Director.LOCAL_HARD_CAP:
		var id: int = server.new_id()
		server.zombies[id] = Zombie.new(id, "walker",
			survivor.position + Vector3(float(i % 5), 0.0, float(i / 5)))
	var count_before: int = server.zombies.size()
	var events_before: int = server.events.size()
	server.time = 1000.0
	server.next_incident_at = 0.0
	server._tick_world_incidents()
	t.eq(server.zombies.size(), count_before,
		"server does not spawn incident into saturated local area")
	t.eq(server.events.size(), events_before,
		"blocked incident does not announce a fake wave")
	t.near(server.next_incident_at, 1000.0 + WorldIncidents.RETRY_SECONDS, 0.001,
		"saturated events retry later instead of spinning each server tick")
