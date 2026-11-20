extends RefCounted
## Integration regression for paid PvE intel shared only with an unchanged party.
## Both offline and online radars read the same server-verified snapshot field.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const ThreatScan = preload("res://scripts/shared/field_threat_scanner.gd")
const Radar = preload("res://scripts/client/survival_radar.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	var world := WorldGen.new(681)
	var server := GameServer.new(world, 681)
	server.zombies.clear()
	var scout = server.add_player(711, "Scout")
	var ally = server.add_player(712, "Ally")
	var recruit = server.add_player(713, "Recruit")
	var outsider = server.add_player(714, "Outsider")
	scout.position = _at(world, 800.0, 100.0)
	ally.position = _at(world, 805.0, 100.0)
	recruit.position = _at(world, 806.0, 100.0)
	outsider.position = _at(world, 807.0, 100.0)
	var boss := Zombie.new(server.new_id(), "brute", _at(world, 825.0, 100.0))
	boss.raid_boss = true
	server.zombies[boss.id] = boss
	scout.inventory.add(ThreatScan.ITEM_ID, 4)

	t.current = "a paid scan binds party intel to the live roster at activation"
	t.check(server.cmd_party_invite(scout.id, ally.id).get("ok", false),
		"invitation uses server-authorized proximity")
	t.check(server.cmd_party_accept(ally.id).get("ok", false),
		"teammate joins before scanner activation")
	var original_group: int = server.parties.group_of(scout.id)
	t.check(original_group > 0, "an actual party has a server-issued ID")
	var result: Dictionary = server.cmd_use(scout.id, ThreatScan.ITEM_ID)
	t.check(result.get("ok", false) and result.get("party_shared", false),
		"one actual item activates party sharing")
	t.eq(scout.inventory.count(ThreatScan.ITEM_ID), 3,
		"shared intel never duplicates or refunds the paid device")
	var personal: Dictionary = server.snapshot_for(scout.id)["you"]["threat_scan"]
	var shared: Dictionary = server.snapshot_for(ally.id)["you"]["threat_scan"]
	t.eq(str(personal.get("kind", "")), "raid",
		"owner retains original personal boss tracker")
	t.eq(int(shared.get("shared_by", -1)), scout.id,
		"teammate sees the verified scout, not a client-provided enemy ID")
	t.near(float(shared.get("x", 0.0)), boss.position.x, 0.001,
		"teammate tracks live server position")
	t.check(not shared.has("target") and not shared.has("expires") and
		not shared.has("members") and not shared.has("group"),
		"internal target and roster data never leak to the client")
	t.eq(server.snapshot_for(outsider.id)["you"]["threat_scan"], {},
		"unrelated survivor gets no intel even while standing beside the scout")
	t.eq(server.snapshot_for(recruit.id)["you"]["threat_scan"], {},
		"player not yet invited cannot use party tracking")
	for candidate in server.snapshot_for(outsider.id)["players"]:
		t.check(not candidate.has("threat_scan"),
			"public actor snapshots never carry party scanner data")

	t.current = "online and offline markers agree and obey physical tracking bounds"
	var radar := Radar.new()
	radar.sim = server
	radar.actor_id = ally.id
	t.eq(radar.current_threat_scan(), shared,
		"offline radar uses the exact same server-approved shared marker")
	ally.position = _at(world, 1200.0, 100.0)
	t.eq(server.threat_scan_for(ally.id), {},
		"far-away teammate cannot obtain a world-wide boss locator")
	ally.position = _at(world, 805.0, 100.0)
	boss.position = _at(world, 1200.0, 100.0)
	t.eq(server.threat_scan_for(ally.id), {},
		"tracking stops when the infected leaves the allowed vicinity")
	boss.position = _at(world, 825.0, 100.0)
	boss.state = Zombie.State.DEAD
	t.eq(server.threat_scan_for(ally.id), {},
		"dead boss is never kept in a shared radar")
	boss.state = Zombie.State.IDLE
	scout.survival.alive = false
	t.eq(server.threat_scan_for(ally.id), {},
		"dead scout cannot keep relaying tactical intel")
	scout.survival.alive = true
	t.check(not server.threat_scan_for(ally.id).is_empty(),
		"living scout restores the still-valid signal without a free rescan")

	t.current = "party membership changes invalidate old tactical signals"
	t.check(server.cmd_party_invite(scout.id, recruit.id).get("ok", false),
		"leader may recruit a new party member")
	t.check(server.cmd_party_accept(recruit.id).get("ok", false),
		"new participant joins the original party ID")
	t.eq(server.parties.group_of(scout.id), original_group,
		"joining preserves the group identity but changes the roster")
	t.eq(server.threat_scan_for(recruit.id), {},
		"late joiner cannot inherit a scan made before joining")
	t.eq(server.threat_scan_for(ally.id), {},
		"old party marker is revoked on roster change")
	result = server.cmd_use(scout.id, ThreatScan.ITEM_ID)
	t.check(result.get("ok", false) and result.get("party_shared", false),
		"fresh paid scanner explicitly authorizes the new roster")
	t.eq(int(server.threat_scan_for(recruit.id).get("shared_by", 0)), scout.id,
		"newly authorized member receives a real moving marker")
	t.check(server.cmd_party_leave(recruit.id).get("ok", false),
		"recruit exits the party")
	t.eq(server.threat_scan_for(ally.id), {},
		"removing a teammate revokes the previous party-wide signal")
	t.eq(server.threat_scan_for(recruit.id), {},
		"departing survivor can no longer see the scanner")

	t.current = "expiry, solo use and unrelated group changes stay private"
	server.time += ThreatScan.MARK_SECONDS
	t.eq(server.threat_scan_for(scout.id), {},
		"owner's paid pin expires on time")
	t.eq(server.threat_scan_for(ally.id), {},
		"relay never outlives its original scanner window")
	t.check(server.cmd_party_leave(ally.id).get("ok", false),
		"party disbands when second member leaves")
	result = server.cmd_use(scout.id, ThreatScan.ITEM_ID)
	t.check(result.get("ok", false) and not result.get("party_shared", true),
		"solo scans stay private despite carrying the same item")
	t.check(server.cmd_party_invite(scout.id, ally.id).get("ok", false),
		"solo scout can subsequently form a new party")
	t.check(server.cmd_party_accept(ally.id).get("ok", false),
		"ally may join after a solo scan")
	t.eq(server.threat_scan_for(ally.id), {},
		"joining later cannot retroactively share private scouting")
	radar.actor_id = outsider.id
	t.eq(radar.current_threat_scan(), {},
		"an unrelated local client cannot borrow party intelligence")
	radar.free()
