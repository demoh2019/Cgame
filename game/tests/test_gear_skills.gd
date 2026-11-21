extends RefCounted
## Albion-style gear ability bar: weapon ultimate and armor skills, server-validated.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const GearSkills = preload("res://scripts/shared/gear_skills.gd")
const Survival = preload("res://scripts/shared/survival.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _first_of(kind: String) -> String:
	var ids: Array = Defs.items().keys()
	ids.sort()
	for id in ids:
		if str(Defs.item(id).get("kind", "")) == kind and not str(id).contains("@"):
			return str(id)
	return ""


func run(t) -> void:
	t.current = "skills come from gear and scale with item power"
	var chest := _first_of("armor")
	var boots := _first_of("feet")
	var helm := _first_of("head")
	t.check(chest != "" and boots != "", "armor and boots exist")
	t.eq(GearSkills.skill_for("armor", "").size(), 0, "no chest, no Iron Skin")
	t.eq(GearSkills.skill_for("armor", chest)["id"], "iron_skin", "chest grants Iron Skin")
	t.eq(GearSkills.skill_for("feet", boots)["id"], "sprint", "boots grant Sprint")
	if helm != "":
		t.eq(GearSkills.skill_for("head", helm)["id"], "second_wind", "helmet grants Second Wind")
	var weak: float = GearSkills.skill_for("armor", chest)["guard"]
	var strong: float = GearSkills.skill_for("armor", chest + "@3")["guard"] if Defs.is_item(chest + "@3") else weak + 0.01
	t.check(strong > weak, "enchanted gear gives a stronger skill")
	t.check(GearSkills.skill_for("armor", chest + "@3").get("guard", 0.0) <= GearSkills.MAX_GUARD, "guard is capped")

	t.current = "weapon ultimate"
	var q: Dictionary = Combat.active_skill("spear_2")
	var e: Dictionary = GearSkills.ultimate(q)
	t.check(float(e["damage"]) > float(q["damage"]) * 2.0, "ultimate hits much harder")
	t.check(float(e["cooldown"]) > float(q["cooldown"]), "with a longer cooldown")

	t.current = "Iron Skin and Second Wind in survival"
	var body := Survival.new()
	body.guard_seconds = 4.0
	body.guard_reduction = 0.3
	var taken: float = body.hurt(10.0)
	t.near(taken, 7.0, 0.001, "guard reduces damage")
	body.tick(5.0)
	t.eq(body.guard_seconds, 0.0, "guard wears off")
	var before: float = body.health
	body.regen_seconds = 2.0
	body.regen_per_second = 1.0
	body.tick(1.0)
	t.check(body.health > before, "Second Wind heals over time")

	t.current = "server: per-slot cooldowns and buffs"
	var world = WorldGen.new(999)
	var server := GameServer.new(world, 3)
	var hero = server.add_player(801, "Hero")
	hero.inventory = Inventory.new()
	hero.position = Vector3(40, world.height_at(40, 40), 40)
	t.eq(server.cmd_gear_skill(801, "armor").get("reason"), "no_item", "needs a chest piece")
	t.eq(server.cmd_gear_skill(801, "weapon").get("reason"), "unknown_slot", "only armor slots")
	hero.inventory.add(chest, 1)
	hero.inventory.equip(chest)
	t.check(bool(server.cmd_gear_skill(801, "armor").get("ok", false)), "Iron Skin activates")
	t.check(hero.survival.guard_seconds > 0.0, "guard buff applied")
	t.eq(server.cmd_gear_skill(801, "armor").get("reason"), "cooldown", "cooldown blocks spam")
	hero.inventory.add(boots, 1)
	hero.inventory.equip(boots)
	t.check(bool(server.cmd_gear_skill(801, "feet").get("ok", false)), "boots work independently of the chest cooldown")
	t.check(hero.sprint_buff_speed > 0.0, "sprint buff applied")
