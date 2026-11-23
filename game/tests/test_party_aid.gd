extends RefCounted
## Actual authoritative party medicine transactions and privacy regressions.
const Defs = preload("res://scripts/shared/defs.gd")
const PartyAid = preload("res://scripts/shared/party_aid.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "medical aid range and data safety"
	t.check(PartyAid.can_reach(Vector3.ZERO, Vector3(3.2, 0, 0)), "inclusive horizontal reach")
	t.check(not PartyAid.can_reach(Vector3.ZERO, Vector3(3.3, 0, 0)), "no distance exploit")
	t.check(not PartyAid.can_reach(Vector3.ZERO, Vector3(0, 3, 0)), "no healing across high floors")
	t.check(not PartyAid.can_reach(Vector3(INF, 0, 0), Vector3.ZERO), "nonfinite source rejected")
	t.check(not PartyAid.has_effect(Defs.item("canned_food"), 50.0, 20.0), "only medicine qualifies")
	t.check(not PartyAid.has_effect(Defs.item("bandage"), 100.0, 0.0), "no-effect heal rejected")
	t.check(PartyAid.has_effect(Defs.item("antibiotics"), 100.0, 20.0), "curing infection has value")
	t.check(PartyAid.has_effect(Defs.item("bandage"), 100.0, 0.0, 25.0),
			"bandaging a wound has value even at full health")
	t.check(not PartyAid.has_effect(Defs.item("antibiotics"), 100.0, 0.0, 25.0),
			"antibiotics do not pretend to stop bleeding")
	t.check(not PartyAid.has_effect(Defs.item("bandage"), 100.0, 0.0, NAN),
			"invalid wound severity is refused")

	t.current = "invalid aid potency and overflowed reach never authorize supplies"
	t.check(not PartyAid.can_reach(Vector3(-1.0e30, 0.0, 0.0),
		Vector3(1.0e30, 0.0, 0.0)),
		"overflowing horizontal separation cannot allow remote treatment")
	t.check(not PartyAid.supported_item("canned_food",
		{"kind": "food", "food": "50"}),
		"numeric strings cannot masquerade as authoritative food effects")
	t.check(not PartyAid.supported_item("water_bottle",
		{"kind": "drink", "drink": INF}),
		"non-finite water restoration cannot be shared")
	t.check(not PartyAid.has_effect({"kind": "medical", "heal": INF},
		50.0, 0.0), "non-finite healing cannot qualify for item consumption")
	t.check(not PartyAid.has_effect({"kind": "medical", "cure": "30"},
		100.0, 25.0), "textual cure potency cannot qualify as medicine")
	t.check(PartyAid.has_effect(Defs.item("bandage"), 50.0, 0.0),
		"real medical healing remains eligible")

	var world := WorldGen.new(733)
	var server := GameServer.new(world, 733)
	var medic = server.add_player(11, "Medic")
	var target = server.add_player(12, "Warrior")
	var stranger = server.add_player(13, "Unrelated")
	medic.position = _at(world, 8.0, 9.0)
	target.position = _at(world, 9.0, 9.0)
	stranger.position = _at(world, 10.0, 9.0)
	medic.inventory.add("bandage", 3)
	target.survival.hurt(50.0)
	t.current = "party consent is required before treating teammates"
	t.eq(server.cmd_party_aid(11, 11, "bandage").get("reason", ""), "self", "no self-aid exploit")
	t.eq(server.cmd_party_aid(11, 12, "bandage").get("reason", ""), "not_in_party", "strangers cannot heal remotely")
	t.eq(server.cmd_party_aid(11, 999, "bandage").get("reason", ""), "invalid_target", "missing targets are rejected")
	t.check(server.cmd_party_invite(11, 12).get("ok", false), "medic invites nearby warrior")
	t.check(server.cmd_party_accept(12).get("ok", false), "warrior joins party voluntarily")
	t.eq(server.cmd_party_aid(11, 13, "bandage").get("reason", ""), "not_in_party", "outsider cannot receive party care")
	t.eq(server.cmd_party_aid(11, 12, "cooked_fish").get("reason", ""), "not_shareable", "special meals cannot bypass their own rules")
	t.eq(server.cmd_party_aid(11, 12, "antibiotics").get("reason", ""), "not_carried", "missing items cannot be used")

	t.current = "successful aid consumes exactly one carried item and starts cooldown"
	var before_count: int = medic.inventory.count("bandage")
	var heal: Dictionary = server.cmd_party_aid(11, 12, "bandage")
	t.check(heal.get("ok", false), "bandage heals a real injured teammate")
	t.near(target.survival.health, 78.0, 0.001, "bandage restores 28 HP")
	t.eq(medic.inventory.count("bandage"), before_count - 1, "one bandage consumed")
	t.near(medic.party_aid_timer, PartyAid.COOLDOWN, 0.001, "cooldown applied")
	t.eq(server.cmd_party_aid(11, 12, "bandage").get("reason", ""), "cooldown", "spam rejected")
	t.eq(medic.inventory.count("bandage"), before_count - 1, "rejected attempt consumes nothing")
	server._tick_players(1.0)
	t.check(medic.party_aid_timer < PartyAid.COOLDOWN and medic.party_aid_timer > 0.0,
		"authoritative timer expires through simulation ticks")
	medic.party_aid_timer = 0.0
	target.survival.heal(100.0)
	t.eq(server.cmd_party_aid(11, 12, "bandage").get("reason", ""), "no_effect", "cannot waste medicine on healthy ally")
	t.eq(medic.inventory.count("bandage"), before_count - 1, "no-effect rejection leaves inventory unchanged")

	t.current = "full-health allied wounds are safely staunched"
	t.check(target.survival.add_bleeding(37.0), "wounded teammate has active bleeding")
	var bandage_result: Dictionary = server.cmd_party_aid(11, 12, "bandage")
	t.check(bool(bandage_result.get("ok", false)), "bandage treats bleeding without missing HP")
	t.near(target.survival.bleeding, 0.0, 0.001, "party first aid stops the bleeding")
	t.near(target.survival.health, Defs.MAX_HEALTH, 0.001, "treatment does not over-heal")
	t.near(float(bandage_result.get("bleeding_stopped", 0.0)), 37.0, 0.001,
			"medic is told how much bleeding was stopped")
	t.eq(medic.inventory.count("bandage"), before_count - 2,
			"healing another player with a wound spends exactly one bandage")
	medic.party_aid_timer = 0.0
	t.eq(server.cmd_party_aid(11, 12, "bandage").get("reason"), "no_effect",
			"already staunched wound does not waste another bandage")
	t.eq(medic.inventory.count("bandage"), before_count - 2,
			"refused repeat treatment does not duplicate supply consumption")

	t.current = "server permits field antiseptic and antibiotics for another player"
	target.survival.add_infection(60.0)
	t.check(target.survival.add_bleeding(16.0), "antiseptic target has infected bleeding wound")
	medic.inventory.add("field_antiseptic", 1)
	t.check(server.cmd_party_aid(11, 12, "field_antiseptic").get("ok", false),
		"field antiseptic treats an infected teammate")
	t.near(target.survival.infection, 20.0, 0.001, "field antiseptic removes 40 infection")
	t.near(target.survival.bleeding, 0.0, 0.001, "antiseptic also stops active bleeding")
	t.eq(medic.inventory.count("field_antiseptic"), 0, "one field antiseptic used")
	medic.party_aid_timer = 0.0
	medic.inventory.add("antibiotics", 1)
	t.check(server.cmd_party_aid(11, 12, "antibiotics").get("ok", false), "antibiotics may cure allied infection")
	t.near(target.survival.infection, 0.0, 0.001, "antibiotics cure remaining infection")
	t.eq(medic.inventory.count("antibiotics"), 0, "one antibiotic dose used")

	t.current = "authoritative party food and water sharing"
	t.check(PartyAid.supported_item("canned_food", Defs.item("canned_food")),
		"ordinary canned food is permitted")
	t.check(PartyAid.supported_item("water_bottle", Defs.item("water_bottle")),
		"plain drinking water is permitted")
	t.check(not PartyAid.supported_item("cooked_fish", Defs.item("cooked_fish")),
		"special meals cannot be transferred as basic sustenance")
	t.check(not PartyAid.has_effect(Defs.item("water_bottle"), 100.0, 0.0),
		"water is not wasted on a fully hydrated teammate")
	t.check(not PartyAid.has_effect(Defs.item("canned_food"), 100.0, 0.0),
		"food is not wasted on a fully fed teammate")
	t.check(PartyAid.has_effect(Defs.item("canned_food"), 100.0, 0.0, 0.0, 0.0, 20.0, 100.0),
		"food works when the recipient is hungry")
	t.check(PartyAid.has_effect(Defs.item("water_bottle"), 100.0, 0.0, 0.0, 0.0, 100.0, 20.0),
		"water works when the recipient is thirsty")
	t.check(not PartyAid.has_effect(Defs.item("water_bottle"), 100.0, 0.0, 0.0, 0.0, 100.0, NAN),
		"invalid thirst cannot cause item consumption")
	medic.party_aid_timer = 0.0
	medic.inventory.add("water_bottle", 2)
	medic.inventory.add("canned_food", 2)
	target.survival.thirst = 22.0
	target.survival.hunger = 38.0
	var before_water: int = medic.inventory.count("water_bottle")
	var water_share: Dictionary = server.cmd_party_aid(11, 12, "water_bottle")
	t.check(water_share.get("ok", false), "giver shares a real carried water bottle")
	t.near(target.survival.thirst, 67.0, 0.001, "recipient thirst restored by 45")
	t.near(float(water_share.get("drink", 0.0)), 45.0, 0.001,
		"authoritative result contains the actual thirst restored")
	t.eq(medic.inventory.count("water_bottle"), before_water - 1,
		"exactly one bottle leaves the giver")
	t.eq(server.cmd_party_aid(11, 12, "canned_food").get("reason", ""), "cooldown",
		"sharing food cannot bypass the existing party aid cooldown")
	medic.party_aid_timer = 0.0
	var before_food: int = medic.inventory.count("canned_food")
	var food_share: Dictionary = server.cmd_party_aid(11, 12, "canned_food")
	t.check(food_share.get("ok", false), "giver shares canned food")
	t.near(target.survival.hunger, 80.0, 0.001, "recipient hunger restored by 42")
	t.near(float(food_share.get("food", 0.0)), 42.0, 0.001,
		"result reflects actual hunger restoration")
	t.eq(medic.inventory.count("canned_food"), before_food - 1,
		"exactly one food ration leaves the giver")
	medic.party_aid_timer = 0.0
	target.survival.eat(100.0)
	t.eq(server.cmd_party_aid(11, 12, "canned_food").get("reason", ""), "no_effect",
		"full hunger cannot waste another ration")
	t.eq(medic.inventory.count("canned_food"), before_food - 1,
		"rejected food share consumes nothing")
	target.survival.drink(100.0)
	t.eq(server.cmd_party_aid(11, 12, "water_bottle").get("reason", ""), "no_effect",
		"full thirst cannot waste another bottle")
	t.eq(medic.inventory.count("water_bottle"), before_water - 1,
		"rejected water share consumes nothing")
	t.eq(server.cmd_party_aid(11, 13, "water_bottle").get("reason", ""), "not_in_party",
		"food and water cannot be sent to unrelated players")

	t.current = "automatic aid uses the real full medical catalog"
	var catalog: Array[String] = PartyAid.medical_items()
	for medical_id in ["bandage", "field_splint", "herbal_poultice",
			"spore_antidote", "purified_serum", "field_antiseptic"]:
		t.check(catalog.has(medical_id), "every supported medical item appears in party UI")
	t.check(not catalog.has("canned_food") and not catalog.has("field_triage_pack"),
		"food and group-only triage packs never appear as single-target medicine")
	t.check(catalog.size() >= 7, "party UI dynamically discovers all medical items")
	t.eq(PartyAid.best_item(null, 60.0, 0.0, 0.0, 0.0), "",
		"unknown inventory cannot invent free treatment")
	t.eq(PartyAid.best_item(medic.inventory, NAN, 0.0, 0.0, 0.0), "",
		"invalid client-independent vital values never select a medicine")

	t.current = "automatic aid prioritizes fractures, infection and bleeding"
	medic.inventory.add("field_splint", 1)
	target.survival.add_fracture(30.0)
	medic.party_aid_timer = 0.0
	var splinted: Dictionary = server.cmd_party_aid(11, 12, "auto")
	t.check(splinted.get("ok", false), "automatic support treats a genuine fracture")
	t.eq(splinted.get("item", ""), "field_splint", "auto uses the fracture-specific tool")
	t.near(target.survival.fracture, 0.0, 0.001, "splint restores mobility")
	t.eq(medic.inventory.count("field_splint"), 0, "one carried splint is spent")
	medic.party_aid_timer = 0.0
	medic.inventory.add("spore_antidote", 1)
	medic.inventory.add("herbal_poultice", 1)
	target.survival.add_infection(14.0)
	var herbs: Dictionary = server.cmd_party_aid(11, 12, "auto")
	t.check(herbs.get("ok", false), "automatic support cleanses infected ally")
	t.eq(herbs.get("item", ""), "herbal_poultice",
		"cheap herbal medicine is preferred over rare spore antidote")
	t.near(target.survival.infection, 0.0, 0.001, "herbs treat a mild infection")
	t.eq(medic.inventory.count("herbal_poultice"), 0, "herbal treatment spends one item")
	t.eq(medic.inventory.count("spore_antidote"), 1, "rare medicine is preserved")
	medic.party_aid_timer = 0.0
	target.survival.add_bleeding(34.0)
	var bandaged: Dictionary = server.cmd_party_aid(11, 12, "auto")
	t.eq(bandaged.get("item", ""), "bandage",
		"bleeding takes priority and the cheapest dressing is selected")
	t.near(target.survival.bleeding, 0.0, 0.001, "automatic dressing stops bleeding")
	t.eq(medic.inventory.count("bandage"), 0, "remaining bandage is actually spent")
	medic.party_aid_timer = 0.0
	var preserved: Dictionary = medic.inventory.to_dict()
	t.eq(server.cmd_party_aid(11, 12, "auto").get("reason", ""), "no_treatment",
		"healthy ally does not waste any carried medicine")
	t.eq(medic.inventory.to_dict(), preserved, "no-effect automatic aid is an atomic no-op")

	t.current = "ally healing respects progression-increased maximum health"
	medic.inventory.add("bandage", 1)
	target.survival.max_health = 125.0
	target.survival.health = 100.0
	t.check(PartyAid.has_effect(Defs.item("bandage"), 100.0, 0.0, 0.0, 0.0, 100.0, 100.0, 125.0),
		"healing an upgraded character at 100 HP is still effective")
	var upgraded: Dictionary = server.cmd_party_aid(11, 12, "auto")
	t.check(upgraded.get("ok", false), "auto heals a wounded high-health party member")
	t.eq(upgraded.get("item", ""), "bandage", "healing is chosen after urgent afflictions")
	t.near(target.survival.health, 125.0, 0.001, "medicine respects boosted HP cap")
	t.eq(medic.inventory.count("bandage"), 0, "upgraded ally consumes one real dressing")
	target.survival.max_health = Defs.MAX_HEALTH
	target.survival.health = Defs.MAX_HEALTH

	t.current = "range, verticality, death and leaving party block aid without charge"
	medic.party_aid_timer = 0.0
	target.survival.hurt(20.0)
	target.position = _at(world, 35.0, 9.0)
	t.eq(server.cmd_party_aid(11, 12, "bandage").get("reason", ""), "too_far", "distant heal rejected")
	target.position = medic.position + Vector3(0, 10, 0)
	t.eq(server.cmd_party_aid(11, 12, "bandage").get("reason", ""), "too_far", "healing through floors rejected")
	target.position = _at(world, 9.0, 9.0)
	target.survival.hurt(1000.0)
	t.eq(server.cmd_party_aid(11, 12, "bandage").get("reason", ""), "dead", "cannot revive the dead with a bandage")
	target.survival.reset()
	t.check(server.cmd_party_leave(12).get("ok", false), "ally may leave party")
	t.eq(server.cmd_party_aid(11, 12, "bandage").get("reason", ""), "not_in_party", "former member may not receive aid")
	medic.party_aid_timer = PartyAid.COOLDOWN
	server._spawn_player(medic)
	t.near(medic.party_aid_timer, 0.0, 0.001, "respawn resets aid cooldown")

	t.current = "medical events are private to giver and recipient"
	var net := Net.new()
	net.role = "server"
	net.sim = server
	t.check(net._event_visible_to({"type": "party_aid", "peer": 12, "by": 11}, 12), "recipient sees own aid event")
	t.check(net._event_visible_to({"type": "party_aid", "peer": 12, "by": 11}, 11), "medic sees aid event")
	t.check(not net._event_visible_to({"type": "party_aid", "peer": 12, "by": 11}, 13), "outsider cannot see private medical event")
	net.free()
