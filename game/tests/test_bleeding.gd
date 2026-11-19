extends RefCounted
## Real, server-owned wounds, first-aid transactions and persistence regression.

const Defs = preload("res://scripts/shared/defs.gd")
const Survival = preload("res://scripts/shared/survival.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func run(t) -> void:
	t.current = "bleeding severity and natural clotting"
	var life := Survival.new()
	t.near(life.bleeding, 0.0, 0.0001, "new survivor has no wound")
	t.check(not life.add_bleeding(-10.0), "negative wound is rejected")
	t.check(not life.add_bleeding(INF), "infinite wound is rejected")
	t.check(not life.add_bleeding(NAN), "NaN wound is rejected")
	t.check(life.add_bleeding(50.0), "real wound is applied")
	life.health = 65.0
	var hp_before: float = life.health
	var taken: float = life.tick(5.0)
	t.check(taken > 0.0 and life.health < hp_before, "bleeding drains health")
	t.check(life.bleeding < 50.0, "wound gradually clots")
	t.check(life.stop_bleeding(), "treatment stops bleeding")
	t.near(life.bleeding, 0.0, 0.0001, "treated bleeding clears")
	t.check(not life.stop_bleeding(), "cannot stop a healed wound again")
	t.check(life.add_bleeding(200.0), "large wound is accepted but bounded")
	t.near(life.bleeding, Defs.BLEEDING_MAX, 0.0001, "wound severity capped")
	life.reset()
	t.near(life.bleeding, 0.0, 0.0001, "respawn clears bleeding")
	life.hurt(500.0)
	t.check(not life.add_bleeding(10.0), "dead survivors cannot bleed anew")

	t.current = "bandage treats wounds without wasting healthy supplies"
	var world := WorldGen.new(412)
	var server := GameServer.new(world, 19)
	var patient = server.add_player(731, "Medic")
	var initial_bandages: int = patient.inventory.count("bandage")
	patient.survival.add_bleeding(30.0)
	t.check(server.cmd_use(731, "bandage").get("ok", false), "bandage works at full health")
	t.near(patient.survival.bleeding, 0.0, 0.0001, "bandage staunches the wound")
	t.eq(patient.inventory.count("bandage"), initial_bandages - 1, "one bandage consumed")
	t.eq(server.cmd_use(731, "bandage").get("reason", ""), "no_effect", "cannot waste a bandage")
	t.eq(patient.inventory.count("bandage"), initial_bandages - 1, "rejected use costs nothing")
	patient.inventory.add("field_antiseptic", 1)
	patient.survival.add_bleeding(18.0)
	t.check(server.cmd_use(731, "field_antiseptic").get("ok", false), "antiseptic also staunches wounds")
	t.near(patient.survival.bleeding, 0.0, 0.0001, "antiseptic clears bleeding")

	t.current = "infected melee strikes cause a server-owned wound"
	patient.position = Vector3(200.0, world.height_at(200.0, 200.0), 200.0)
	var infected := Zombie.new(server.new_id(), "walker",
		Vector3(201.1, patient.position.y, 200.0))
	infected.target_id = patient.id
	infected.state = Zombie.State.ATTACK
	server.zombies[infected.id] = infected
	server._tick_zombies(0.1)
	t.near(patient.survival.bleeding, Defs.ZOMBIE_BLEEDING_PER_HIT["walker"], 0.0001,
		"actual zombie strike applies its configured bleeding")
	var wound_event := false
	for event in server.events:
		if event.get("type") == "bleeding" and event.get("peer") == patient.id:
			wound_event = true
	t.check(wound_event, "clients receive a wound notification")

	t.current = "PvP wounds only after legitimate damaging melee hits"
	var aggressor = server.add_player(732, "Bandit")
	aggressor.inventory.add("club_1", 1)
	aggressor.inventory.equip("club_1")
	patient.survival.stop_bleeding()
	patient.position = Vector3(700.0, world.height_at(700.0, 0.0), 0.0)
	aggressor.position = Vector3(701.0, world.height_at(701.0, 0.0), 0.0)
	server._damage_target(aggressor, {"kind": "player", "id": patient.id}, 14.0)
	t.near(patient.survival.bleeding, Defs.PVP_MELEE_BLEEDING_PER_HIT, 0.0001,
		"red-zone melee hit applies a wound")
	patient.survival.stop_bleeding()
	patient.position = Vector3(20.0, world.height_at(20.0, 0.0), 0.0)
	aggressor.position = Vector3(21.0, world.height_at(21.0, 0.0), 0.0)
	server._damage_target(aggressor, {"kind": "player", "id": patient.id}, 14.0)
	t.near(patient.survival.bleeding, 0.0, 0.0001, "safe-hub PvP causes no wounds")

	t.current = "persistent bleeding and atomic corrupt-save refusal"
	patient.survival.add_bleeding(27.0)
	var saved: Dictionary = server.character_data(patient)
	t.near(float(saved["bleeding"]), 27.0, 0.0001, "saved character includes bleeding")
	patient.survival.stop_bleeding()
	t.check(server.apply_character(patient, saved), "server restores wound")
	t.near(patient.survival.bleeding, 27.0, 0.0001, "bleeding persists across logins")
	for invalid in [-1.0, 110.0, INF, NAN, "27", true]:
		var corrupt: Dictionary = saved.duplicate(true)
		corrupt["bleeding"] = invalid
		t.check(not server.apply_character(patient, corrupt), "corrupt saved wounds rejected")
		t.near(patient.survival.bleeding, 27.0, 0.0001, "failed restore keeps live wound")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("bleeding")
	t.check(server.apply_character(patient, legacy), "old saves remain compatible")
	t.near(patient.survival.bleeding, 0.0, 0.0001, "legacy save starts without wounds")
