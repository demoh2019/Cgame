extends RefCounted
## Real owner consent, real loot, current party isolation and revocation.
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Rescue = preload("res://scripts/shared/party_corpse_rescue.gd")
const Atlas = preload("res://scripts/shared/expedition_atlas.gd")
const Radar = preload("res://scripts/client/survival_radar.gd")


func run(t) -> void:
	t.current = "only an actual death bag may be shared with an existing group"
	var world := WorldGen.new(114)
	var server := GameServer.new(world, 114)
	var dead = server.add_player(101, "Fallen", "owner-account")
	var friend = server.add_player(102, "Friend", "friend-account")
	var stranger = server.add_player(103, "Stranger", "stranger-account")
	friend.position = dead.position + Vector3(1, 0, 0)
	t.eq(server.cmd_party_corpse_rescue(101).get("reason", ""), "not_in_party",
		"cannot signal an unrelated group")
	t.check(server.cmd_party_invite(101, 102).get("ok", false),
		"nearby survivor can issue legitimate invitation")
	t.check(server.cmd_party_accept(102).get("ok", false),
		"two members join an authenticated party")
	t.eq(server.cmd_party_corpse_rescue(101).get("reason", ""),
		"no_recoverable_bag", "alive owner cannot forge a loot destination")
	dead.position = Vector3(800.0, world.height_at(800.0, 0.0), 0.0)
	dead.inventory.add("wood_1", 4)
	server._on_player_death(dead, -1)
	t.eq(server.snapshot_for(102)["you"]["party"].get("corpse_rescue", {}),
		{}, "without consent teammate sees no location after real death")
	var accepted: Dictionary = server.cmd_party_corpse_rescue(101)
	t.check(bool(accepted.get("ok", false)), "fallen player can ask for help")
	var shared: Dictionary = server.snapshot_for(102)["you"]["party"]["corpse_rescue"]
	t.eq(shared.get("x", 0.0), 800.0, "only true death X is sent")
	t.eq(shared.get("z", 0.0), 0.0, "only true death Z is sent")
	t.check(float(shared.get("remaining", 0.0)) > 0.0 and
		float(shared.get("remaining", 0.0)) <= Rescue.SECONDS,
		"beacon is limited to ninety seconds or less")
	t.check(not shared.has("bag") and not shared.has("owner_token") and
		not shared.has("items"), "account identity and loot remain secret")
	t.eq(server.snapshot_for(103)["you"]["party"].get("corpse_rescue", {}),
		{}, "nearby unrelated player sees no party rescue")
	t.eq(server.cmd_party_corpse_rescue(101).get("reason", ""),
		"already_shared", "replay cannot make extra markers")
	t.eq(Atlas.find(Atlas.objectives(server.snapshot_for(102)["you"]),
		"rescue").get("label", ""), "RECOVER TEAMMATE GEAR",
		"authorized escort can select actual objective on map")
	t.eq(Atlas.find(Atlas.objectives(server.snapshot_for(103)["you"]),
		"rescue"), {}, "outsider has no map objective")
	var radar := Radar.new()
	radar.sim = server
	radar.actor_id = 102
	t.eq(radar.current_party_corpse_rescue(), shared,
		"private radar equals authenticated snapshot")
	radar.actor_id = 103
	t.eq(radar.current_party_corpse_rescue(), {}, "outsider radar has no point")

	t.current = "leaving and theft revoke access without teleport or loot rights"
	t.check(server.cmd_party_leave(102).get("ok", false),
		"teammate leaves freely")
	t.eq(server.snapshot_for(102)["you"]["party"].get("corpse_rescue", {}),
		{}, "former member immediately loses marker")
	friend.position = Vector3(800.0, world.height_at(800.0, 0.0), 0.0)
	var id: int = int(server.bags.keys()[0])
	var result: Dictionary = server.cmd_loot(102, id)
	t.check(result.get("ok", false), "real bag remains public and lootable")
	t.eq(Rescue.shared(101, server.players, server.parties,
		server.bags, server.time), {}, "disbanded group can't retain a signal")
	t.check(not server.bags.has(id), "all physical loot was taken normally")
	radar.free()
