extends RefCounted
## Boss loot is ONE bag, protected from outsider ninja-looting for a short
## interval. Only real combat participants of the killing group have first pick.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const RaidEncounter = preload("res://scripts/shared/raid_encounter.gd")
const RaidLoot = preload("res://scripts/shared/raid_loot.gd")


func _position(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func _boss(server, world, x: float, z: float):
	var enemy := Zombie.new(server.new_id(), "brute", _position(world, x, z), -1)
	RaidEncounter.empower(enemy)
	server.zombies[enemy.id] = enemy
	return enemy


func run(t) -> void:
	t.current = "raid combat and exclusive first pickup"
	var world := WorldGen.new(47)
	var server := GameServer.new(world, 47)
	var killer = server.add_player(101, "Warrior", "account-warrior")
	var helper = server.add_player(102, "Archer", "account-archer")
	var outsider = server.add_player(103, "Ninja", "account-ninja")
	var idle = server.add_player(104, "Idle", "account-idle")
	for survivor in [killer, helper, outsider, idle]:
		survivor.position = _position(world, 901.0, 900.0)
		survivor.inventory.add("club_1", 1)
		survivor.inventory.equip("club_1")
	t.check(server.parties.invite(101, 102, server.time).get("ok", false), "leader invites helper")
	t.check(server.parties.accept(102, server.time).get("ok", false), "helper joins group")
	t.check(server.parties.invite(101, 104, server.time).get("ok", false), "idle player invited")
	t.check(server.parties.accept(104, server.time).get("ok", false), "idle player joins group")
	var boss = _boss(server, world, 902.0, 900.0)
	server._damage_target(helper, {"kind": "zombie", "id": boss.id}, 3.0)
	server._damage_target(killer, {"kind": "zombie", "id": boss.id}, 1000.0)
	t.check(not boss.is_alive(), "server confirms a single boss kill")
	t.eq(server.bags.size(), 1, "one shared bag exists for all raid rewards")
	if server.bags.is_empty():
		return
	var bag_id: int = int(server.bags.keys()[0])
	var bag: Dictionary = server.bags[bag_id]
	t.near(RaidLoot.remaining(bag, server.time), RaidLoot.LOCK_SECONDS, 0.001,
		"raid reservation lasts a bounded 75 seconds")
	t.eq(server.cmd_loot(103, bag_id).get("reason"), "raid_reserved",
		"outsider at corpse cannot ninja-loot")
	t.eq(server.cmd_loot(104, bag_id).get("reason"), "raid_reserved",
		"AFK party members cannot claim contributor loot")
	t.eq(outsider.inventory.count("infected_core"), 0, "denied pickup creates no trophies")
	t.eq(server.bags[bag_id]["items"], bag["items"], "denied pickup does not mutate reward bag")
	var public: Array = server.snapshot_for(103)["bags"]
	t.eq(public.size(), 1, "outsider can see bag's position")
	t.check(public[0]["raid"] and public[0]["reserved_seconds"] > 0.0,
		"outsiders see why loot cannot be picked up yet")
	t.check(not public[0].has("raid_eligible_tokens") and not public[0].has("owner_account"),
		"recipient account identities remain private")

	t.current = "reconnection keeps authenticated earned loot rights"
	server.remove_player(102)
	var wrong = server.add_player(102, "Impostor", "different-account")
	wrong.position = _position(world, 901.0, 900.0)
	t.eq(server.cmd_loot(102, bag_id).get("reason"), "raid_reserved",
		"recycled peer number cannot steal previous account entitlement")
	server.remove_player(102)
	var rejoined = server.add_player(205, "Archer", "account-archer")
	rejoined.position = _position(world, 901.0, 900.0)
	t.check(server.cmd_loot(205, bag_id).get("ok", false),
		"real contributing account can loot after reconnecting")
	t.check(not server.bags.has(bag_id), "shared bag disappears after full pickup")
	t.eq(server.cmd_loot(205, bag_id).get("reason"), "nothing_there",
		"replaying pickup cannot duplicate rewards")

	t.current = "public pickup after reservation ends"
	var second = _boss(server, world, 902.0, 900.0)
	server._damage_target(killer, {"kind": "zombie", "id": second.id}, 1000.0)
	var second_id: int = int(server.bags.keys()[0])
	t.eq(server.cmd_loot(103, second_id).get("reason"), "raid_reserved",
		"another boss has an independent fresh lock")
	server.time += RaidLoot.LOCK_SECONDS + 0.01
	t.near(RaidLoot.remaining(server.bags[second_id], server.time), 0.0, 0.001,
		"reservation expires based only on authoritative server time")
	t.check(server.cmd_loot(103, second_id).get("ok", false),
		"outsider may collect remaining loot after lock expiry")
	t.check(not server.bags.has(second_id), "public collection removes original bag")

	t.current = "regular infected and guest peer reuse"
	var regular = Zombie.new(server.new_id(), "walker", _position(world, 902.0, 900.0), -1)
	server.zombies[regular.id] = regular
	server._damage_target(killer, {"kind": "zombie", "id": regular.id}, 500.0)
	var regular_id: int = int(server.bags.keys()[0])
	t.check(server.cmd_loot(103, regular_id).get("ok", false),
		"ordinary infected loot is never raid-locked")
	var guest = server.add_player(501, "Unregistered")
	guest.position = _position(world, 901.0, 900.0)
	var third = _boss(server, world, 902.0, 900.0)
	server._damage_target(guest, {"kind": "zombie", "id": third.id}, 1000.0)
	var guest_bag: int = int(server.bags.keys()[0])
	server.remove_player(501)
	var recycled = server.add_player(501, "RecycledGuest")
	recycled.position = _position(world, 901.0, 900.0)
	t.eq(server.cmd_loot(501, guest_bag).get("reason"), "raid_reserved",
		"reused anonymous peer ID cannot inherit disconnected guest rights")
