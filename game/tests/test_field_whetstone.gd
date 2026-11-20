extends RefCounted
## Server authority: costs, hit resolution, persistence and backward compatibility.

const Defs = preload("res://scripts/shared/defs.gd")
const Rules = preload("res://scripts/shared/field_whetstone.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _spot(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "whetstone: craft and paid melee preparation"
	t.eq(Defs.item(Rules.ITEM_ID).get("kind"), "whetstone", "consumable registered")
	t.eq(Defs.recipes()[Rules.ITEM_ID]["station"], "workbench", "workbench recipe")
	t.eq(Defs.recipes()[Rules.ITEM_ID]["inputs"], {"stone_1": 2, "scrap": 1},
		"stone and scrap recipe requirements")
	var world := WorldGen.new(406)
	var server := GameServer.new(world, 117)
	var p = server.add_player(410, "Blade")
	t.eq(server.cmd_use(410, Rules.ITEM_ID).get("reason"), "not_carried",
		"absent consumable cannot be used")
	p.inventory.add(Rules.ITEM_ID, 2)
	t.eq(server.cmd_use(410, Rules.ITEM_ID).get("reason"), "need_melee",
		"unarmed players cannot sharpen")
	t.eq(p.inventory.count(Rules.ITEM_ID), 2, "rejected use does not consume")
	p.inventory.add("bow_1", 1)
	p.inventory.equip("bow_1")
	t.eq(server.cmd_use(410, Rules.ITEM_ID).get("reason"), "need_melee",
		"ranged weapons cannot receive melee bonus")
	p.inventory.add("club_1", 1)
	p.inventory.equip("club_1")
	p.attack_timer = 1.0
	t.eq(server.cmd_use(410, Rules.ITEM_ID).get("reason"), "in_combat",
		"no preparation while attacking")
	p.attack_timer = 0.0
	t.check(bool(server.cmd_use(410, Rules.ITEM_ID).get("ok", false)),
		"prepared melee weapon accepted")
	t.eq(p.sharpened_hits, Rules.HITS, "three charges granted server-side")
	t.eq(p.inventory.count(Rules.ITEM_ID), 1, "exactly one stone consumed")
	t.eq(server.cmd_use(410, Rules.ITEM_ID).get("reason"), "already_sharpened",
		"duplicate use cannot waste supplies")
	t.eq(p.inventory.count(Rules.ITEM_ID), 1, "duplicate preserves items")

	t.current = "whetstone: confirmed infected hits and strict saves"
	p.position = _spot(world, 200.0, 200.0)
	var brute := Zombie.new(server.new_id(), "brute", _spot(world, 202.0, 200.0))
	server.zombies[brute.id] = brute
	var before_hp: float = brute.health
	var miss: Dictionary = server.cmd_attack(410, -1.0, 0.0)
	t.check(bool(miss.get("ok", false)) and not bool(miss.get("hit", true)),
		"miss is not a confirmed hit")
	t.eq(p.sharpened_hits, Rules.HITS, "miss does not spend charges")
	p.attack_timer = 0.0
	var strike: Dictionary = server.cmd_attack(410, 1.0, 0.0)
	t.check(bool(strike.get("hit", false)) and bool(strike.get("sharpened", false)),
		"server-verified infected contact uses preparation")
	t.near(before_hp - brute.health, 14.0 * Rules.DAMAGE_FACTOR, 0.001,
		"damage comes from 15 percent buff on tier one club")
	t.eq(p.sharpened_hits, 2, "confirmed hit spends one charge")
	var saved: Dictionary = server.character_data(p)
	t.check(server.valid_character_data(saved), "valid state can be saved")
	t.eq(saved["sharpened_hits"], 2, "saved charges do not refill")
	p.sharpened_hits = 0
	p.sharpened_weapon = ""
	t.check(server.apply_character(p, saved), "owned equipped weapon survives reload")
	t.eq(p.sharpened_hits, 2, "server restores exact saved hit count")
	t.eq(int(server.snapshot_for(410)["you"]["sharpened_hits"]), 2,
		"private snapshot exposes charge count")
	var invalid: Dictionary = saved.duplicate(true)
	invalid["sharpened_hits"] = Rules.HITS + 1
	t.check(not server.apply_character(p, invalid), "forged extra charges rejected")
	t.eq(p.sharpened_hits, 2, "invalid save is atomic")
	invalid = saved.duplicate(true)
	invalid["sharpened_weapon"] = "spear_4"
	t.check(not server.apply_character(p, invalid), "foreign unowned weapon rejected")
	invalid = saved.duplicate(true)
	invalid["sharpened_hits"] = 2.5
	t.check(not server.apply_character(p, invalid), "fractional hit counter rejected")

	t.current = "whetstone: PvP separation, expiry and equipment changes"
	server.zombies.clear()
	var enemy = server.add_player(411, "Rival")
	p.position = _spot(world, 800.0, 800.0)
	enemy.position = _spot(world, 802.0, 800.0)
	p.attack_timer = 0.0
	server.cmd_attack(410, 1.0, 0.0)
	t.eq(p.sharpened_hits, 2, "PvP cannot gain or spend PvE-only charges")
	p.position = _spot(world, 200.0, 200.0)
	p.combat_tag_until = 0.0 # End the test duel before requesting an out-of-combat item.
	var brute2 := Zombie.new(server.new_id(), "brute", _spot(world, 202.0, 200.0))
	server.zombies[brute2.id] = brute2
	p.attack_timer = 0.0
	server.cmd_attack(410, 1.0, 0.0)
	p.attack_timer = 0.0
	server.cmd_attack(410, 1.0, 0.0)
	t.eq(p.sharpened_hits, 0, "third infected hit exhausts charges")
	t.eq(p.sharpened_weapon, "", "no stale preparation after exhaustion")
	p.attack_timer = 0.0
	var plain_hp: float = brute2.health
	server.cmd_attack(410, 1.0, 0.0)
	t.near(plain_hp - brute2.health, 14.0, 0.001,
		"unprepared follow-up strike is normal damage")
	p.attack_timer = 0.0
	t.check(bool(server.cmd_use(410, Rules.ITEM_ID).get("ok", false)),
		"another stone usable after the previous wears off")
	p.inventory.add("club_2", 1)
	t.check(bool(server.cmd_use(410, "club_2").get("ok", false)),
		"carried weapon can be swapped")
	t.eq(p.sharpened_hits, 0, "weapon swap cancels old preparation")
	var legacy: Dictionary = server.character_data(p)
	legacy.erase("sharpened_hits")
	legacy.erase("sharpened_weapon")
	t.check(server.apply_character(p, legacy), "legacy version-one save compatible")
	t.eq(p.sharpened_hits, 0, "legacy character receives no free preparation")
