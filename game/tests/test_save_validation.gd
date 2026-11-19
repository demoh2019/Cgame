extends RefCounted
## Exercises the actual server character restore path without sockets or Nakama.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const SaveValidation = preload("res://scripts/shared/save_validation.gd")


func run(t) -> void:
	var server = GameServer.new(WorldGen.new(67), 11)
	var player = server.add_player(905, "Stored Survivor")
	player.inventory.add("club_1", 1)
	player.inventory.equip("club_1")
	player.stash.add("silver", 50)
	player.survival.health = 66.0
	var saved: Dictionary = server.character_data(player)

	t.current = "valid character and old save compatibility"
	t.check(server.apply_character(player, saved), "valid snapshot restores")
	t.eq(player.inventory.weapon, "club_1", "carried weapon survives restore")
	t.eq(player.stash.count("silver"), 50, "private bank survives restore")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("stash")
	t.check(server.apply_character(player, legacy), "old version-1 save without bank accepted")
	t.eq(player.stash.slots.size(), Defs.STASH_SLOTS, "old save gets correctly sized bank")
	t.eq(player.stash.count("silver"), 0, "old save gets empty bank")
	t.check(server.apply_character(player, saved), "restore full snapshot again")

	# No damage to live state from a failed validation, even if the invalid
	# portion is in the protected stash after a valid carried inventory.
	t.current = "corrupt saves reject atomically"
	var original_health: float = player.survival.health
	var original_wood: int = player.inventory.count("club_1")
	var original_silver: int = player.stash.count("silver")
	var invalid: Dictionary = saved.duplicate(true)
	invalid["inventory"]["slots"][0] = {"id": "wood_1", "count": 1.5}
	t.check(not server.apply_character(player, invalid), "fractional carried items rejected")
	invalid = saved.duplicate(true)
	invalid["inventory"]["slots"][0] = {"id": "wood_1", "count": "10"}
	t.check(not server.apply_character(player, invalid), "textual carried quantities rejected")
	invalid = saved.duplicate(true)
	invalid["inventory"]["slots"][0] = {"id": "wood_1", "count": NAN}
	t.check(not server.apply_character(player, invalid), "NaN carried count rejected")
	invalid = saved.duplicate(true)
	invalid["inventory"]["slots"][0] = {"id": "wood_1", "count": INF}
	t.check(not server.apply_character(player, invalid), "infinite carried count rejected")
	invalid = saved.duplicate(true)
	invalid["inventory"]["slots"][0] = {"id": 12, "count": 1}
	t.check(not server.apply_character(player, invalid), "non-string item ID rejected")
	invalid = saved.duplicate(true)
	invalid["inventory"]["slots"][0] = 5
	t.check(not server.apply_character(player, invalid), "non-dictionary slot rejected")
	invalid = saved.duplicate(true)
	invalid["inventory"]["slots"][0] = {"id": "wood_1", "count": 101}
	t.check(not server.apply_character(player, invalid), "oversized stack rejected")
	invalid = saved.duplicate(true)
	invalid["inventory"]["weapon"] = "canned_food"
	t.check(not server.apply_character(player, invalid), "food cannot masquerade as a weapon")
	invalid = saved.duplicate(true)
	invalid["inventory"]["armor"] = "club_1"
	t.check(not server.apply_character(player, invalid), "weapon cannot be equipped as armor")
	invalid = saved.duplicate(true)
	invalid["stash"]["slots"][0] = {"id": "silver", "count": 1.25}
	t.check(not server.apply_character(player, invalid), "fractional stash quantity rejected")
	invalid = saved.duplicate(true)
	invalid["stash"]["weapon"] = "club_1"
	t.check(not server.apply_character(player, invalid), "stash cannot grant equipped weapons")
	invalid = saved.duplicate(true)
	invalid["health"] = NAN
	t.check(not server.apply_character(player, invalid), "nonfinite health rejected")
	invalid = saved.duplicate(true)
	invalid["deaths"] = -1
	t.check(not server.apply_character(player, invalid), "negative death count rejected")
	invalid = saved.duplicate(true)
	invalid["hunger"] = "100"
	t.check(not server.apply_character(player, invalid), "textual hunger rejected")
	t.eq(player.inventory.count("club_1"), original_wood, "invalid restore kept carried weapon")
	t.eq(player.inventory.weapon, "club_1", "invalid restore kept equipment")
	t.eq(player.stash.count("silver"), original_silver, "invalid restore kept bank")
	t.eq(player.survival.health, original_health, "invalid restore kept survival")

	t.current = "reconnect validation is side-effect free"
	var seed_before: int = server.rng.state
	t.check(server.valid_character_data(saved), "existing valid save is allowed to reconnect")
	t.eq(server.rng.state, seed_before, "validation must not change the spawn RNG")
	var broken: Dictionary = saved.duplicate(true)
	broken["inventory"]["slots"][0] = {"id": "silver", "count": "99"}
	t.check(not server.valid_character_data(broken), "corrupt existing save is not treated as a new player")
	t.eq(player.stash.count("silver"), original_silver, "validation does not change a live player's protected bank")

	t.current = "numeric bounds"
	t.check(SaveValidation.valid_counter(0), "zero counter accepted")
	t.check(SaveValidation.valid_counter(12.0), "integral JSON float counter accepted")
	t.check(not SaveValidation.valid_counter(12.2), "fractional counter rejected")
	t.check(not SaveValidation.valid_counter(INF), "infinite counter rejected")
	t.check(not SaveValidation.finite_number(true, 0.0, 100.0), "boolean not a stat")
