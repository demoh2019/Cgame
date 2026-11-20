extends RefCounted
## Paid expedition medicine: crafting, self-care, party aid and save integrity.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")

const ITEM_ID := "expedition_trauma_kit"


func run(t) -> void:
	t.current = "trauma kit: registered recipe and atomic workbench crafting"
	var data: Dictionary = Defs.item(ITEM_ID)
	t.eq(data.get("kind", ""), "medical", "uses server-authoritative medical rules")
	t.eq(Defs.tier_of(ITEM_ID), 2, "requires tier-two crafting")
	t.near(float(data.get("heal", 0.0)), 38.0, 0.001, "restores health")
	t.near(float(data.get("cure", 0.0)), 15.0, 0.001, "cures infection")
	t.near(float(data.get("fracture_treatment", 0.0)), 45.0, 0.001, "treats fracture")
	t.check(bool(data.get("stop_bleeding", false)), "stops active bleeding")
	var recipe: Dictionary = Defs.recipes()[ITEM_ID]
	t.eq(recipe["station"], "workbench", "requires a workbench")
	t.eq(recipe["inputs"], {
		"bandage": 2, "field_splint": 1, "field_antiseptic": 1, "cloth_2": 2
	}, "all materials have an actual inventory cost")
	var ingredients := Inventory.new()
	t.eq(Crafting.craft(ingredients, ITEM_ID, true), Crafting.Result.MISSING_INPUTS,
		"cannot craft without ingredients")
	for ingredient in recipe["inputs"]:
		ingredients.add(str(ingredient), int(recipe["inputs"][ingredient]))
	t.eq(Crafting.craft(ingredients, ITEM_ID, false), Crafting.Result.NO_STATION,
		"cannot bypass workbench")
	t.eq(ingredients.count("field_splint"), 1, "failed craft does not consume")
	t.eq(Crafting.craft(ingredients, ITEM_ID, true), Crafting.Result.OK,
		"workbench crafting succeeds with materials")
	t.eq(ingredients.count(ITEM_ID), 1, "one kit crafted")
	t.eq(ingredients.count("field_splint"), 0, "splint consumed")
	t.eq(ingredients.count("cloth_2"), 0, "tier-two cloth consumed")

	t.current = "trauma kit: no-waste self-care, mixed injuries and persistence"
	var world := WorldGen.new(621)
	var server := GameServer.new(world, 621)
	var medic = server.add_player(621, "Expedition Medic")
	t.eq(server.cmd_use(medic.id, ITEM_ID).get("reason", ""), "not_carried",
		"no free healing from absent kit")
	medic.inventory.add(ITEM_ID, 3)
	t.eq(server.cmd_use(medic.id, ITEM_ID).get("reason", ""), "no_effect",
		"healthy player cannot waste supplies")
	t.eq(medic.inventory.count(ITEM_ID), 3, "no effect means no debit")
	medic.survival.health = 50.0
	medic.survival.add_infection(30.0)
	medic.survival.add_bleeding(40.0)
	medic.survival.add_fracture(60.0)
	t.check(bool(server.cmd_use(medic.id, ITEM_ID).get("ok", false)),
		"one kit treats simultaneous injuries")
	t.near(medic.survival.health, 50.0 + 38.0 * (1.0 + medic.skills.bonus("heal_power")),
		0.001, "self-heal follows existing skill scaling")
	t.near(medic.survival.infection, 15.0, 0.001, "infection reduced")
	t.near(medic.survival.bleeding, 0.0, 0.001, "bleeding stopped")
	t.near(medic.survival.fracture, 15.0, 0.001, "fracture partially treated")
	t.eq(medic.inventory.count(ITEM_ID), 2, "exactly one kit consumed")
	var save: Dictionary = server.character_data(medic)
	t.check(server.valid_character_data(save), "kit survives strict save validation")
	medic.inventory.remove(ITEM_ID, 2)
	t.check(server.apply_character(medic, save), "saved character restores")
	t.eq(medic.inventory.count(ITEM_ID), 2, "unspent kits persist")
	t.near(medic.survival.fracture, 15.0, 0.001, "remaining fracture persists")
	medic.survival.health = medic.survival.max_health
	medic.survival.infection = 0.0
	t.check(bool(server.cmd_use(medic.id, ITEM_ID).get("ok", false)),
		"fracture-only treatment works at full HP")
	t.near(medic.survival.fracture, 0.0, 0.001, "fracture-only treatment clears injury")
	t.eq(medic.inventory.count(ITEM_ID), 1, "fracture-only treatment consumes one")

	t.current = "trauma kit: authenticated, nearby party aid"
	var patient = server.add_player(622, "Wounded Scout")
	medic.position = Vector3(9.0, world.height_at(9.0, 9.0), 9.0)
	patient.position = medic.position + Vector3(1.0, 0.0, 0.0)
	patient.survival.health = 60.0
	patient.survival.add_bleeding(22.0)
	patient.survival.add_fracture(45.0)
	t.eq(server.cmd_party_aid(medic.id, patient.id, ITEM_ID).get("reason", ""),
		"not_in_party", "strangers cannot receive involuntary aid")
	t.check(bool(server.cmd_party_invite(medic.id, patient.id).get("ok", false)),
		"invitation offered")
	t.check(bool(server.cmd_party_accept(patient.id).get("ok", false)),
		"patient consents to the party")
	patient.position += Vector3(12.0, 0.0, 0.0)
	t.eq(server.cmd_party_aid(medic.id, patient.id, ITEM_ID).get("reason", ""),
		"too_far", "cannot heal distant party member")
	patient.position = medic.position + Vector3(1.0, 0.0, 0.0)
	var before: int = medic.inventory.count(ITEM_ID)
	t.check(bool(server.cmd_party_aid(medic.id, patient.id, ITEM_ID).get("ok", false)),
		"medic treats injured ally using a carried kit")
	t.near(patient.survival.health, 98.0, 0.001, "patient receives health")
	t.near(patient.survival.bleeding, 0.0, 0.001, "patient stops bleeding")
	t.near(patient.survival.fracture, 0.0, 0.001, "patient's fracture is treated")
	t.eq(medic.inventory.count(ITEM_ID), before - 1, "medic debited exactly once")
	t.eq(server.cmd_party_aid(medic.id, patient.id, ITEM_ID).get("reason", ""),
		"cooldown", "healing cooldown remains authoritative")
	medic.party_aid_timer = 0.0
	t.eq(server.cmd_party_aid(medic.id, patient.id, ITEM_ID).get("reason", ""),
		"not_carried", "consumed kit cannot be reused")
