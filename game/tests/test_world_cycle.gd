extends RefCounted
## Shared world-clock math, server-sync and night-only infected detection.

const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func run(t) -> void:
	t.current = "server time is shared by day and night"
	t.near(WorldCycle.phase(0.0), 0.0, 0.0001, "fresh world begins at sunrise")
	t.near(WorldCycle.phase(WorldCycle.DAY_LENGTH * 0.25), 0.25, 0.0001, "quarter day is noon")
	t.near(WorldCycle.phase(WorldCycle.DAY_LENGTH), 0.0, 0.0001, "time loops without drift")
	t.near(WorldCycle.phase(-WorldCycle.DAY_LENGTH * 0.25), 0.75, 0.0001, "negative time wraps")
	t.near(WorldCycle.phase(INF), 0.0, 0.0001, "infinite timestamps cannot produce NaN")
	t.near(WorldCycle.daylight(WorldCycle.DAY_LENGTH * 0.25), 1.0, 0.0001, "midday is bright")
	t.near(WorldCycle.daylight(WorldCycle.DAY_LENGTH * 0.75), 0.0, 0.0001, "midnight is dark")
	t.check(not WorldCycle.is_night(WorldCycle.DAY_LENGTH * 0.25), "midday is day")
	t.check(WorldCycle.is_night(WorldCycle.DAY_LENGTH * 0.75), "midnight is night")
	t.check(not WorldCycle.is_night(WorldCycle.DAY_LENGTH), "new day starts at sunrise")
	t.check(WorldCycle.notice_multiplier(0.0) == 1.0, "day detection uses baseline")
	t.check(WorldCycle.notice_multiplier(WorldCycle.DAY_LENGTH * 0.75) > 1.0, "infected notice farther at night")

	t.current = "authoritative infected notice and protected settlements"
	var world := WorldGen.new(17)
	var server := GameServer.new(world, 17)
	var person = server.add_player(45, "Night Scout")
	person.position = Vector3(119.0, world.height_at(119.0, 100.0), 100.0)
	var z := Zombie.new(server.new_id(), "walker",
		Vector3(100.0, world.height_at(100.0, 100.0), 100.0))
	server.zombies[z.id] = z
	server.time = WorldCycle.DAY_LENGTH * 0.25
	server._tick_zombies(0.3)
	t.eq(z.target_id, -1, "quiet survivor at 19 meters is unseen by day")
	server.time = WorldCycle.DAY_LENGTH * 0.75
	server._tick_zombies(0.3)
	t.eq(z.target_id, 45, "same survivor is detected at night by the server")
	t.eq(server.snapshot_for(45)["you"]["is_night"], true, "night state comes from server time")
	server.time = WorldCycle.DAY_LENGTH * 0.25
	t.eq(server.snapshot_for(45)["you"]["is_night"], false, "day state updates in snapshot")
	z.target_id = -1
	z.state = Zombie.State.IDLE
	z.think_timer = 0.0
	person.position = Vector3(1.0, world.height_at(1.0, 0.0), 0.0)
	z.position = Vector3(0.0, world.height_at(0.0, 0.0), 0.0)
	server.time = WorldCycle.DAY_LENGTH * 0.75
	server._tick_zombies(0.3)
	t.eq(z.target_id, -1, "night bonuses cannot bypass hub safe status")
