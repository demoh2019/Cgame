extends RefCounted
## Game-side, server-authoritative infection and field medicine regression.

const Defs = preload("res://scripts/shared/defs.gd")
const Survival = preload("res://scripts/shared/survival.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Combat = preload("res://scripts/shared/combat.gd")


func run(t) -> void:
	t.current = "infection severity, progression, and treatment"
	var life := Survival.new()
	t.near(life.infection, 0.0, 0.001, "new characters start without infection")
	t.check(not life.add_infection(-10.0), "negative exposure is rejected")
	t.check(not life.add_infection(INF), "nonfinite exposure is rejected")
	t.check(life.add_infection(40.0), "a zombie wound can transmit infection")
	var hp_before: float = life.health
	life.tick(10.0)
	t.check(life.infection > 40.0, "untreated infection progresses while alive")
	t.check(life.health < hp_before, "advanced infection causes health damage")
	t.check(life.treat_infection(25.0), "field treatment reduces infection")
	t.check(life.infection < 40.0, "treatment decreases severity")
	t.check(life.treat_infection(500.0), "antibiotics can eliminate severe infection")
	t.near(life.infection, 0.0, 0.001, "infection severity clamps to zero")
	t.check(not life.treat_infection(10.0), "no medicine effect at zero infection")
	life.add_infection(150.0)
	t.near(life.infection, Defs.INFECTION_MAX, 0.001, "infection severity has a cap")
	life.reset()
	t.near(life.infection, 0.0, 0.001, "respawn clears infection")
	life.hurt(1000.0)
	t.check(not life.add_infection(25.0), "the dead cannot be infected")

	t.current = "zombie hits are the authoritative infection source"
	var world := WorldGen.new(318)
	var server := GameServer.new(world, 77)
	var survivor = server.add_player(210, "FieldMedic")
	survivor.position = Vector3(200.0, world.height_at(200.0, 200.0), 200.0)
	var walker := Zombie.new(server.new_id(), "walker",
		Vector3(201.1, survivor.position.y, 200.0))
	walker.target_id = 210
	walker.state = Zombie.State.ATTACK
	server.zombies[walker.id] = walker
	var base_health: float = survivor.survival.health
	server._tick_zombies(0.1)
	t.check(survivor.survival.health < base_health, "zombie strike deals real damage")
	t.near(survivor.survival.infection, float(Defs.ZOMBIE_INFECTION_PER_HIT["walker"]),
		0.001, "server applies infection from the actual infected attacker")
	var saw_infection_event := false
	for event in server.events:
		if event.get("type") == "infection" and event.get("peer") == 210:
			saw_infection_event = true
	t.check(saw_infection_event, "server emits an infection event")

	t.current = "treatment cannot waste rare medicine on a healthy survivor"
	survivor.inventory.add("antibiotics", 1)
	survivor.survival.add_infection(70.0)
	t.check(server.cmd_use(210, "antibiotics").get("ok", false), "antibiotics cure an infected player")
	t.near(survivor.survival.infection, 0.0, 0.001, "antibiotics clear infection")
	t.eq(survivor.inventory.count("antibiotics"), 0, "using medicine consumes one dose")
	survivor.inventory.add("antibiotics", 1)
	t.eq(server.cmd_use(210, "antibiotics").get("reason", ""), "no_effect",
		"antibiotics cannot be wasted without infection")
	t.eq(survivor.inventory.count("antibiotics"), 1, "rejected use does not consume the item")

	t.current = "field antiseptic crafting, curing, and inventory transactions"
	survivor.survival.add_infection(65.0)
	survivor.inventory.add("bandage", 1)
	survivor.inventory.add("water_bottle", 1)
	survivor.inventory.add("cloth_1", 1)
	var old_cloth: int = survivor.inventory.count("cloth_1")
	t.check(server.cmd_craft(210, "field_antiseptic").get("ok", false),
		"field antiseptic can be crafted from existing survival materials")
	t.eq(survivor.inventory.count("cloth_1"), old_cloth - 1, "craft spends cloth")
	t.eq(survivor.inventory.count("field_antiseptic"), 1, "craft rewards an antiseptic kit")
	t.check(server.cmd_use(210, "field_antiseptic").get("ok", false),
		"antiseptic kit cleans the zombie wound")
	t.near(survivor.survival.infection, 25.0, 0.001, "field antiseptic reduces infection by 40")
	t.eq(survivor.inventory.count("field_antiseptic"), 0, "field kit is single-use")

	t.current = "persistent infection and atomic corrupt-save rejection"
	var saved: Dictionary = server.character_data(survivor)
	t.near(float(saved["infection"]), 25.0, 0.001, "character save includes infection")
	survivor.survival.treat_infection(100.0)
	t.check(server.apply_character(survivor, saved), "saved infection restores")
	t.near(survivor.survival.infection, 25.0, 0.001, "infection survives logout")
	for invalid_value in [-1.0, 1000.0, INF, NAN, "25", true]:
		var corrupt: Dictionary = saved.duplicate(true)
		corrupt["infection"] = invalid_value
		t.check(not server.apply_character(survivor, corrupt),
			"invalid stored infection is rejected without partial mutation")
		t.near(survivor.survival.infection, 25.0, 0.001, "bad save leaves infection unchanged")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("infection")
	t.check(server.apply_character(survivor, legacy), "existing v1 characters remain loadable")
	t.near(survivor.survival.infection, 0.0, 0.001, "v1 absent field defaults to healthy")

	t.current = "infected zone carries valuable medical loot"
	t.check(Defs.is_item("antibiotics"), "antibiotics have an item definition")
	t.check(Defs.recipes().has("field_antiseptic"), "field kit is a crafting recipe")
	var rng := RandomNumberGenerator.new()
	rng.seed = 284
	var found := false
	for i in 160:
		var drop: Dictionary = Combat.crate_loot(3, rng)
		if drop.has("antibiotics"):
			found = true
			t.eq(int(drop["antibiotics"]), 1, "rare medicines drop as one bounded dose")
	t.check(found, "high-risk scavenging can discover antibiotics")
