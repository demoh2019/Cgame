extends RefCounted
## Regression for server-owned fractures, field splints and migration.

const Defs = preload("res://scripts/shared/defs.gd")
const Survival = preload("res://scripts/shared/survival.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const PartyAid = preload("res://scripts/shared/party_aid.gd")


func run(t) -> void:
	t.current = "fracture severity and gradual healing"
	var life := Survival.new()
	t.near(life.fracture, 0.0, 0.001, "new survivor starts with no fracture")
	t.check(not life.add_fracture(-5.0), "reject negative severity")
	t.check(not life.add_fracture(NAN), "reject NaN")
	t.check(not life.add_fracture(INF), "reject infinity")
	t.check(life.add_fracture(35.0), "blunt strike fractures limb")
	t.check(not life.try_sprint(0.05), "broken limb prevents sprint")
	t.near(life.stamina, Defs.MAX_STAMINA, 0.001, "blocked sprint costs no stamina")
	life.tick(10.0)
	t.check(life.fracture < 35.0, "untreated fracture gradually heals")
	t.check(life.treat_fracture(100.0), "splint heals fracture")
	t.near(life.fracture, 0.0, 0.001, "splint clears severity")
	t.check(not life.treat_fracture(10.0), "healthy limb cannot be treated")
	life.add_fracture(999.0)
	t.near(life.fracture, Defs.FRACTURE_MAX, 0.001, "fracture capped at 100")
	life.reset()
	t.near(life.fracture, 0.0, 0.001, "respawn clears fracture")
	life.hurt(1000.0)
	t.check(not life.add_fracture(10.0), "dead cannot acquire new injury")

	t.current = "shared server/client movement"
	var world := WorldGen.new(836)
	var origin := Vector3(100.0, world.height_at(100.0, 100.0), 100.0)
	var normal := Movement.step(world, origin, {"x": 1.0, "z": 0.0}, 0.1)
	var injured := Movement.step(world, origin, {
		"x": 1.0, "z": 0.0, "injury_factor": Survival.fracture_speed_factor(35.0)}, 0.1)
	t.check(injured.distance_to(origin) <= normal.distance_to(origin) + 0.0001,
		"injury cannot increase movement speed")
	var forced_sprint := Movement.step(world, origin, {
		"x": 1.0, "z": 0.0, "sprint": true,
		"injury_factor": Defs.FRACTURE_SPEED_FACTOR}, 0.1)
	t.near(forced_sprint.distance_to(origin), injured.distance_to(origin), 0.001,
		"shared movement disallows sprint while injured")

	t.current = "damaging brute strike, not client input, causes fracture"
	var server := GameServer.new(world, 836)
	var patient = server.add_player(210, "Patient")
	patient.position = Vector3(200.0, world.height_at(200.0, 200.0), 200.0)
	var brute := Zombie.new(server.new_id(), "brute",
		Vector3(201.1, patient.position.y, 200.0))
	brute.target_id = patient.id
	brute.state = Zombie.State.ATTACK
	server.zombies[brute.id] = brute
	server._tick_zombies(0.1)
	t.near(patient.survival.fracture, 35.0, 0.001, "brute inflicts fracture")
	var saw_event := false
	for event in server.events:
		if event.get("type") == "fracture" and event.get("peer") == patient.id:
			saw_event = true
	t.check(saw_event, "server broadcasts injury event")
	t.near(float(server.snapshot_for(patient.id)["you"]["fracture"]), 35.0, 0.001,
		"snapshot includes fracture")

	t.current = "field crafting, paid self-care and no wasted medicine"
	t.check(Defs.is_item("field_splint"), "field splint is a real item")
	t.check(Defs.recipes().has("field_splint"), "field splint has a recipe")
	patient.inventory.add("plank_1", 1)
	patient.inventory.add("fiber_1", 2)
	patient.inventory.add("cloth_1", 1)
	t.check(bool(server.cmd_craft(patient.id, "field_splint").get("ok", false)),
		"field splint can be crafted without a station")
	t.eq(patient.inventory.count("field_splint"), 1, "splint added")
	t.check(server.cmd_use(patient.id, "field_splint").get("ok", false), "splint treats limb")
	t.near(patient.survival.fracture, 0.0, 0.001, "fracture cured")
	t.eq(patient.inventory.count("field_splint"), 0, "one splint consumed")
	patient.inventory.add("field_splint", 1)
	t.eq(server.cmd_use(patient.id, "field_splint").get("reason", ""), "no_effect",
		"healthy players cannot waste splints")
	t.eq(patient.inventory.count("field_splint"), 1, "failed treatment does not spend splint")

	t.current = "consenting party medics have real supply costs"
	var medic = server.add_player(211, "FieldMedic")
	patient.position = Vector3(8.0, world.height_at(8.0, 9.0), 9.0)
	medic.position = Vector3(9.0, world.height_at(9.0, 9.0), 9.0)
	patient.survival.add_fracture(50.0)
	medic.inventory.add("field_splint", 1)
	t.check(PartyAid.has_effect(Defs.item("field_splint"), 100.0, 0.0, 0.0, 50.0),
		"splint treats broken limbs, not just HP")
	t.eq(server.cmd_party_aid(medic.id, patient.id, "field_splint").get("reason", ""),
		"not_in_party", "strangers cannot apply medicine")
	t.check(bool(server.cmd_party_invite(medic.id, patient.id).get("ok", false)),
		"medic invites patient")
	t.check(bool(server.cmd_party_accept(patient.id).get("ok", false)),
		"patient consents to party")
	t.check(bool(server.cmd_party_aid(medic.id, patient.id, "field_splint").get("ok", false)),
		"nearby party medics may treat fracture")
	t.near(patient.survival.fracture, 0.0, 0.001, "party splint cures injury")
	t.eq(medic.inventory.count("field_splint"), 0, "one carried splint debited")

	t.current = "persistent saves validate and migrate fracture data"
	patient.survival.add_fracture(27.0)
	var saved: Dictionary = server.character_data(patient)
	t.check(server.valid_character_data(saved), "fracture is valid persisted state")
	patient.survival.treat_fracture(100.0)
	t.check(server.apply_character(patient, saved), "saved survivor restores")
	t.near(patient.survival.fracture, 27.0, 0.001, "saved fracture restored")
	for invalid in [-1.0, 101.0, INF, NAN, "27", true]:
		var corrupt: Dictionary = saved.duplicate(true)
		corrupt["fracture"] = invalid
		t.check(not server.apply_character(patient, corrupt), "invalid stored injury rejected")
		t.near(patient.survival.fracture, 27.0, 0.001, "corrupt save preserves state")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("fracture")
	t.check(server.apply_character(patient, legacy), "old v1 saves load")
	t.near(patient.survival.fracture, 0.0, 0.001, "old saves default to healthy limbs")
