extends RefCounted
## Albion-style gear durability: wear from fighting and deaths, half-strength broken
## gear, silver repair at a workbench, persistence through saves.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const GearDurability = preload("res://scripts/shared/gear_durability.gd")
const SaveValidation = preload("res://scripts/shared/save_validation.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _armor_id() -> String:
	for id in Defs.items():
		if str(Defs.item(id).get("kind", "")) == "armor" and float(Defs.item(id).get("armor", 0.0)) > 0.0:
			return str(id)
	return ""


func run(t) -> void:
	t.current = "durability basics"
	var bag := Inventory.new()
	bag.add("club_2", 1)
	t.eq(bag.durability("club_2"), 100.0, "new gear is pristine")
	bag.damage_item("club_2", 30.0)
	t.near(bag.durability("club_2"), 70.0, 0.001, "wear lowers durability")
	t.eq(bag.effectiveness("club_2"), 1.0, "worn gear still works fully")
	bag.damage_item("club_2", 500.0)
	t.eq(bag.durability("club_2"), 0.0, "durability never goes negative")
	t.eq(bag.effectiveness("club_2"), GearDurability.BROKEN_EFFECTIVENESS, "broken gear works at half strength")
	bag.damage_item("axe_1", 10.0)
	t.check(not bag.wear.has("axe_1"), "items you do not carry cannot be worn down")

	t.current = "repair is a silver sink"
	var cost: int = bag.repair_cost()
	t.check(cost > 0, "broken gear costs silver to fix")
	t.eq(cost, GearDurability.repair_cost(float(Defs.item("club_2")["value"]), 100.0), "cost follows value and wear")
	t.check(GearDurability.repair_cost(100.0, 10.0) < GearDurability.repair_cost(100.0, 90.0), "more wear costs more")
	t.eq(bag.repair_all(), ["club_2"], "repair restores damaged items")
	t.eq(bag.durability("club_2"), 100.0, "back to 100%")
	t.eq(bag.repair_cost(), 0, "nothing left to pay for")

	t.current = "last-copy removal clears equipped and stale durability state"
	var removal := Inventory.new(3)
	t.eq(removal.add("club_2", 2), 0, "two independent weapons fit")
	t.check(removal.equip("club_2"), "owned weapon can be equipped")
	removal.damage_item("club_2", 35.0)
	t.check(removal.remove("club_2", 1), "one of two weapons can leave the bag")
	t.eq(removal.durability("club_2"), 65.0,
		"shared stack wear stays until the final copy leaves")
	t.eq(removal.weapon, "club_2", "remaining weapon stays equipped")
	t.check(removal.remove("club_2", 1), "last weapon is removed")
	t.eq(removal.weapon, "", "missing weapon is automatically unequipped")
	t.check(not removal.wear.has("club_2"), "orphan durability is discarded")
	removal.add("club_2", 1)
	t.eq(removal.durability("club_2"), 100.0,
		"newly acquired replacement cannot inherit previous damage")
	removal.damage_item("club_2", 50.0)
	removal.take_everything()
	t.eq(removal.to_dict()["wear"], {},
		"full-loot death clears old durability along with all carried items")
	removal.add("club_2", 1)
	t.eq(removal.durability("club_2"), 100.0,
		"respawned survivor's fresh gear starts at pristine durability")

	t.current = "armor wears on hits and protects less when broken"
	var armor_id := _armor_id()
	t.check(armor_id != "", "an armor item exists")
	var worn := Inventory.new()
	worn.add(armor_id, 1)
	worn.equip(armor_id)
	var fresh: float = Combat.apply_gear(100.0, worn)
	t.check(worn.durability(armor_id) < 100.0, "a received hit wears the armor")
	worn.damage_item(armor_id, 500.0)
	var broken: float = Combat.apply_gear(100.0, worn)
	t.check(broken > fresh, "broken armor lets more damage through")

	t.current = "durability survives a save"
	var saved: Dictionary = worn.to_dict()
	var parsed: Dictionary = SaveValidation.parse_inventory(saved, Defs.INVENTORY_SLOTS)
	t.check(not parsed.is_empty(), "save with durability is accepted")
	t.eq((parsed["inventory"] as Inventory).durability(armor_id), 0.0, "durability restored from the save")
	saved["wear"] = {armor_id: 999.0, "not_an_item": 5.0}
	var tampered: Dictionary = SaveValidation.parse_inventory(saved, Defs.INVENTORY_SLOTS)
	t.eq((tampered["inventory"] as Inventory).durability(armor_id), 100.0, "out-of-range values are ignored")

	t.current = "server repair at the workbench"
	var world = WorldGen.new(1234)
	var server := GameServer.new(world, 77)
	var smith = server.add_player(701, "Smith")
	smith.inventory = Inventory.new()
	smith.inventory.add("club_2", 1)
	smith.inventory.damage_item("club_2", 100.0)
	smith.position = Vector3(300, world.height_at(300, 300), 300)
	t.eq(server.cmd_repair_gear(701).get("reason"), "no_station", "repairs need a workbench")
	smith.position = Vector3(9.0, world.height_at(9.0, 0.0), 0.0)
	t.eq(server.cmd_repair_gear(701).get("reason"), "need_silver", "repairs cost silver")
	smith.inventory.add("silver", 1000)
	var result: Dictionary = server.cmd_repair_gear(701)
	t.check(bool(result.get("ok", false)), "paid repair succeeds")
	t.eq(smith.inventory.count("silver"), 1000 - int(result["cost"]), "silver is spent")
	t.eq(smith.inventory.durability("club_2"), 100.0, "gear restored")
	t.eq(server.cmd_repair_gear(701).get("reason"), "nothing_to_repair", "no double charging")
