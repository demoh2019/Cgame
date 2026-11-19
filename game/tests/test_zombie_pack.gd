extends RefCounted
## Pack-alert integration with the authoritative survival server.
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func run(t) -> void:
	t.current = "proximity pack alert"
	var world := WorldGen.new(22)
	var server := GameServer.new(world, 31)
	var survivor = server.add_player(70, "Loud Survivor")
	# Teleport in a test only. All production AI target positions originate on server.
	survivor.position = Vector3(210, world.height_at(210, 210), 210)
	var source = Zombie.new(server.new_id(), "walker", Vector3(220, world.height_at(220, 210), 210))
	var helper = Zombie.new(server.new_id(), "walker", Vector3(236, world.height_at(236, 210), 210))
	var far = Zombie.new(server.new_id(), "walker", Vector3(251, world.height_at(251, 210), 210))
	server.zombies[source.id] = source
	server.zombies[helper.id] = helper
	server.zombies[far.id] = far
	# An unaided helper 26 m from a quiet survivor does not notice them.
	t.eq(helper.target_id, -1, "helper starts without a target")
	server.tick_count = 0
	server._tick_zombies(0.05)
	t.eq(source.target_id, 70, "scout independently finds survivor")
	t.eq(helper.target_id, 70, "neighboring infected receives peer target")
	t.eq(helper.state, Zombie.State.CHASE, "helper joins pursuit")
	t.eq(far.target_id, -1, "distant infected does not hear pack communication")

	t.current = "safe hub and expired target"
	var protected = server.add_player(71, "Safe")
	protected.position = Vector3(0, world.height_at(0, 0), 0)
	var guard = Zombie.new(server.new_id(), "walker", Vector3(8, world.height_at(8, 0), 0))
	var wing = Zombie.new(server.new_id(), "walker", Vector3(19, world.height_at(19, 0), 0))
	server.zombies[guard.id] = guard
	server.zombies[wing.id] = wing
	server._tick_zombies(0.05)
	t.eq(guard.target_id, -1, "infected cannot recruit against survivor in safe hub")
	t.eq(wing.target_id, -1, "pack alert cannot bypass hub protection")
	survivor.survival.hurt(1000.0)
	server._tick_zombies(0.05)
	t.check(helper.target_id == -1 or helper.state == Zombie.State.IDLE, "dead target is dropped by recruited infected")
