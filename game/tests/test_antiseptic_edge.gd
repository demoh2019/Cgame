extends RefCounted
## Server-paid melee oil: strict ownership, limited buff, PvE-only combat.
const Defs = preload("res://scripts/shared/defs.gd")
const Oil = preload("res://scripts/shared/antiseptic_edge.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func run(t) -> void:
	t.current = "craftable consumable requires an owned equipped melee weapon"
	var item: Dictionary = Defs.item(Oil.ITEM_ID)
	t.eq(item.get("kind", ""), "weapon_coating", "real oil kind is defined")
	t.check(Defs.recipes().has(Oil.ITEM_ID), "oil has a workbench recipe")
	var recipe: Dictionary = Defs.recipes()[Oil.ITEM_ID]
	t.eq(recipe["station"], "workbench", "workbench required for refining")
	t.eq(int(recipe["inputs"]["spore_culture"]), 1,
		"uses a true swamp culture rather than generic currency")
	var world := WorldGen.new(93)
	var sim := GameServer.new(world, 93)
	var hunter = sim.add_player(771, "Pathfinder")
	t.eq(sim.cmd_use(999, Oil.ITEM_ID).get("reason", ""), "dead",
		"unknown sender cannot apply oil")
	hunter.inventory.add(Oil.ITEM_ID, 2)
	t.eq(sim.cmd_use(771, Oil.ITEM_ID).get("reason", ""), "need_melee",
		"unarmed character is rejected without cost")
	t.eq(hunter.inventory.count(Oil.ITEM_ID), 2,
		"rejected oil was not consumed")
	hunter.inventory.add("pistol", 1)
	t.check(hunter.inventory.equip("pistol"), "owns actual ranged weapon")
	t.eq(sim.cmd_use(771, Oil.ITEM_ID).get("reason", ""), "need_melee",
		"ranged equipment cannot be coated")
	hunter.inventory.add("club_1", 1)
	t.check(hunter.inventory.equip("club_1"), "real melee club equipped")
	var use: Dictionary = sim.cmd_use(771, Oil.ITEM_ID)
	t.check(bool(use.get("ok", false)), "legitimate melee oil application works")
	t.eq(hunter.inventory.count(Oil.ITEM_ID), 1, "spends exactly one oil")
	t.eq(hunter.edge_coating_weapon, "club_1", "coating is tied to melee item")
	t.near(hunter.edge_coating_seconds, Oil.SECONDS, 0.001,
		"precise server timer assigned")
	t.eq(sim.cmd_use(771, Oil.ITEM_ID).get("reason", ""), "already_coated",
		"reapplying during active buff does not waste a second oil")
	t.eq(hunter.inventory.count(Oil.ITEM_ID), 1, "no duplicated oil consumption")
	t.current = "authoritative PvE damage, raid and PvP isolation"
	var infected := Zombie.new(sim.new_id(), "walker", Vector3(30.0, 0.0, 30.0))
	sim.zombies[infected.id] = infected
	var old_health: float = infected.health
	sim._damage_target(hunter, {"kind": "zombie", "id": infected.id}, 10.0, "melee")
	t.near(old_health - infected.health, 12.0, 0.001,
		"normal infected receives +20 percent server damage")
	var elite := Zombie.new(sim.new_id(), "brute", Vector3(30.0, 0.0, 31.0))
	elite.elite = true
	sim.zombies[elite.id] = elite
	old_health = elite.health
	sim._damage_target(hunter, {"kind": "zombie", "id": elite.id}, 10.0, "melee")
	t.near(old_health - elite.health, 12.0, 0.001,
		"elite infected receives same bounded bonus")
	var boss := Zombie.new(sim.new_id(), "brute", Vector3(30.0, 0.0, 32.0))
	boss.raid_boss = true
	sim.zombies[boss.id] = boss
	old_health = boss.health
	sim._damage_target(hunter, {"kind": "zombie", "id": boss.id}, 10.0, "melee")
	t.near(old_health - boss.health, 10.0, 0.001,
		"raid boss never receives consumable damage bonus")
	var opponent = sim.add_player(772, "Opponent")
	hunter.position = Vector3(801.0, world.height_at(801.0, 800.0), 800.0)
	opponent.position = Vector3(800.0, world.height_at(800.0, 800.0), 800.0)
	var hp: float = opponent.survival.health
	sim._damage_target(hunter, {"kind": "player", "id": 772}, 10.0, "melee")
	t.near(hp - opponent.survival.health, 10.0, 0.001,
		"PvP strike remains base damage during oil buff")
	t.current = "re-equipping, lost ownership, expiration and respawn"
	sim.cmd_use(771, "pistol")
	t.eq(hunter.edge_coating_seconds, 0.0, "changing weapon cancels coating")
	t.eq(hunter.edge_coating_weapon, "", "stale weapon link is cleared")
	t.check(hunter.inventory.equip("club_1"), "can equip old club again")
	t.check(sim.cmd_use(771, Oil.ITEM_ID).get("ok", false),
		"second paid application works only after old effect ends")
	t.eq(hunter.inventory.count(Oil.ITEM_ID), 0, "both legitimate charges were spent")
	sim._tick_players(0.5)
	t.check(hunter.edge_coating_seconds < Oil.SECONDS,
		"remaining buff duration decreases on server tick")
	hunter.inventory.remove("club_1", 1)
	sim._tick_players(0.1)
	t.eq(hunter.edge_coating_seconds, 0.0,
		"dropping coated weapon immediately clears bonus")
	t.eq(Oil.damage(10.0, hunter.inventory, "club_1", 100.0, infected), 10.0,
		"ghost weapon never grants protected bonus")
	sim._spawn_player(hunter)
	t.eq(hunter.edge_coating_seconds, 0.0, "respawning clears transient oil")
