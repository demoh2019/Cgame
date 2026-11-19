extends RefCounted
## Classic MMO party combat: confirmed assists, friendly fire and anti-farming.
## All operations exercise the actual authoritative GameServer, not client data.

const Party = preload("res://scripts/shared/party.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _zombie(server, world, x: float, z: float, hp: float = 170.0):
	var entity := Zombie.new(server.new_id(), "brute",
		Vector3(x, world.height_at(x, z), z))
	entity.health = hp
	server.zombies[entity.id] = entity
	return entity


func run(t) -> void:
	t.current = "server party assist rules reject invalid XP and locations"
	t.eq(Party.assist_xp(0), 0, "zero base XP does not grant assist XP")
	t.eq(Party.assist_xp(-100), 0, "negative XP cannot grant assist XP")
	t.eq(Party.assist_xp(25), 12, "a brute kill is worth twelve assist XP")
	t.eq(Party.assist_xp(100000), 100, "assist XP cannot exceed hard cap")
	t.check(Party.in_assist_range(Vector3.ZERO, Vector3(Party.ASSIST_RANGE, 0, 0)),
		"assist range includes the boundary")
	t.check(not Party.in_assist_range(Vector3.ZERO,
		Vector3(Party.ASSIST_RANGE + 0.1, 0, 0)), "distant members do not qualify")
	t.check(not Party.in_assist_range(Vector3(NAN, 0, 0), Vector3.ZERO),
		"nonfinite locations cannot grant assist XP")

	t.current = "party membership requires explicit, nearby accepted invitations"
	var world := WorldGen.new(410)
	var server := GameServer.new(world, 410)
	var attacker = server.add_player(11, "Vanguard")
	var ally = server.add_player(12, "Medic")
	var bystander = server.add_player(13, "Scout")
	var outsider = server.add_player(14, "Raider")
	var base_x := 700.0
	var base_z := 200.0
	attacker.position = Vector3(base_x, world.height_at(base_x, base_z), base_z)
	ally.position = Vector3(base_x + 4.0, world.height_at(base_x + 4.0, base_z), base_z)
	bystander.position = Vector3(base_x + 10.0, world.height_at(base_x + 10.0, base_z), base_z)
	outsider.position = Vector3(base_x + 45.0, world.height_at(base_x + 45.0, base_z), base_z)
	t.check(world.zone_at(base_x, base_z) >= 2, "party combat test occurs in PvP territory")
	t.eq(server.cmd_party_invite(11, 14).get("reason", ""), "too_far",
		"distant strangers cannot be invited")
	t.check(server.cmd_party_invite(11, 12).get("ok", false), "leader sends an invitation")
	t.eq(server.parties.group_of(12), 0, "invite does not force another player into party")
	t.check(server.cmd_party_accept(12).get("ok", false), "recipient consents to party")
	t.check(server.cmd_party_invite(11, 13).get("ok", false), "leader may invite a second ally")
	t.check(server.cmd_party_accept(13).get("ok", false), "second ally joins")
	t.eq(server.parties.members_of(11).size(), 3, "party is tracked by the authoritative server")
	t.eq(server.parties.group_of(14), 0, "uninvited outsider remains unaffiliated")

	attacker.inventory.add("club_1", 1)
	ally.inventory.add("club_1", 1)
	bystander.inventory.add("club_1", 1)
	outsider.inventory.add("club_1", 1)
	t.check(attacker.inventory.equip("club_1"), "attacker owns equipped melee weapon")
	t.check(ally.inventory.equip("club_1"), "ally owns equipped melee weapon")
	t.check(bystander.inventory.equip("club_1"), "third member owns equipped melee weapon")
	t.check(outsider.inventory.equip("club_1"), "unrelated player owns melee weapon")

	t.current = "party assists require a real hit before confirmed zombie death"
	var brute = _zombie(server, world, base_x + 2.5, base_z, 170.0)
	var assist_hit: Dictionary = server.cmd_attack(12, -1.0, 0.0)
	t.check(assist_hit.get("ok", false) and assist_hit.get("hit", false),
		"ally damages a real infected before the kill")
	t.eq(ally.progression.combat_xp["melee"], 0, "a normal hit alone grants no XP")
	# The killer finishes the same wounded infected, from its other side.
	brute.health = 8.0
	var finish: Dictionary = server.cmd_attack(11, 1.0, 0.0)
	t.check(finish.get("ok", false) and finish.get("hit", false),
		"leader defeats the infected in actual melee combat")
	t.eq(attacker.progression.combat_xp["melee"], 25,
		"killer earns normal brute weapon mastery")
	t.eq(ally.progression.combat_xp["melee"], 12,
		"contributing ally earns bounded mastery assist")
	t.eq(bystander.progression.combat_xp["melee"], 0,
		"nearby party member without combat contribution gets no XP")
	t.eq(outsider.progression.combat_xp["melee"], 0,
		"non-party players cannot leech party XP")
	var before: int = int(ally.progression.combat_xp["melee"])
	server._damage_target(attacker, {"kind": "zombie", "id": brute.id}, 500.0)
	t.eq(ally.progression.combat_xp["melee"], before,
		"re-killing a corpse cannot duplicate assist XP")
	var saw_assist := false
	for event in server.events:
		if event.get("type") == "mastery" and event.get("peer") == 12 and event.get("assist", false):
			saw_assist = true
	t.check(saw_assist, "server generates a personal assist XP event")

	t.current = "expired hits and removed membership do not grant group experience"
	var late = _zombie(server, world, base_x + 2.5, base_z, 100.0)
	server._damage_target(ally, {"kind": "zombie", "id": late.id}, 1.0)
	server.time += Party.ASSIST_WINDOW + 1.0
	server._damage_target(attacker, {"kind": "zombie", "id": late.id}, 500.0)
	t.eq(ally.progression.combat_xp["melee"], before,
		"hits older than the contribution window are not eligible")
	var orphan = _zombie(server, world, base_x + 2.5, base_z, 100.0)
	server._damage_target(ally, {"kind": "zombie", "id": orphan.id}, 1.0)
	t.check(server.cmd_party_leave(12).get("ok", false), "member voluntarily leaves")
	server._damage_target(attacker, {"kind": "zombie", "id": orphan.id}, 500.0)
	t.eq(ally.progression.combat_xp["melee"], before,
		"former groupmates cannot collect party experience")

	t.current = "party members are never selected or damaged as PvP targets"
	# Rejoin the group for the rest of the combat regression.
	t.check(server.cmd_party_invite(11, 12).get("ok", false), "leader re-invites ally")
	t.check(server.cmd_party_accept(12).get("ok", false), "ally joins again")
	var ally_health: float = ally.survival.health
	ally.position = Vector3(base_x + 1.0,
		world.height_at(base_x + 1.0, base_z), base_z)
	var target = _zombie(server, world, base_x + 2.0, base_z, 170.0)
	attacker.attack_timer = 0.0
	var real_hit: Dictionary = server.cmd_attack(11, 1.0, 0.0)
	t.check(real_hit.get("ok", false) and real_hit.get("hit", false),
		"melee hits infected behind a friendly party member")
	t.eq(real_hit.get("target", ""), "zombie", "ally does not intercept zombie targeting")
	t.near(ally.survival.health, ally_health, 0.001,
		"party members take no friendly melee damage")
	server._damage_target(attacker, {"kind": "player", "id": 12}, 500.0)
	t.near(ally.survival.health, ally_health, 0.001,
		"even direct server combat calls enforce friendly-fire protection")

	t.current = "disconnect immediately cancels session-only party membership"
	server.remove_player(12)
	t.eq(server.parties.group_of(12), 0, "disconnected ally is no longer in a party")
	t.eq(server.parties.members_of(11).size(), 2,
		"remaining party retains its real online members")
	var state: Dictionary = server.snapshot_for(11)["you"]["party"]
	t.eq(state["members"].size(), 2, "snapshot exposes the current server roster")
	t.check(target.is_alive(), "group combat did not corrupt nearby zombie state")
