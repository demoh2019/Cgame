extends RefCounted
## Paid survival armor mitigates only server-verified infected melee hits.

const Defs = preload("res://scripts/shared/defs.gd")
const Plate = preload("res://scripts/shared/field_armor_plate.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _position(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func _claw(server, player) -> void:
	server.zombies.clear()
	var monster := Zombie.new(server.new_id(), "walker",
		player.position + Vector3(1.1, 0.0, 0.0))
	monster.target_id = player.id
	monster.state = Zombie.State.ATTACK
	server.zombies[monster.id] = monster
	server._tick_zombies(0.1)


func run(t) -> void:
	t.current = "field plate: recipe and authorized usage"
	t.eq(Defs.item(Plate.ITEM_ID).get("kind"), "armor_plate", "item registered")
	t.eq(Defs.recipes()[Plate.ITEM_ID]["station"], "workbench",
		"plate is craftable at a real workbench")
	t.eq(Defs.recipes()[Plate.ITEM_ID]["inputs"],
		{"bar_1": 1, "cloth_1": 2, "scrap": 2}, "T1 resources and scrap pay for plate")
	var world := WorldGen.new(207)
	var server := GameServer.new(world, 68)
	var survivor = server.add_player(900, "Armorer")
	t.eq(server.cmd_use(900, Plate.ITEM_ID).get("reason"), "not_carried",
		"missing plate cannot be applied")
	survivor.inventory.add(Plate.ITEM_ID, 2)
	t.eq(server.cmd_use(900, Plate.ITEM_ID).get("reason"), "need_armor",
		"unarmored survivor cannot apply plate")
	t.eq(survivor.inventory.count(Plate.ITEM_ID), 2, "failure leaves item intact")
	survivor.inventory.add("jacket_1", 1)
	t.check(survivor.inventory.equip("jacket_1"), "equips carried armor")
	survivor.attack_timer = 1.0
	t.eq(server.cmd_use(900, Plate.ITEM_ID).get("reason"), "in_combat",
		"cannot fit armor while attacking")
	survivor.attack_timer = 0.0
	t.check(bool(server.cmd_use(900, Plate.ITEM_ID).get("ok", false)),
		"valid armor accepts paid plate")
	t.eq(survivor.inventory.count(Plate.ITEM_ID), 1, "exactly one plate spent")
	t.eq(survivor.plated_hits, 3, "three hits awarded")
	t.eq(server.cmd_use(900, Plate.ITEM_ID).get("reason"), "already_plated",
		"second request does not consume resource")
	t.eq(survivor.inventory.count(Plate.ITEM_ID), 1, "no duplicate charge cost")

	t.current = "field plate: ordinary infected damage and saving"
	survivor.position = _position(world, 200.0, 200.0)
	var start_hp: float = survivor.survival.health
	_claw(server, survivor)
	t.near(start_hp - survivor.survival.health, 9.0 * 0.92 * Plate.DAMAGE_FACTOR,
		0.001, "server applies normal jacket and plate against a real claw")
	t.eq(survivor.plated_hits, 2, "confirmed claw consumes exactly one charge")
	var saved: Dictionary = server.character_data(survivor)
	t.check(server.valid_character_data(saved), "honest equipment save is valid")
	t.eq(saved["plated_hits"], 2, "remaining charges survive logout")
	survivor.plated_hits = 0
	survivor.plated_armor = ""
	t.check(server.apply_character(survivor, saved),
		"server restores charged armor owned in saved inventory")
	t.eq(survivor.plated_hits, 2, "relogin does not refill charges")
	t.eq(int(server.snapshot_for(900)["you"]["plated_hits"]), 2,
		"owner snapshot exposes charges")
	var bad: Dictionary = saved.duplicate(true)
	bad["plated_hits"] = 4
	t.check(not server.apply_character(survivor, bad), "forged charges rejected")
	t.eq(survivor.plated_hits, 2, "invalid save does not change live state")
	bad = saved.duplicate(true)
	bad["plated_armor"] = "jacket_4"
	t.check(not server.apply_character(survivor, bad), "ghost armor rejected")
	bad = saved.duplicate(true)
	bad["plated_hits"] = 1.5
	t.check(not server.apply_character(survivor, bad), "fractional counter rejected")

	t.current = "field plate: three hits, equipment swap and compatibility"
	_claw(server, survivor)
	_claw(server, survivor)
	t.eq(survivor.plated_hits, 0, "third confirmed claw uses final charge")
	t.eq(survivor.plated_armor, "", "empty charge has no ghost armor")
	survivor.survival.reset()
	start_hp = survivor.survival.health
	_claw(server, survivor)
	t.near(start_hp - survivor.survival.health, 9.0 * 0.92, 0.001,
		"ordinary damage resumes without a plate")
	survivor.attack_timer = 0.0
	t.check(bool(server.cmd_use(900, Plate.ITEM_ID).get("ok", false)),
		"new plate can be applied after charges expire")
	survivor.inventory.add("jacket_2", 1)
	t.check(bool(server.cmd_use(900, "jacket_2").get("ok", false)),
		"equip an owned replacement armor piece")
	t.eq(survivor.plated_hits, 0, "changing equipment cancels the plate")
	var old: Dictionary = server.character_data(survivor)
	old.erase("plated_hits")
	old.erase("plated_armor")
	t.check(server.apply_character(survivor, old), "old version-one saves still load")
	t.eq(survivor.plated_hits, 0, "old saves start with no free defenses")
