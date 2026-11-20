extends RefCounted
## Group-cooking integration: real lit fire, accepted roster, finite distance,
## exactly priced meals and recipient-only messages.
const PartyFeast = preload("res://scripts/shared/party_feast.gd")
const HeartyMeal = preload("res://scripts/shared/hearty_meal.gd")
const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Net = preload("res://scripts/shared/net.gd")
const BarricadeTest = preload("res://tests/test_barricades.gd")


func _at(world, position: Vector2) -> Vector3:
	return Vector3(position.x, world.height_at(position.x, position.y), position.y)


func run(t) -> void:
	t.current = "server-side active fire and cooked recipe checks"
	var fake_fire := {"id": 5, "x": 10.0, "y": 1.0, "z": 10.0, "expires": 30.0}
	t.check(PartyFeast.near_fire(fake_fire, Vector3(10, 1, 10), 5.0),
		"real-time active campfire permits a nearby survivor")
	t.check(not PartyFeast.near_fire(fake_fire, Vector3(16, 1, 10), 5.0),
		"survivors outside camp radius cannot share provisions")
	t.check(not PartyFeast.near_fire(fake_fire, Vector3(10, 6, 10), 5.0),
		"vertical separation prevents feeding teammates through floors")
	t.check(not PartyFeast.near_fire(fake_fire, Vector3(NAN, 1, 10), 5.0),
		"nonfinite player coordinates cannot qualify")
	t.check(not PartyFeast.near_fire(fake_fire, Vector3(10, 1, 10), 30.0),
		"expired campfire no longer provides a dining area")
	t.eq(PartyFeast.food_tier("cooked_fish_4"), 4,
		"high-tier coastal meals use existing cooked food")
	t.eq(PartyFeast.food_tier("canned_food"), 0,
		"ordinary canned food cannot be forged into a group feast")
	t.near(PartyFeast.COOLDOWN, 20.0, 0.001, "sharing is cooldown limited")

	t.current = "real world campfire and consenting party roster"
	var world := WorldGen.new(214)
	var sim := GameServer.new(world, 214)
	var site: Vector2 = BarricadeTest.new()._find_place(world)
	t.check(site != Vector2.ZERO, "find dry passable site outside protected settlement")
	if site == Vector2.ZERO:
		return
	var origin: Vector2 = site + Vector2(-2.8, 0.0)
	var cook = sim.add_player(41, "ExpeditionCook")
	var ally = sim.add_player(42, "Scout")
	var distant = sim.add_player(43, "Ranger")
	var outsider = sim.add_player(44, "Stranger")
	cook.position = _at(world, origin)
	ally.position = _at(world, origin + Vector2(0, 1.0))
	distant.position = _at(world, origin + Vector2(0, -1.0))
	outsider.position = _at(world, origin + Vector2(0, -2.0))
	cook.inventory.add("cooked_fish", 1)
	cook.inventory.add("wood_1", 3)
	cook.inventory.add("stone_1", 1)
	t.eq(sim.cmd_party_feast(41, "cooked_fish").get("reason", ""), "not_in_party",
		"a solo survivor cannot buy group effects")
	t.check(sim.cmd_party_invite(41, 42).get("ok", false), "cook invites scout")
	t.check(sim.cmd_party_accept(42).get("ok", false), "scout accepts membership")
	t.check(sim.cmd_party_invite(41, 43).get("ok", false), "leader invites ranger")
	t.check(sim.cmd_party_accept(43).get("ok", false), "ranger joins expedition")
	t.eq(sim.cmd_party_feast(41, "raw_fish").get("reason", ""), "not_prepared_food",
		"uncooked fish does not qualify as a meal")
	t.eq(sim.cmd_party_feast(41, "canned_food").get("reason", ""), "not_prepared_food",
		"canned food stays a personal survival item")
	t.eq(sim.cmd_party_feast(41, "cooked_fish").get("reason", ""), "no_fire",
		"parties cannot share a meal without a real active campfire")
	# Nearby members of the same party may sit together; a remote third
	# member and an ungrouped spectator must not receive any benefit.
	var built: Dictionary = sim.cmd_light_campfire(41, site.x, site.y)
	t.check(built.get("ok", false), "the player actually builds a fueled campfire")
	if not built.get("ok", false):
		return
	distant.position = _at(world, origin + Vector2(-14.0, 0))
	t.check(FieldCampfire.has_warmth(sim.campfires, cook.position, sim.time),
		"the new fire is warming the cook")
	t.check(FieldCampfire.has_warmth(sim.campfires, ally.position, sim.time),
		"the same fire is warming scout")
	var lacking: Dictionary = sim.cmd_party_feast(41, "cooked_fish")
	t.eq(lacking.get("reason", ""), "need_food",
		"two guests require two owned cooked-fish portions")
	t.eq(int(lacking.get("portions", 0)), 2, "required portions come from real roster")
	t.eq(cook.inventory.count("cooked_fish"), 1,
		"failed feast cannot destroy the single owned portion")
	t.near(cook.feast_timer, 0.0, 0.001,
		"insufficient food never starts feast cooldown")

	t.current = "successful camp feast is paid exactly once and never feeds strangers"
	cook.inventory.add("cooked_fish", 3)
	cook.survival.hunger = 15.0
	ally.survival.hunger = 15.0
	distant.survival.hunger = 15.0
	outsider.survival.hunger = 15.0
	var first: Dictionary = sim.cmd_party_feast(41, "cooked_fish")
	t.check(first.get("ok", false), "funded feast serves valid online camp companions")
	t.eq(int(first.get("served", 0)), 2,
		"only cook and nearby accepted scout are served")
	t.eq(cook.inventory.count("cooked_fish"), 2,
		"two portions are removed, never one and never three")
	t.eq(cook.meal_tier, 1, "cook gets server-owned T1 meal effect")
	t.eq(ally.meal_tier, 1, "nearby ally gets the same effect")
	t.near(ally.meal_seconds, HeartyMeal.duration(1), 0.001,
		"scout receives full legitimate meal duration")
	t.eq(distant.meal_tier, 0, "faraway ranger receives no teleport-fed buff")
	t.eq(outsider.meal_tier, 0, "spectator outside party receives no meal")
	t.check(cook.survival.hunger > 15.0 and ally.survival.hunger > 15.0,
		"each served teammate gets the actual cooked food nutrition")
	t.near(distant.survival.hunger, 15.0, 0.001,
		"out-of-range players do not receive free hunger restoration")
	t.near(cook.feast_timer, PartyFeast.COOLDOWN, 0.001,
		"successful feast starts the server cooldown")
	t.eq(sim.cmd_party_feast(41, "cooked_fish").get("reason", ""), "cooldown",
		"replayed network command cannot duplicate shared provisions")
	t.eq(cook.inventory.count("cooked_fish"), 2,
		"cooldown rejections consume no additional portions")
	sim._tick_players(1.0)
	t.check(cook.feast_timer < PartyFeast.COOLDOWN and cook.feast_timer > 0.0,
		"cooldown decreases only during authoritative simulation ticks")
	t.check(cook.dirty_inventory and cook.dirty_character and ally.dirty_character,
		"sender inventory and both character buffs are marked for saving")
	t.eq(sim.snapshot_for(41)["you"]["party_feast_cooldown"] > 0.0, true,
		"multiplayer owner sees remaining feast cooldown")
	var saved: Dictionary = sim.character_data(ally)
	ally.meal_seconds = 0.0
	ally.meal_tier = 0
	t.check(sim.apply_character(ally, saved), "teammate meal effect survives logout")
	t.eq(ally.meal_tier, 1, "served effect persists across character restoration")

	t.current = "party feast message reaches only the recipient"
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	var expected_messages := 0
	for event in sim.events:
		if event.get("type") == "party_feast":
			expected_messages += 1
			t.check(net._event_visible_to(event, int(event["peer"])),
				"meal notice is delivered to its specific recipient")
			t.check(not net._event_visible_to(event, 44),
				"unrelated spectators cannot read private meal events")
	t.eq(expected_messages, 2, "only two private meal notifications are created")
	net.free()

	t.current = "out-of-range and higher-tier buffs protect other players"
	cook.feast_timer = 0.0
	ally.position = _at(world, origin + Vector2(-12.0, 0.0))
	var food_before: int = cook.inventory.count("cooked_fish")
	t.eq(sim.cmd_party_feast(41, "cooked_fish").get("reason", ""), "no_companions",
		"solo survivor at the fire cannot eat absent teammates' portions")
	t.eq(cook.inventory.count("cooked_fish"), food_before,
		"an empty roster cannot charge any provisions")
	ally.position = _at(world, origin + Vector2(0, 1.0))
	ally.meal_tier = 4
	ally.meal_seconds = HeartyMeal.duration(4)
	t.eq(sim.cmd_party_feast(41, "cooked_fish").get("reason", ""), "no_companions",
		"weak T1 food must never replace ally's stronger T4 preparation")
	t.eq(ally.meal_tier, 4, "stronger active survivor buff remains intact")
	t.eq(cook.inventory.count("cooked_fish"), food_before,
		"rejected downgrade does not use cook's rations")
	ally.meal_tier = 0
	ally.meal_seconds = 0.0
	t.check(sim.cmd_party_leave(42).get("ok", false),
		"ally can withdraw consent by leaving the party")
	t.eq(sim.cmd_party_feast(41, "cooked_fish").get("reason", ""), "no_companions",
		"former member no longer receives any portion")
	t.eq(cook.inventory.count("cooked_fish"), food_before,
		"leaving the party does not consume items")

	t.current = "dead characters and expired fires cannot be fed"
	# Rejoin the accepted party while still physically close.
	t.check(sim.cmd_party_invite(41, 42).get("ok", false), "re-invite teammate")
	t.check(sim.cmd_party_accept(42).get("ok", false), "teammate rejoins")
	ally.survival.hurt(1000.0)
	t.eq(sim.cmd_party_feast(41, "cooked_fish").get("reason", ""), "no_companions",
		"dead teammates are excluded from the active dining roster")
	ally.survival.reset()
	sim.time = FieldCampfire.DURATION + 2.0
	t.eq(sim.cmd_party_feast(41, "cooked_fish").get("reason", ""), "no_fire",
		"expired campfire cannot be used to bypass world resource costs")
	t.eq(cook.inventory.count("cooked_fish"), food_before,
		"stale fires consume no food")
