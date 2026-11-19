extends RefCounted
## Server-authoritative settlement bank regression. No live socket needed.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "secure stash / only the server transfers items"
	var server = GameServer.new(WorldGen.new(17), 1234)
	var player = server.add_player(10, "Banker")
	player.position = Vector3(9.0, server.world.height_at(9.0, 0.0), 0.0)
	player.inventory.add("wood_1", 7)
	t.eq(player.stash.slots.size(), Defs.STASH_SLOTS, "stash has bounded account slot count")
	t.check(server.cmd_stash(10, "wood_1", 3, true)["ok"], "valid deposit is accepted")
	t.eq(player.inventory.count("wood_1"), 4, "deposit debits carried inventory")
	t.eq(player.stash.count("wood_1"), 3, "deposit credits only private stash")
	t.check(server.cmd_stash(10, "wood_1", 2, false)["ok"], "withdrawal at station succeeds")
	t.eq(player.inventory.count("wood_1"), 6, "withdrawal credits inventory")
	t.eq(player.stash.count("wood_1"), 1, "withdrawal debits stash")

	t.current = "validation, permissions and transaction atomicity"
	t.eq(server.cmd_stash(999, "wood_1", 1, true)["reason"], "dead", "unknown peer never moves items")
	t.eq(server.cmd_stash(10, "fake_item", 1, true)["reason"], "invalid_stack", "item ID must be valid")
	t.eq(server.cmd_stash(10, "wood_1", 0, true)["reason"], "invalid_stack", "zero transfer is rejected")
	t.eq(server.cmd_stash(10, "wood_1", -1, true)["reason"], "invalid_stack", "negative count is rejected")
	t.eq(server.cmd_stash(10, "wood_1", Defs.stack_size("wood_1") + 1, true)["reason"], "invalid_stack", "a single command cannot exceed max stack")
	var carry_before: int = player.inventory.count("wood_1")
	var stored_before: int = player.stash.count("wood_1")
	t.eq(server.cmd_stash(10, "wood_1", carry_before + 1, true)["reason"], "missing_items", "cannot invent materials via deposit")
	t.eq(server.cmd_stash(10, "wood_1", stored_before + 1, false)["reason"], "missing_items", "cannot invent materials via withdrawal")
	t.eq(player.inventory.count("wood_1"), carry_before, "failed transfers do not affect carried items")
	t.eq(player.stash.count("wood_1"), stored_before, "failed transfers do not affect bank items")

	player.position = Vector3(150.0, server.world.height_at(150.0, 0.0), 0.0)
	t.eq(server.cmd_stash(10, "wood_1", 1, true)["reason"], "no_station", "client cannot deposit while away from hub")
	t.eq(server.cmd_stash(10, "wood_1", 1, false)["reason"], "no_station", "client cannot withdraw while away from hub")
	t.eq(player.stash.count("wood_1"), stored_before, "out-of-range request has no side effects")
	player.position = Vector3(9.0, server.world.height_at(9.0, 0.0), 0.0)

	t.current = "bounded capacity and equipment"
	var full_slots: Array = []
	for i in range(Defs.STASH_SLOTS):
		full_slots.append({"id": "wood_1", "count": Defs.stack_size("wood_1")})
	player.stash.slots = full_slots
	t.eq(server.cmd_stash(10, "wood_1", 1, true)["reason"], "no_space", "no deposit when bank is full")
	t.eq(player.inventory.count("wood_1"), carry_before, "full bank never consumes a source item")
	player.stash = preload("res://scripts/shared/inventory.gd").new(Defs.STASH_SLOTS)
	player.inventory.add("club_1", 1)
	player.inventory.equip("club_1")
	t.check(server.cmd_stash(10, "club_1", 1, true)["ok"], "equipped weapon may be banked")
	t.eq(player.inventory.weapon, "", "banking last equipped weapon unequips it")
	t.eq(player.stash.count("club_1"), 1, "equipped weapon safely stored")

	t.current = "interest snapshot and private persistence"
	var first: Dictionary = server.snapshot_for(10)
	t.check(first.has("stash"), "owner receives initial stash contents")
	t.eq(first["stash"]["slots"].size(), Defs.STASH_SLOTS, "snapshot has bounded stash")
	t.check(not server.snapshot_for(10).has("stash"), "stash is sent only when dirty")
	t.check(server.cmd_stash(10, "wood_1", 1, true)["ok"], "a new transfer marks stash dirty")
	t.check(server.snapshot_for(10).has("stash"), "subsequent transfer re-sends private stash")
	var saved: Dictionary = server.character_data(player)
	t.check(saved.has("stash"), "character save includes protected stash")
	var restored_server = GameServer.new(WorldGen.new(17), 1234)
	var restored = restored_server.add_player(20, "Restored", "account-20", saved)
	t.eq(restored.stash.count("wood_1"), player.stash.count("wood_1"), "stored wood survives account reconnection")
	t.eq(restored.stash.count("club_1"), 1, "stored weapon survives account reconnection")

	t.current = "backwards-compatible and reject invalid saves"
	var old_save: Dictionary = saved.duplicate(true)
	old_save.erase("stash")
	var old_user = restored_server.add_player(21, "Old Character", "account-21", old_save)
	t.eq(old_user.stash.count("wood_1"), 0, "version-1 characters without stash load an empty bank")
	var bad: Dictionary = saved.duplicate(true)
	bad["stash"]["slots"][0] = {"id": "not_a_real_item", "count": 1}
	var before_rejected: int = player.stash.count("wood_1")
	t.check(not server.apply_character(player, bad), "corrupt bank item rejects complete character restore")
	t.eq(player.stash.count("wood_1"), before_rejected, "corrupt restore does not mutate existing private items")
	bad = saved.duplicate(true)
	bad["stash"]["slots"][0] = {"id": "wood_1", "count": -3}
	t.check(not server.apply_character(player, bad), "negative stash amount is rejected")
	bad = saved.duplicate(true)
	bad["stash"]["slots"].pop_back()
	t.check(not server.apply_character(player, bad), "wrong stash slot count is rejected")
	bad = saved.duplicate(true)
	bad["stash"]["slots"][0] = {"id": "wood_1", "count": NAN}
	t.check(not server.apply_character(player, bad), "nonfinite quantity is rejected")

	t.current = "death drops carried items but not bank deposits"
	var protected_wood: int = player.stash.count("wood_1")
	var protected_weapon: int = player.stash.count("club_1")
	player.inventory.add("silver", 17)
	player.position = Vector3(800.0, server.world.height_at(800.0, 0.0), 0.0)
	player.survival.health = 0.0
	server._on_player_death(player, -1)
	t.eq(player.inventory.count("silver"), 0, "silver carried outside the bank is dropped")
	t.eq(player.stash.count("wood_1"), protected_wood, "banked resources survive death")
	t.eq(player.stash.count("club_1"), protected_weapon, "banked weapons survive death")
	server.tick(Defs.RESPAWN_SECONDS + 0.1)
	t.eq(player.stash.count("club_1"), protected_weapon, "respawn keeps banked equipment")
