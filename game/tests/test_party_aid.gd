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
	t.eq(server.cmd_party_aid(11, 12, "canned_food").get("reason", ""), "not_medical", "food cannot be forged into healing")
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

	t.current = "server permits field antiseptic and antibiotics for another player"
	target.survival.add_infection(60.0)
	medic.inventory.add("field_antiseptic", 1)
	t.check(server.cmd_party_aid(11, 12, "field_antiseptic").get("ok", false),
		"field antiseptic treats an infected teammate")
	t.near(target.survival.infection, 20.0, 0.001, "field antiseptic removes 40 infection")
	t.eq(medic.inventory.count("field_antiseptic"), 0, "one field antiseptic used")
	medic.party_aid_timer = 0.0
	medic.inventory.add("antibiotics", 1)
	t.check(server.cmd_party_aid(11, 12, "antibiotics").get("ok", false), "antibiotics may cure allied infection")
	t.near(target.survival.infection, 0.0, 0.001, "antibiotics cure remaining infection")
	t.eq(medic.inventory.count("antibiotics"), 0, "one antibiotic dose used")

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
