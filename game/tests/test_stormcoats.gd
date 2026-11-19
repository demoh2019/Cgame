extends RefCounted
## Craftable weather gear must exchange PvP protection for storm survival.
## Authoritative weather, no ghost equipment or client-authored climate.
const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const Weather = preload("res://scripts/shared/weather.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "stormcoat tier progression and meaningful equipment choices"
	t.eq(Weather.protection(""), 0.0, "no armor supplies no insulation")
	t.eq(Weather.protection("not_an_item"), 0.0, "ghost item IDs cannot supply warmth")
	t.eq(Weather.protection("pistol"), 0.0, "weapon IDs cannot substitute for armor")
	t.near(Weather.protection("jacket_2"), 0.35, 0.0001,
		"regular jackets keep historical 35 percent protection")
	for tier in range(2, Defs.MAX_TIER + 1):
		var coat_id: String = "storm_coat_%d" % tier
		var jacket_id: String = "jacket_%d" % tier
		var item: Dictionary = Defs.item(coat_id)
		var recipe: Dictionary = Defs.recipes()[coat_id]
		t.eq(item["kind"], "armor", "T%d stormcoat uses normal equipment slot" % tier)
		t.eq(Defs.tier_of(coat_id), tier, "weather clothing follows artisan tier")
		t.eq(recipe["station"], "workbench", "stormcoats need a real workstation")
		t.eq(recipe["inputs"]["cloth_%d" % tier], 6, "six cloth consumed for insulation")
		t.eq(recipe["inputs"]["fiber_%d" % tier], 4, "four fiber consumed for insulation")
		t.check(Weather.protection(coat_id) > Weather.protection(jacket_id),
			"stormcoat is warmer than same-tier battle gear")
		t.check(Combat.apply_armor(100.0, coat_id) > Combat.apply_armor(100.0, jacket_id),
			"cold-weather choice intentionally sacrifices physical protection")
	t.near(Weather.protection("storm_coat_2"), 0.55, 0.0001, "T2 55 percent")
	t.near(Weather.protection("storm_coat_3"), 0.67, 0.0001, "T3 67 percent")
	t.near(Weather.protection("storm_coat_4"), 0.78, 0.0001, "T4 78 percent")

	t.current = "real server crafting and inventory material conservation"
	var world := WorldGen.new(311)
	var sim := GameServer.new(world, 311)
	var smith = sim.add_player(411, "Cold Weather Tailor")
	smith.position = _at(world, 9.0, 0.0)
	for tier in range(2, Defs.MAX_TIER + 1):
		var coat_id: String = "storm_coat_%d" % tier
		var recipe: Dictionary = Defs.recipes()[coat_id]
		for id in recipe["inputs"]:
			smith.inventory.add(str(id), int(recipe["inputs"][id]))
		var before: Dictionary = smith.inventory.to_dict()
		t.eq(sim.cmd_craft(411, coat_id).get("reason", ""), "need_skill",
			"prior tier artisan cannot craft T%d gear" % tier)
		t.eq(smith.inventory.to_dict(), before, "failed craft does not consume input materials")
		smith.progression.crafting_xp = (tier - 1) * 100
		t.check(bool(sim.cmd_craft(411, coat_id).get("ok", false)),
			"trained crafter makes real T%d expedition armor" % tier)
		t.eq(smith.inventory.count(coat_id), 1, "one coat produced, no duplicate")
		t.eq(smith.inventory.count("cloth_%d" % tier), 0, "coat consumes its cloth")
		t.eq(smith.inventory.count("fiber_%d" % tier), 0, "coat consumes its fiber")
		t.check(smith.inventory.equip(coat_id), "new coat is wearable")
		t.eq(smith.inventory.armor, coat_id, "equipped armor is visible to server")

	t.current = "actual cold storm applies tiered insulation on server tick"
	var bare = sim.add_player(412, "Unprotected")
	var protected = sim.add_player(413, "Storm Ranger")
	var point: Vector3 = _at(world, 280.0, 230.0)
	bare.position = point
	protected.position = point
	bare.inventory.armor = ""
	protected.inventory.add("storm_coat_4", 1)
	protected.inventory.equip("storm_coat_4")
	var storm: Dictionary = {}
	for phase in range(150):
		sim.time = float(phase) * Weather.CHANGE_SECONDS + 1.0
		storm = Weather.conditions(world, point.x, point.z, sim.time)
		if float(storm.get("severity", 0.0)) > 0.0:
			break
	t.check(float(storm.get("severity", 0.0)) > 0.0, "real world offers hazardous weather")
	if float(storm.get("severity", 0.0)) <= 0.0:
		return
	sim._tick_players(20.0)
	t.check(bare.survival.exposure > protected.survival.exposure,
		"server cold exposure decreases only for equipped insulated player")
	t.near(protected.survival.exposure,
		float(storm["severity"]) * (1.0 - 0.78) * 0.55 * 20.0, 0.001,
		"real server tick uses item insulation rather than client-provided modifier")
	t.near(float(sim.snapshot_for(413)["you"]["weather_insulation"]), 0.78, 0.0001,
		"online HUD receives server-derived protection")
	t.eq(float(sim.snapshot_for(412)["you"]["weather_insulation"]), 0.0,
		"unprotected player receives no fake equipment stat")

	t.current = "lost gear cannot retain temperature buffs"
	protected.inventory.remove("storm_coat_4", 1)
	protected.inventory.armor = "storm_coat_4" # Simulate stale equipment.
	protected.survival.exposure = 0.0
	bare.survival.exposure = 0.0
	t.eq(float(sim.snapshot_for(413)["you"]["weather_insulation"]), 0.0,
		"lost gear does not appear as insulation in network state")
	sim._tick_players(20.0)
	t.near(protected.survival.exposure, bare.survival.exposure, 0.001,
		"missing inventory item never grants warmth on subsequent server ticks")
