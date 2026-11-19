extends RefCounted
## Server-authoritative infection lifecycle regression.
const Defs = preload("res://scripts/shared/defs.gd")
const Survival = preload("res://scripts/shared/survival.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func run(t) -> void:
	t.current = "infection thresholds and treatment"
	var s := Survival.new()
	t.check(not s.expose_to_infection(-1.0), "negative exposure rejected")
	t.check(not s.expose_to_infection(INF), "infinite exposure rejected")
	t.check(s.expose_to_infection(75.0), "valid exposure accepted")
	t.near(s.infection, 75.0, 0.0001, "correct infection dose")
	t.check(s.expose_to_infection(50.0), "additional exposure accepted")
	t.near(s.infection, 100.0, 0.0001, "infection is capped")
	s.health = 90.0
	var damage := s.tick(1.0)
	t.check(damage > 1.0, "symptomatic infection harms survivor")
	t.check(s.health < 90.0, "infection reduces health")
	t.check(not s.tick(-1.0) > 0.0, "invalid negative delta rejected")
	t.check(s.treat_infection(55.0), "medicine works")
	t.check(s.infection < Defs.INFECTION_DAMAGE_THRESHOLD, "medicine suppresses symptoms")
	t.check(not s.treat_infection(NAN), "NaN treatment rejected")
	t.check(s.treat_infection(500.0), "treatment is capped at zero")
	t.near(s.infection, 0.0, 0.0001, "infection never becomes negative")
	t.check(not s.treat_infection(55.0), "no medicine needed at zero infection")
	t.eq(s.to_dict()["infection"], 0.0, "infection serialized into vitals")

	t.current = "server medicine and persistence"
	var world := WorldGen.new(44)
	var server := GameServer.new(world, 15)
	var p = server.add_player(88, "Medic")
	p.survival.expose_to_infection(80.0)
	t.check(server.character_data(p).has("infection"), "infected character snapshot")
	var old_save: Dictionary = server.character_data(p)
	old_save.erase("infection")
	t.check(server.apply_character(p, old_save), "old version-1 saves still load")
	t.near(p.survival.infection, 0.0, 0.0001, "old save resets infection")
	var bad_save: Dictionary = server.character_data(p)
	bad_save["infection"] = -25.0
	var before_health := p.survival.health
	t.check(not server.apply_character(p, bad_save), "negative infection save rejected")
	t.near(p.survival.health, before_health, 0.0001, "bad save does not mutate health")
	bad_save["infection"] = INF
	t.check(not server.apply_character(p, bad_save), "infinite infection save rejected")

	p.inventory.add("water_bottle", 1)
	p.inventory.add("cloth_1", 1)
	t.check(server.cmd_craft(88, "antiseptic")["ok"], "craft medicine from cloth and water")
	t.eq(p.inventory.count("antiseptic"), 1, "craft creates exactly one antiseptic")
	t.eq(server.cmd_use(88, "antiseptic")["reason"], "not_needed", "medicine cannot be wasted at zero infection")
	t.eq(p.inventory.count("antiseptic"), 1, "rejected use does not consume medicine")
	p.survival.expose_to_infection(80.0)
	t.check(server.cmd_use(88, "antiseptic")["ok"], "server applies medicine")
	t.near(p.survival.infection, 25.0, 0.0001, "medicine removes 55 points")
	t.eq(p.inventory.count("antiseptic"), 0, "medicine consumed once")
	t.check(p.dirty_character, "medicine marks character for persistence")
	t.near(server.snapshot_for(88)["you"]["infection"], 25.0, 0.0001, "infection replicates to the HUD")
	var current_save: Dictionary = server.character_data(p)
	var after_login = server.add_player(89, "Return", "", current_save)
	t.near(after_login.survival.infection, 25.0, 0.0001, "infection restored across sessions")

	t.current = "infected attack is authoritative"
	p.position = Vector3(300.0, world.height_at(300.0, 300.0), 300.0)
	var zombie := Zombie.new(server.new_id(), "walker",
		Vector3(301.0, world.height_at(301.0, 300.0), 300.0))
	server.zombies[zombie.id] = zombie
	var starting_infection := p.survival.infection
	server._tick_zombies(0.05)
	t.check(p.survival.infection > starting_infection, "zombie strike applies server-side infection")
	t.check(p.survival.infection <= 100.0, "server-side infection stays bounded")
