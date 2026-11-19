extends RefCounted
## Real authoritative player input/shot noise and hearing expiry.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func run(t) -> void:
	t.current = "sprint sound from validated movement"
	var world := WorldGen.new(42)
	var server := GameServer.new(world, 11)
	var player = server.add_player(910, "Stealth Tester")
	player.position = Vector3(0.0, world.height_at(0.0, 0.0), 0.0)
	player.input_budget = 0.25
	var old_position: Vector3 = player.position
	server.submit_input(910, 1, 1.0, 0.0, true, 0.0, 0.1)
	t.check(player.position.distance_to(old_position) > 0.01, "server accepted running movement")
	t.near(player.noise_radius, Defs.SPRINT_NOISE_RADIUS, 0.00001, "moving sprint produces footsteps")
	var old_noise: float = player.noise_radius
	server.submit_input(910, 1, 1.0, 0.0, true, 0.0, 0.1)
	t.near(player.noise_radius, old_noise, 0.00001, "replayed input does not change sound")
	server._tick_players(Defs.SPRINT_NOISE_SECONDS + 0.05)
	t.near(player.noise_radius, 0.0, 0.00001, "footsteps fade after sprint stops")

	t.current = "gunshot needs real ammo"
	player.inventory.add("pistol", 1)
	player.inventory.equip("pistol")
	var dry: Dictionary = server.cmd_attack(910, 1.0, 0.0)
	t.eq(dry["reason"], "no_ammo", "unloaded gun cannot shoot")
	t.near(player.noise_radius, 0.0, 0.00001, "dry firing does not attract enemies")
	player.attack_timer = 0.0
	player.inventory.add("ammo_9mm", 1)
	var shot: Dictionary = server.cmd_attack(910, 1.0, 0.0)
	t.check(shot["ok"], "loaded pistol fires")
	t.eq(player.inventory.count("ammo_9mm"), 0, "shot consumes ammunition")
	t.near(player.noise_radius, Defs.GUNSHOT_NOISE_RADIUS, 0.00001, "shot produces long-range noise")
	t.check(player.noise_timer >= Defs.GUNSHOT_NOISE_SECONDS, "gunshot persists briefly")

	t.current = "server sends sound to zombie AI"
	player.position = Vector3(310.0, world.height_at(310.0, 310.0), 310.0)
	var zombie = Zombie.new(server.new_id(), "walker", Vector3(340.0, world.height_at(340.0, 310.0), 310.0))
	server.zombies[zombie.id] = zombie
	server._tick_zombies(0.1)
	t.eq(zombie.target_id, 910, "server-generated shot noise triggers zombie aggro")
	server._tick_players(Defs.GUNSHOT_NOISE_SECONDS + 0.1)
	t.near(player.noise_radius, 0.0, 0.00001, "gunshot expires on server")
	var new_zombie = Zombie.new(server.new_id(), "walker", Vector3(340.0, world.height_at(340.0, 310.0), 310.0))
	server.zombies[new_zombie.id] = new_zombie
	server._tick_zombies(0.1)
	t.eq(new_zombie.target_id, -1, "expired shot is not heard by newly spawned infected")
	var persistent: Dictionary = server.character_data(player)
	t.check(not persistent.has("noise_radius") and not persistent.has("noise_timer"), "temporary noise is not persistent character data")
