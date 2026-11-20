extends RefCounted
## Unsafe fishing rations, proper cooking, a paid herb remedy and persistent illness.

const Defs = preload("res://scripts/shared/defs.gd")
const FoodSafety = preload("res://scripts/shared/food_safety.gd")
const Survival = preload("res://scripts/shared/survival.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "raw fish remains a resource while prepared meals are safe"
	t.eq(FoodSafety.raw_fish_tier("raw_fish"), 1, "T1 raw fish is edible when desperate")
	for tier in range(2, 5):
		t.eq(FoodSafety.raw_fish_tier("raw_fish_%d" % tier), tier,
			"higher-tier catches have a real unsafe-food identity")
	t.eq(FoodSafety.raw_fish_tier("wood_1"), 0, "ordinary materials cannot be eaten")
	t.eq(FoodSafety.raw_fish_tier("raw_fish_10"), 0, "unregistered fish tiers are rejected")
	t.eq(Defs.item("raw_fish")["kind"], "resource",
		"fishing rewards remain craftable and tradeable")
	t.check(bool(Defs.item("raw_fish")["unsafe_food"]),
		"only marked fish resources may use the unsafe food route")
	t.eq(Defs.item("cooked_fish")["kind"], "food",
		"cooked fish retains the original safe food route")
	t.eq(Defs.recipes()["cooked_fish"]["station"], "campfire",
		"cooking requires the existing lit fire or settlement bench")
	t.eq(Defs.item(FoodSafety.REMEDY_ITEM)["kind"], "medical",
		"stomach remedy uses the existing medicine transport")
	t.eq(Defs.recipes()[FoodSafety.REMEDY_ITEM]["inputs"],
		{"wild_herbs": 2, "charcoal_filter": 1, "water_bottle": 1},
		"remedy uses foraged herbs plus real purification supplies")

	t.current = "server consumes raw fish exactly once and applies thirst-risk tradeoff"
	var world := WorldGen.new(521)
	var sim := GameServer.new(world, 521)
	var p = sim.add_player(811, "Hungry Scout")
	t.eq(sim.cmd_use(p.id, "raw_fish").get("reason", ""), "not_carried",
		"imaginary fish cannot be consumed")
	p.inventory.add("wood_1", 1)
	t.eq(sim.cmd_use(p.id, "wood_1").get("reason", ""), "not_usable",
		"players cannot bypass resource rules by eating raw materials")
	p.inventory.add("raw_fish", 2)
	p.survival.hunger = 100.0
	t.eq(sim.cmd_use(p.id, "raw_fish").get("reason", ""), "not_hungry",
		"full survivors cannot waste raw fish or exploit hunger XP")
	t.eq(p.inventory.count("raw_fish"), 2, "failed eating keeps both raw fish")
	p.survival.hunger = 35.0
	var use: Dictionary = sim.cmd_use(p.id, "raw_fish")
	t.check(bool(use.get("ok", false)) and bool(use.get("ate_raw_fish", false)),
		"actual server item action consumes one edible raw fish")
	t.eq(p.inventory.count("raw_fish"), 1, "one fish is spent, never two")
	t.near(p.survival.hunger, 35.0 + FoodSafety.raw_hunger(1), 0.0001,
		"desperate raw meal gives modest calories")
	t.near(p.survival.food_poisoning, FoodSafety.raw_poison(1), 0.0001,
		"raw fish causes the server-owned illness")
	t.eq(sim.snapshot_for(p.id)["you"]["food_poisoning"], p.survival.food_poisoning,
		"the illness is replicated to the owning player's HUD")
	t.check(p.dirty_inventory and p.dirty_character,
		"item and symptom both take part in persistence")

	t.current = "illness advances consistently, costs thirst/health and naturally fades"
	var initial: float = p.survival.food_poisoning
	var one_big: Dictionary = FoodSafety.progress(initial, 30.0)
	var one_small := {"remaining": initial, "extra_thirst": 0.0, "damage": 0.0}
	for index in 30:
		var step: Dictionary = FoodSafety.progress(float(one_small["remaining"]), 1.0)
		one_small["remaining"] = step["remaining"]
		one_small["extra_thirst"] = float(one_small["extra_thirst"]) + float(step["extra_thirst"])
		one_small["damage"] = float(one_small["damage"]) + float(step["damage"])
	t.near(float(one_big["remaining"]), float(one_small["remaining"]), 0.0001,
		"integrated duration is not frame-rate dependent")
	t.near(float(one_big["extra_thirst"]), float(one_small["extra_thirst"]), 0.0001,
		"thirst penalty is frame-rate independent")
	t.near(float(one_big["damage"]), float(one_small["damage"]), 0.0001,
		"health damage is frame-rate independent")
	var clean := Survival.new()
	clean.thirst = 70.0
	clean.hunger = 70.0
	p.survival.thirst = 70.0
	p.survival.hunger = 70.0
	p.survival.health = 100.0
	clean.tick(30.0)
	p.survival.tick(30.0)
	t.check(p.survival.thirst < clean.thirst, "poisoning drains extra drinking water")
	t.check(p.survival.health < clean.health, "poisoning inflicts gradual damage")
	t.check(p.survival.food_poisoning < initial, "symptoms naturally improve")
	var before_resume: float = p.survival.food_poisoning
	var saved: Dictionary = sim.character_data(p)
	t.eq(saved["food_poisoning"], before_resume, "symptoms persist in the character save")
	p.survival.food_poisoning = 0.0
	t.check(sim.apply_character(p, saved), "save restores the illness")
	t.near(p.survival.food_poisoning, before_resume, 0.0001,
		"reconnecting cannot clear poisoning")
	for bad_value in [-1.0, INF, NAN, 101.0, "31", true]:
		var broken: Dictionary = saved.duplicate(true)
		broken["food_poisoning"] = bad_value
		t.check(not sim.apply_character(p, broken), "invalid poison save is rejected")
		t.near(p.survival.food_poisoning, before_resume, 0.0001,
			"invalid loading never mutates the live survivor")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("food_poisoning")
	t.check(sim.apply_character(p, legacy), "pre-poisoning characters load")
	t.eq(p.survival.food_poisoning, 0.0, "legacy saves begin without poison")

	t.current = "crafting and applying the herbal remedy uses actual materials"
	t.eq(sim.cmd_use(p.id, FoodSafety.REMEDY_ITEM).get("reason", ""),
		"not_carried", "missing medicine cannot cure")
	# Starter characters already carry clean water; remove it for the missing-input test.
	p.inventory.remove("water_bottle", p.inventory.count("water_bottle"))
	p.inventory.add("wild_herbs", 2)
	p.inventory.add("charcoal_filter", 1)
	t.eq(sim.cmd_craft(p.id, FoodSafety.REMEDY_ITEM).get("reason", ""),
		"missing_inputs", "remedy needs clean water")
	p.inventory.add("water_bottle", 1)
	t.check(bool(sim.cmd_craft(p.id, FoodSafety.REMEDY_ITEM).get("ok", false)),
		"crafting the real antidote succeeds with full inputs")
	t.eq(p.inventory.count("wild_herbs"), 0, "foraged herbs were spent")
	t.eq(p.inventory.count("charcoal_filter"), 0, "filter was spent")
	t.eq(p.inventory.count(FoodSafety.REMEDY_ITEM), 1, "one remedy enters the backpack")
	t.eq(sim.cmd_use(p.id, FoodSafety.REMEDY_ITEM).get("reason", ""), "no_effect",
		"healthy survivor cannot waste a remedy")
	t.eq(p.inventory.count(FoodSafety.REMEDY_ITEM), 1,
		"ineffective medicine is not consumed")
	p.survival.add_food_poisoning(65.0)
	t.check(bool(sim.cmd_use(p.id, FoodSafety.REMEDY_ITEM).get("ok", false)),
		"server accepts paid recovery for actual poisoning")
	t.eq(p.inventory.count(FoodSafety.REMEDY_ITEM), 0,
		"successful healing spends exactly one dose")
	t.eq(p.survival.food_poisoning, 0.0, "herbal remedy cures a moderate illness")

	t.current = "automatic and cooperative medicine treats actual food poisoning"
	p.survival.food_poisoning = 34.0
	p.inventory.add(FoodSafety.REMEDY_ITEM, 1)
	var automatic: Dictionary = sim.cmd_quick_medicine(p.id)
	t.check(bool(automatic.get("ok", false)), "smart medicine uses a real dose for poisoning")
	t.eq(str(automatic.get("item", "")), FoodSafety.REMEDY_ITEM,
		"server-selected auto treatment chooses the stomach remedy")
	t.eq(p.survival.food_poisoning, 0.0, "auto treatment clears moderate poison")
	var medic = sim.add_player(812, "Herbal Medic")
	var companion = sim.add_player(813, "Fishing Companion")
	var town: Vector3 = Vector3(0.0, world.height_at(0.0, 0.0), 0.0)
	medic.position = town
	companion.position = town
	medic.inventory.add(FoodSafety.REMEDY_ITEM, 2)
	companion.survival.food_poisoning = 50.0
	t.eq(sim.cmd_party_aid(medic.id, companion.id, FoodSafety.REMEDY_ITEM).get("reason", ""),
		"not_in_party", "strangers cannot cure each other")
	t.check(bool(sim.cmd_party_invite(medic.id, companion.id).get("ok", false)),
		"medic can invite a survivor nearby")
	t.check(bool(sim.cmd_party_accept(companion.id).get("ok", false)),
		"companion voluntarily joins party")
	var aid: Dictionary = sim.cmd_party_aid(medic.id, companion.id, "auto")
	t.check(bool(aid.get("ok", false)), "party auto-aid identifies food poisoning")
	t.eq(str(aid.get("item", "")), FoodSafety.REMEDY_ITEM,
		"party healer selects a carried stomach remedy")
	t.near(float(aid.get("food_poison_treated", 0.0)), 50.0, 0.0001,
		"party response reports verified sickness removed")
	t.eq(companion.survival.food_poisoning, 0.0, "ill party member is cured")
	t.eq(medic.inventory.count(FoodSafety.REMEDY_ITEM), 1,
		"party medicine costs one real dose")
	medic.party_aid_timer = 0.0
	t.eq(sim.cmd_party_aid(medic.id, companion.id, FoodSafety.REMEDY_ITEM).get("reason", ""),
		"no_effect", "healthy allies do not waste medicine")
	t.eq(medic.inventory.count(FoodSafety.REMEDY_ITEM), 1,
		"no-effect party aid preserves the second dose")

	t.current = "higher-tier raw fish stacks symptoms, cooking never introduces poison"
	p.survival.hunger = 20.0
	p.survival.food_poisoning = 90.0
	p.inventory.add("raw_fish_4", 1)
	t.check(bool(sim.cmd_use(p.id, "raw_fish_4").get("ok", false)),
		"T4 fish remains edible with larger dangerous consequences")
	t.eq(p.survival.food_poisoning, FoodSafety.MAX_SEVERITY,
		"raw-food poisoning severity has a hard upper bound")
	p.inventory.add("cooked_fish", 1)
	var before_cooked: float = p.survival.food_poisoning
	t.check(bool(sim.cmd_use(p.id, "cooked_fish").get("ok", false)),
		"ordinary cooked food is still usable")
	t.eq(p.survival.food_poisoning, before_cooked,
		"properly cooked fish adds no new poisoning")
	p.survival.reset()
	t.eq(p.survival.food_poisoning, 0.0, "respawning clears food poisoning")
	t.eq(FoodSafety.progress(0.0, 120.0)["damage"], 0.0,
		"recovered survivors do not take phantom poison damage")
