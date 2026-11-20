extends RefCounted
## Atomic cross-backpack transfers, live-camp geometry, server party security,
## rate limiting, private events and persistent inventory flags.
const CampProvisions = preload("res://scripts/shared/camp_provisions.gd")
const PartyAid = preload("res://scripts/shared/party_aid.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const BarricadeTest = preload("res://tests/test_barricades.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, point: Vector2) -> Vector3:
	return Vector3(point.x, world.height_at(point.x, point.y), point.y)


func run(t) -> void:
	t.current = "fixed allowed packages and shared fire geometry"
	t.eq(CampProvisions.package_items("kit"),
		{"canned_food": 1, "water_bottle": 1}, "kit pairs exact existing resources")
	t.eq(CampProvisions.package_items("stew"),
		{"camp_fish_stew": 1}, "prepared meal remains a real item")
	for invalid in ["", "all", "pistol", "silver", "antibiotics"]:
		t.eq(CampProvisions.package_items(invalid), {}, "unsafe item choice denied")
	var a := Vector3(10, 5, 10)
	var b := Vector3(11, 5, 10)
	var camp := {"x": 10.0, "y": 5.0, "z": 10.0, "expires": 60.0}
	t.check(CampProvisions.shared_fire({7: camp}, a, b, 1.0),
		"nearby teammate stands at same live campfire")
	t.check(not CampProvisions.shared_fire({}, a, b, 1.0),
		"no fire means no handoff")
	t.check(not CampProvisions.shared_fire({7: camp}, a, b, 60.0),
		"expired fire cannot authorize transfer")
	t.check(not CampProvisions.shared_fire({7: camp}, a, Vector3(19, 5, 10), 1.0),
		"recipient cannot receive supplies from afar")
	t.check(not CampProvisions.shared_fire({7: camp}, a, Vector3(11, 9, 10), 1.0),
		"other floor cannot receive supplies")
	t.check(not CampProvisions.shared_fire({7: camp}, Vector3.INF, b, 1.0),
		"nonfinite positions fail closed")

	t.current = "staged inventory handoff never loses a partial kit"
	var donor := Inventory.new(3)
	var receiver := Inventory.new(3)
	donor.add("canned_food", 2)
	donor.add("water_bottle", 1)
	t.eq(CampProvisions.transfer(donor, receiver, "kit"), "",
		"single transaction moves two provisions")
	t.eq(donor.count("canned_food"), 1, "donor pays one ration")
	t.eq(donor.count("water_bottle"), 0, "donor pays one bottle")
	t.eq(receiver.count("canned_food"), 1, "receiver gets real food")
	t.eq(receiver.count("water_bottle"), 1, "receiver gets real water")
	var after_donor: Dictionary = donor.to_dict()
	var after_receiver: Dictionary = receiver.to_dict()
	t.eq(CampProvisions.transfer(donor, receiver, "kit"),
		"missing_supplies", "repeated request cannot mint another bottle")
	t.eq(donor.to_dict(), after_donor, "donor unchanged on failed replay")
	t.eq(receiver.to_dict(), after_receiver, "receiver unchanged on failed replay")
	var full := Inventory.new(2)
	full.add("stone_1", 100)
	full.add("wood_1", 100)
	var funded := Inventory.new(3)
	funded.add("canned_food", 1)
	funded.add("water_bottle", 1)
	after_donor = funded.to_dict()
	after_receiver = full.to_dict()
	t.eq(CampProvisions.transfer(funded, full, "kit"), "no_space",
		"recipient full refuses all items")
	t.eq(funded.to_dict(), after_donor, "full bag cannot destroy donor's supplies")
	t.eq(full.to_dict(), after_receiver, "full bag remains unchanged")
	var partial := Inventory.new(2)
	partial.add("canned_food", 1)
	partial.add("stone_1", 5)
	after_receiver = partial.to_dict()
	t.eq(CampProvisions.transfer(funded, partial, "kit"), "no_space",
		"partial capacity cannot accept half a kit")
	t.eq(funded.to_dict(), after_donor, "partial failure rolls donor back")
	t.eq(partial.to_dict(), after_receiver, "recipient sees no half kit")
	t.eq(CampProvisions.transfer(funded, funded, "kit"), "invalid_inventory",
		"self-inventory cannot duplicate goods")
	var meal := Inventory.new()
	meal.add("camp_fish_stew", 1)
	t.eq(CampProvisions.transfer(meal, receiver, "stew"), "",
		"new cooked food participates in camp provisioning")
	t.eq(receiver.count("camp_fish_stew"), 1, "stew arrives physically")

	t.current = "server enforces party consent, live campfire and save flags"
	var world := WorldGen.new(214)
	var sim := GameServer.new(world, 214)
	var spot: Vector2 = BarricadeTest.new()._find_place(world)
	t.check(spot != Vector2.ZERO, "real dry place found for a camp")
	if spot == Vector2.ZERO:
		return
	var source = sim.add_player(111, "Cook")
	var ally = sim.add_player(112, "Scout")
	var outsider = sim.add_player(113, "Stranger")
	var origin := spot + Vector2(-2.8, 0)
	source.position = _at(world, origin)
	ally.position = _at(world, origin + Vector2(0, 0.8))
	outsider.position = _at(world, origin + Vector2(-1.0, 0))
	source.inventory.add("canned_food", 4)
	source.inventory.add("water_bottle", 4)
	source.inventory.add("wood_1", 6)
	source.inventory.add("stone_1", 1)
	t.eq(sim.cmd_party_provision(999, 112, "kit").get("reason", ""), "dead",
		"fake RPC sender is rejected")
	t.eq(sim.cmd_party_provision(111, 111, "kit").get("reason", ""), "self",
		"self-provision disallowed")
	t.eq(sim.cmd_party_provision(111, 999, "kit").get("reason", ""), "invalid_target",
		"unknown recipient is rejected")
	t.eq(sim.cmd_party_provision(111, 112, "kit").get("reason", ""), "not_in_party",
		"no supply exchange without party consent")
	t.check(sim.cmd_party_invite(111, 112).get("ok", false), "invite real ally")
	t.check(sim.cmd_party_accept(112).get("ok", false), "ally accepts invitation")
	t.eq(sim.cmd_party_provision(111, 113, "kit").get("reason", ""), "not_in_party",
		"stranger cannot receive supplies")
	t.eq(sim.cmd_party_provision(111, 112, "invalid").get("reason", ""),
		"invalid_package", "arbitrary item selection rejected")
	t.eq(sim.cmd_party_provision(111, 112, "kit").get("reason", ""), "no_fire",
		"distance and party alone are not a camp")
	ally.position = _at(world, origin + Vector2(-8, 0))
	outsider.position = _at(world, origin + Vector2(-9, 0))
	var lit: Dictionary = sim.cmd_light_campfire(111, spot.x, spot.y)
	t.check(lit.get("ok", false), "real material-paid fire burns at server site")
	if not bool(lit.get("ok", false)):
		return
	ally.position = _at(world, origin + Vector2(0, 0.8))
	outsider.position = _at(world, origin + Vector2(-1, 0))
	var food_before: int = source.inventory.count("canned_food")
	var water_before: int = source.inventory.count("water_bottle")
	var ally_food: int = ally.inventory.count("canned_food")
	var ally_water: int = ally.inventory.count("water_bottle")
	var delivered: Dictionary = sim.cmd_party_provision(111, 112, "kit")
	t.check(delivered.get("ok", false), "server transfers a full kit")
	t.eq(source.inventory.count("canned_food"), food_before - 1, "donor debited food")
	t.eq(source.inventory.count("water_bottle"), water_before - 1, "donor debited water")
	t.eq(ally.inventory.count("canned_food"), ally_food + 1, "recipient credited food")
	t.eq(ally.inventory.count("water_bottle"), ally_water + 1, "recipient credited water")
	t.near(source.party_aid_timer, PartyAid.COOLDOWN, 0.001,
		"aid and supply exchange share a cooldown")
	t.eq(sim.cmd_party_provision(111, 112, "kit").get("reason", ""), "cooldown",
		"repeated requests cannot spam or mint supplies")
	t.check(source.dirty_inventory and ally.dirty_inventory,
		"both backpack saves become dirty")
	t.check(source.dirty_character and ally.dirty_character,
		"both character saves become dirty")
	var provision_event: Dictionary = {}
	for event in sim.drain_events():
		if event.get("type", "") == "party_provision":
			provision_event = event
	t.check(not provision_event.is_empty(), "one real recipient event created")
	if not provision_event.is_empty():
		var net := Net.new()
		net.role = "server"
		net.sim = sim
		t.check(net.has_method("c_party_provision"),
			"authenticated network RPC is registered")
		t.check(net._event_visible_to(provision_event, 111), "sender can see receipt")
		t.check(net._event_visible_to(provision_event, 112), "recipient can see delivery")
		t.check(not net._event_visible_to(provision_event, 113),
			"unrelated players cannot read a private transfer")
		net.free()
	t.current = "risk, distance and fire expiry do not spend supplies"
	source.party_aid_timer = 0.0
	source.combat_tag_until = sim.time + 10.0
	var protected: Dictionary = source.inventory.to_dict()
	t.eq(sim.cmd_party_provision(111, 112, "food").get("reason", ""), "in_combat",
		"combat restriction stops vulnerable supply transfer")
	source.combat_tag_until = 0.0
	ally.position = _at(world, origin + Vector2(-8, 0))
	t.eq(sim.cmd_party_provision(111, 112, "food").get("reason", ""), "too_far",
		"remote receiver cannot claim items")
	ally.position = _at(world, origin + Vector2(0, 0.8))
	sim.time = float(sim.campfires[int(lit["id"])]["expires"]) + 0.01
	t.eq(sim.cmd_party_provision(111, 112, "food").get("reason", ""), "no_fire",
		"expired campfire cannot authorize supplies")
	t.eq(source.inventory.to_dict(), protected, "rejected transfers spend nothing")
