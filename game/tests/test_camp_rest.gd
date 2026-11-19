extends RefCounted
## Bounded, server-owned sanctuary recovery with persistent cooldown.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const CampRest = preload("res://scripts/shared/camp_rest.gd")
const Defs = preload("res://scripts/shared/defs.gd")


func run(t) -> void:
	var w := WorldGen.new(83)
	var server := GameServer.new(w, 19)
	var player = server.add_player(800, "Camper")
	var hub: Vector2 = GameServer.WORKBENCH_POSITION
	player.position = Vector3(hub.x, w.height_at(hub.x, hub.y), hub.y)
	t.current = "sanctuary authority and no wasted supplies"
	t.eq(server.cmd_rest(999).get("reason"), "dead", "unknown peer never rests")
	player.position = Vector3(160, w.height_at(160, 160), 160)
	t.eq(server.cmd_rest(800).get("reason"), "no_station", "remote recovery denied")
	player.position = Vector3(hub.x, w.height_at(hub.x, hub.y), hub.y)
	t.eq(server.cmd_rest(800).get("reason"), "fully_rested", "starter vitals do not waste supplies")
	player.survival.health = 50.0
	player.survival.stamina = 20.0
	player.survival.hunger = 40.0
	player.survival.thirst = 35.0
	player.attack_timer = 1.0
	t.eq(server.cmd_rest(800).get("reason"), "in_combat", "combat prevents instant heal")
	player.attack_timer = 0.0
	player.noise_timer = 1.0
	t.eq(server.cmd_rest(800).get("reason"), "in_combat", "noisy survivor must settle down")
	player.noise_timer = 0.0
	player.inventory.add("wood_1", 2)
	player.inventory.add("canned_food", 1)
	player.inventory.remove("water_bottle", 2) # Remove starter water to test missing input.
	t.eq(server.cmd_rest(800).get("reason"), "missing_items", "all costs must be present")
	t.eq(player.inventory.count("wood_1"), 2, "rejected rest does not consume fuel")
	t.eq(player.inventory.count("canned_food"), 3, "rejected rest keeps food")
	player.inventory.add("water_bottle", 3)

	t.current = "costs, healing and cooldown"
	t.check(bool(server.cmd_rest(800).get("ok", false)), "paid camp rest succeeds")
	t.eq(player.inventory.count("wood_1"), 0, "two fuel wood debited")
	t.eq(player.inventory.count("canned_food"), 2, "one ration debited")
	t.eq(player.inventory.count("water_bottle"), 2, "one water debited")
	t.near(player.survival.health, 75.0, 0.0001, "health restored")
	t.near(player.survival.stamina, 75.0, 0.0001, "stamina restored")
	t.near(player.survival.hunger, 55.0, 0.0001, "hunger improved")
	t.near(player.survival.thirst, 50.0, 0.0001, "thirst improved")
	t.near(player.rest_cooldown, CampRest.COOLDOWN, 0.0001, "server sets cooldown")
	t.eq(server.cmd_rest(800).get("reason"), "cooldown", "replayed request cannot duplicate recovery")
	t.eq(player.inventory.count("canned_food"), 2, "cooldown leaves resources intact")
	server._tick_players(0.5)
	t.near(player.rest_cooldown, CampRest.COOLDOWN - 0.5, 0.0001, "cooldown advances by server time")

	t.current = "version-1 save migration and anti-corruption"
	var saved: Dictionary = server.character_data(player)
	t.check(server.valid_character_data(saved), "rest cooldown roundtrips in character save")
	t.check(saved.has("rest_cooldown"), "saved cooldown is explicit")
	player.rest_cooldown = 0.0
	t.check(server.apply_character(player, saved), "resume cooldown after login")
	t.near(player.rest_cooldown, CampRest.COOLDOWN - 0.5, 0.0001, "relog cannot bypass rest cooldown")
	var bad: Dictionary = saved.duplicate(true)
	bad["rest_cooldown"] = -10.0
	t.check(not server.apply_character(player, bad), "negative cooldown is rejected")
	t.near(player.rest_cooldown, CampRest.COOLDOWN - 0.5, 0.0001, "invalid save is atomic")
	bad = saved.duplicate(true)
	bad["rest_cooldown"] = NAN
	t.check(not server.apply_character(player, bad), "NaN cooldown rejected")
	bad = saved.duplicate(true)
	bad["rest_cooldown"] = CampRest.COOLDOWN * 2.0
	t.check(not server.apply_character(player, bad), "oversized cooldown rejected")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("rest_cooldown")
	t.check(server.apply_character(player, legacy), "older version-1 saves still load")
	t.eq(player.rest_cooldown, 0.0, "legacy player has no cooldown")
