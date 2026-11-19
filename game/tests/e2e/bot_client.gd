extends SceneTree
## A headless player that follows a script and checks what the real server tells it.
##   godot --headless --path game --script res://tests/e2e/bot_client.gd -- --scenario solo --port 24565
## Exits 0 when every check passed, 1 otherwise.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Net = preload("res://scripts/shared/net.gd")
const GameClient = preload("res://scripts/client/game_client.gd")
const NakamaScript = preload("res://addons/com.heroiclabs.nakama/Nakama.gd")
const GameServerConstants = preload("res://tests/e2e/constants.gd")

var net
var client
var peer: ENetMultiplayerPeer
var scenario := "solo"
var bot_name := "Bot"
var nakama_address := ""
var device_id := ""
var returning := false # A returning player keeps their character, so skip the fresh-spawn checks.
var session
var failures: Array[String] = []
var checks := 0
const STEP := 1.0 / 30.0


func _initialize() -> void:
	var port := 24565
	var host := "127.0.0.1"
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--scenario":
				i += 1
				scenario = args[i]
			"--port":
				i += 1
				port = int(args[i])
			"--name":
				i += 1
				bot_name = args[i]
			"--nakama":
				i += 1
				nakama_address = args[i]
			"--returning":
				returning = true
			"--device":
				i += 1
				device_id = args[i]
		i += 1
	Engine.physics_ticks_per_second = 30
	net = Net.new()
	net.name = "Net"
	net.role = "client"
	root.add_child(net)
	client = GameClient.new(net)
	peer = ENetMultiplayerPeer.new()
	if peer.create_client(host, port) != OK:
		_finish("could not create the client")
		return
	get_multiplayer().multiplayer_peer = peer
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("BOT %s CHECK FAILED: %s" % [bot_name, message])


func _finish(reason: String = "") -> void:
	if reason != "":
		failures.append(reason)
	if failures.is_empty():
		print("BOT %s PASS (%d checks)" % [bot_name, checks])
	else:
		print("BOT %s FAIL: %s" % [bot_name, "; ".join(failures)])
	quit(0 if failures.is_empty() else 1)


# Waits for a condition, one physics frame at a time. Returns whether it became true in time.
func until(condition: Callable, seconds: float) -> bool:
	var waited := 0.0
	while waited < seconds:
		if condition.call():
			return true
		await physics_frame
		waited += STEP
	return condition.call()


func walk_to(target: Vector2, seconds: float, sprint: bool = true, stop_distance: float = 1.2) -> bool:
	var waited := 0.0
	while waited < seconds:
		var here := Vector2(client.predicted.x, client.predicted.z)
		var offset := target - here
		if offset.length() <= stop_distance:
			return true
		var direction := offset.normalized()
		client.send_input(direction, sprint, atan2(direction.x, direction.y), STEP)
		await physics_frame
		client.decay_correction(STEP)
		waited += STEP
	return false


func here() -> Vector2:
	return Vector2(client.predicted.x, client.predicted.z)


func debug(command: String, args: Dictionary = {}) -> void:
	net.c_debug.rpc_id(1, command, args)


func teleport(x: float, z: float) -> void:
	debug("teleport", {"x": x, "z": z})
	# The server moves us at its next tick; wait until a snapshot shows it and prediction follows.
	await until(func() -> bool: return Vector2(client.you.get("x", 0.0), client.you.get("z", 0.0)).distance_to(Vector2(x, z)) < 1.0, 4.0)
	client.predicted = Vector3(client.you["x"], client.you["y"], client.you["z"])
	client._pending.clear()


func _run() -> void:
	var connected := await until(func() -> bool: return get_multiplayer().multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, 6.0)
	check(connected, "connected to the server")
	if not connected:
		_finish()
		return
	var token := ""
	var refresh := ""
	if nakama_address != "":
		var nakama = NakamaScript.new()
		root.add_child(nakama)
		var parts := nakama_address.split(":")
		var nakama_client = nakama.create_client("albion_after_key", parts[0], int(parts[1]), "http", 10, NakamaLogger.LOG_LEVEL.ERROR)
		session = await nakama_client.authenticate_device_async(device_id, bot_name, true)
		check(not session.is_exception(), "signed in to Nakama")
		if session.is_exception():
			_finish()
			return
		token = session.token
		refresh = session.refresh_token
	client.join(bot_name, token, refresh)
	check(await until(func() -> bool: return client.welcomed and client.snapshots_received > 0, 6.0), "welcome and first snapshot")
	if not client.welcomed:
		_finish()
		return
	check(client.world.world_seed == 1337, "the client built the world from the server's seed")
	check(client.you.get("alive", false), "alive after joining")
	if not returning:
		check(Vector2(client.you["x"], client.you["z"]).length() < Defs.HUB_SAFE_RADIUS, "spawned inside the hub")
		check(client.inventory.count("canned_food") == 2, "the starter kit arrived")
	client.predicted = Vector3(client.you["x"], client.you["y"], client.you["z"])
	match scenario:
		"solo":
			await _scenario_solo()
		"victim":
			await _scenario_victim()
		"killer":
			await _scenario_killer()
		"idle":
			await until(func() -> bool: return false, 3.0)
		"skills":
			await _scenario_skills()
		"persist1":
			await _scenario_persist1()
		"persist2":
			await _scenario_persist2()
		"refused":
			pass
	_finish()


# --- Scenarios ---------------------------------------------------------------------------------------------

func _scenario_solo() -> void:
	# 1. Walk for real and check that prediction and server agree.
	var start := here()
	# Walk to the fountain at the center of the hub (the spawn point is random, and houses stand beyond it).
	var reached := await walk_to(Vector2(-4.0, 3.0), 14.0)
	check(reached, "walked to the fountain inside the hub")
	await until(func() -> bool: return client.snapshots_received > 20, 3.0)
	await until(func() -> bool: return Vector2(client.you["x"], client.you["z"]).distance_to(here()) < 0.8, 2.0)
	var gap := Vector2(client.you["x"], client.you["z"]).distance_to(here())
	check(gap < 0.8, "prediction and the server agree after walking (gap %.2f m, worst correction %.2f m)" % [gap, client.worst_error])
	check(client.worst_error < 1.5, "the server never disagreed by more than 1.5 m (%.2f)" % client.worst_error)

	# 2. Gather: find a tier 1 tree near the hub, walk to it and chop it with bare hands.
	var tree := {}
	var best := INF
	for cx in range(-6, 7):
		for cz in range(-6, 7):
			for node in client.world.chunk(Vector2i(cx, cz))["nodes"]:
				if node["kind"] == "tree" and node["tier"] == 1:
					var d := Vector2(node["x"], node["z"]).length()
					if d > 60.0 and d < best:
						tree = node
						best = d
	check(not tree.is_empty(), "found a tree to chop")
	await teleport(tree["x"] - 2.0, tree["z"])
	var reach := await walk_to(Vector2(tree["x"] - 1.6, tree["z"]), 4.0, false, 0.4)
	client.gather(tree["id"])
	check(await until(func() -> bool: return client.last_results.has("gather"), 3.0), "the server answered the gather command")
	check(client.last_results.get("gather", {}).get("ok", false), "gathering was accepted: %s" % str(client.last_results.get("gather")))
	check(await until(func() -> bool: return client.inventory.count("wood_1") >= 3, 14.0), "wood arrived in the inventory")
	check(await until(func() -> bool: return client.depleted.has(tree["id"]), 3.0), "the tree shows as depleted")

	# 3. Craft at the workbench.
	await teleport(GameServerConstants.WORKBENCH.x + 2.0, GameServerConstants.WORKBENCH.y)
	var wood_before: int = client.inventory.count("wood_1")
	client.craft("plank_1", 1)
	check(await until(func() -> bool: return client.inventory.count("plank_1") >= 1, 4.0), "a plank was crafted at the workbench")
	check(client.inventory.count("wood_1") == wood_before - 2, "two wood were used")
	await teleport(100.0, 100.0)
	client.last_results.erase("craft")
	client.craft("plank_1", 1)
	check(await until(func() -> bool: return client.last_results.has("craft"), 3.0), "the server answers a refused craft")
	check(client.last_results["craft"].get("reason", "") == "no_station", "crafting away from the workbench is refused")

	# 4. Fight a zombie outside the hub.
	await teleport(260.0, 260.0)
	debug("give", {"item": "club_2", "count": 1})
	debug("zombie", {"type": "walker", "x": 262.0, "z": 260.0})
	check(await until(func() -> bool: return client.inventory.count("club_2") == 1 and client.zombies.size() > 0, 4.0), "got a club and see the zombie")
	client.use_item("club_2")
	await until(func() -> bool: return client.you.get("weapon", "") == "club_2", 3.0)
	check(client.you.get("weapon", "") == "club_2", "the club is equipped")
	# The zombie we spawned is the one closest to the spot we put it at (the world has its own too).
	var victim_id := -1
	var closest := INF
	for z in client.zombies.values():
		var d := Vector2(z["x"], z["z"]).distance_to(Vector2(262.0, 260.0))
		if d < closest:
			closest = d
			victim_id = z["id"]
	check(victim_id != -1 and closest < 4.0, "found the zombie that was spawned (%.1f m from the spot)" % closest)
	var killed := false
	for i in 160:
		if not client.zombies.has(victim_id):
			killed = true
			break
		var target: Dictionary = client.zombies[victim_id]
		var offset := Vector2(target["x"], target["z"]) - here()
		if offset.length() > 1.8:
			client.send_input(offset.normalized(), false, atan2(offset.x, offset.y), STEP)
		else:
			client.attack(offset.normalized())
		await until(func() -> bool: return false, 0.2)
	check(killed, "the zombie was killed")
	check(client.you["kills"] >= 1, "the kill is counted on the server")
	check(await until(func() -> bool: return client.bags.size() > 0, 3.0), "the zombie dropped loot")
	var silver_before: int = client.inventory.count("silver")
	var loot: Dictionary = client.nearest_loot(client.predicted, 8.0)
	check(not loot.is_empty(), "the loot bag is near")
	if not loot.is_empty():
		await walk_to(Vector2(loot["x"], loot["z"]), 5.0, false, 1.5)
		client.loot(loot["id"])
		check(await until(func() -> bool: return client.inventory.count("silver") > silver_before, 3.0), "looting the bag gave silver")

	# 5. Die with items in the red zone: they must be gone, and the player must come back in the hub.
	await teleport(600.0, 600.0)
	debug("give", {"item": "silver", "count": 40})
	await until(func() -> bool: return client.inventory.count("silver") > 40, 3.0)
	debug("hurt", {"amount": 1000.0})
	check(await until(func() -> bool: return not client.you.get("alive", true), 3.0), "the player died")
	check(await until(func() -> bool: return client.you.get("alive", false) and client.inventory.count("silver") == 0, Defs.RESPAWN_SECONDS + 4.0), "respawned with an empty pack (full loot)")
	check(client.inventory.count("canned_food") == 2, "and a fresh starter kit")
	await until(func() -> bool: return Vector2(client.you["x"], client.you["z"]).length() < Defs.HUB_SAFE_RADIUS, 2.0)
	check(Vector2(client.you["x"], client.you["z"]).length() < Defs.HUB_SAFE_RADIUS, "back in the hub")


func _scenario_victim() -> void:
	await teleport(600.0, 600.0) # Red zone: PvP and full loot only apply from there.
	debug("give", {"item": "silver", "count": 50})
	check(await until(func() -> bool: return client.inventory.count("silver") >= 50, 4.0), "has silver to lose")
	check(await until(func() -> bool: return not client.you.get("alive", true), 25.0), "was killed by the other player")
	var death_heard := false
	for event in client.events:
		if event["type"] == "death":
			death_heard = true
	check(death_heard, "heard about the death")
	check(await until(func() -> bool: return client.you.get("alive", false) and client.inventory.count("silver") == 0, 10.0), "respawned with nothing")


func _scenario_killer() -> void:
	await teleport(601.0, 600.0)
	debug("give", {"item": "club_3", "count": 1})
	await until(func() -> bool: return client.inventory.count("club_3") == 1, 3.0)
	client.use_item("club_3")
	await until(func() -> bool: return client.you.get("weapon", "") == "club_3", 3.0)
	check(await until(func() -> bool: return client.players.size() > 0, 12.0), "sees the other player")
	var dead := false
	for i in 200:
		var victim := {}
		for p in client.players.values():
			victim = p
		if victim.is_empty() or not victim["alive"]:
			dead = not victim.is_empty() and not victim["alive"]
			if dead:
				break
		else:
			var offset := Vector2(victim["x"], victim["z"]) - here()
			if offset.length() > 1.6:
				client.send_input(offset.normalized(), false, atan2(offset.x, offset.y), STEP)
			else:
				client.attack(offset.normalized())
		await until(func() -> bool: return false, 0.2)
	check(dead, "killed the other player")
	check(await until(func() -> bool: return client.bags.size() > 0, 3.0), "the victim's things are on the ground")
	var loot: Dictionary = client.nearest_loot(client.predicted, 10.0)
	check(not loot.is_empty(), "found the bag")
	if not loot.is_empty():
		await walk_to(Vector2(loot["x"], loot["z"]), 5.0, false, 1.5)
		client.loot(loot["id"])
		check(await until(func() -> bool: return client.inventory.count("silver") >= 50, 3.0), "took the victim's silver")


# --- Persistence scenarios (need Nakama) ----------------------------------------------------------------------

func _scenario_persist1() -> void:
	check(client.inventory.count("silver") == 0, "a brand new account starts without silver")
	debug("xp", {"skill": "melee", "amount": 3000})
	check(await until(func() -> bool: return client.skills.level("melee") >= 8, 4.0), "melee trained to level 8")
	client.buy_perk("heavy_hands")
	check(await until(func() -> bool: return client.skills.rank("heavy_hands") == 1, 4.0), "bought a perk")
	debug("give", {"item": "silver", "count": 123})
	debug("give", {"item": "club_3", "count": 1})
	check(await until(func() -> bool: return client.inventory.count("silver") == 123 and client.inventory.count("club_3") == 1, 4.0), "has silver and a club")
	client.use_item("club_3")
	await until(func() -> bool: return client.you.get("weapon", "") == "club_3", 3.0)
	check(client.you.get("weapon", "") == "club_3", "club equipped")
	client.use_item("canned_food")
	await until(func() -> bool: return client.inventory.count("canned_food") == 1, 3.0)
	await teleport(300.0, 300.0)
	debug("hurt", {"amount": 30.0})
	await until(func() -> bool: return client.you["health"] < 80.0, 3.0)
	check(client.you["health"] < 80.0, "took damage before leaving")
	await until(func() -> bool: return false, 0.5)


func _scenario_persist2() -> void:
	check(client.skills.level("melee") >= 8, "the melee level was kept across sessions (%d)" % client.skills.level("melee"))
	check(client.skills.rank("heavy_hands") == 1, "and the perk")
	check(client.inventory.count("silver") == 123, "the silver was kept across sessions (%d)" % client.inventory.count("silver"))
	check(client.inventory.count("club_3") == 1, "the club was kept")
	check(client.you.get("weapon", "") == "club_3", "and is still equipped")
	check(client.inventory.count("canned_food") == 1, "eaten food stays eaten")
	check(client.you["health"] < 85.0, "the injury was kept (%.0f)" % client.you["health"])
	check(Vector2(client.you["x"], client.you["z"]).distance_to(Vector2(300.0, 300.0)) < 6.0, "they reappear where they logged out")


func _scenario_skills() -> void:
	check(client.skills.level("woodcutting") == 1, "a new character starts at level 1")
	check(client.skill_points == 0, "with no points")
	# Gathering trains its skill and the server reports it.
	var tree := {}
	var best := INF
	for cx in range(-6, 7):
		for cz in range(-6, 7):
			for node in client.world.chunk(Vector2i(cx, cz))["nodes"]:
				if node["kind"] == "tree" and node["tier"] == 1:
					var d := Vector2(node["x"], node["z"]).length()
					if d > 140.0 and d < best: # A different tree than the solo bot chops.
						tree = node
						best = d
	await teleport(tree["x"] - 1.6, tree["z"])
	client.gather(tree["id"])
	check(await until(func() -> bool: return client.skills.xp["woodcutting"] > 0, 14.0), "chopping a tree trained woodcutting on the server and in the snapshot")
	var heard := func(kind: String, key: String, value: String) -> bool:
		for event in client.events:
			if event["type"] != kind or not event.has(key):
				continue
			var field: Variant = event[key]
			if field is Dictionary and field.has(value):
				return true
			if field is String and field == value:
				return true
		return false
	check(await until(func() -> bool: return heard.call("xp", "gains", "woodcutting"), 4.0), "the xp gain was announced")
	# A level up arrives as an event and as points.
	debug("xp", {"skill": "woodcutting", "amount": 1200})
	check(await until(func() -> bool: return client.skills.level("woodcutting") >= 5, 4.0), "level 5 reached")
	check(await until(func() -> bool: return heard.call("skill_up", "skill", "woodcutting"), 3.0), "the level up was announced")
	check(client.skill_points >= 4, "and gave skill points (%d)" % client.skill_points)
	# Perks: refused without the level, bought with it.
	client.last_results.erase("perk")
	client.buy_perk("forest_master")
	check(await until(func() -> bool: return client.last_results.has("perk"), 3.0), "the server answers a perk request")
	check(client.last_results["perk"].get("reason", "") == "need_level", "a perk above your level is refused")
	var points_before: int = client.skill_points
	client.last_results.erase("perk")
	client.buy_perk("sharp_axe")
	check(await until(func() -> bool: return client.skills.rank("sharp_axe") == 1, 4.0), "Sharp Axe bought")
	check(client.skill_points == points_before - 1, "and paid for")
	# Max health follows the toughness skill.
	var health_before: float = client.you["max_health"]
	debug("xp", {"skill": "toughness", "amount": 2000})
	check(await until(func() -> bool: return client.you["max_health"] > health_before, 4.0), "toughness raised the maximum health (%.1f -> %.1f)" % [health_before, client.you["max_health"]])
	# Running bonus reaches the client for prediction.
	debug("xp", {"skill": "athletics", "amount": 3000})
	check(await until(func() -> bool: return client.you.get("speed_bonus", 0.0) > 0.02, 4.0), "the speed bonus reaches the client")
