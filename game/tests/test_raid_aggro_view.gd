extends RefCounted
## Player-specific PvE boss threat signals; never publishes raw hate tables.
## Existing threat/taunt damage mechanics remain authoritative.

const View = preload("res://scripts/shared/raid_aggro_view.gd")
const Threat = preload("res://scripts/shared/threat.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const RaidEncounter = preload("res://scripts/shared/raid_encounter.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "live boss threat is private to nearby members of the engaged party"
	var world := WorldGen.new(69)
	var sim := GameServer.new(world, 69)
	var guardian = sim.add_player(101, "Guardian", "raid-tank")
	var archer = sim.add_player(102, "Archer", "raid-archer")
	var outsider = sim.add_player(103, "Stranger", "raid-outsider")
	var healer = sim.add_player(104, "Healer", "raid-healer")
	guardian.position = _at(world, 851.0, 0.0)
	archer.position = _at(world, 852.0, 0.0)
	outsider.position = _at(world, 853.0, 0.0)
	healer.position = _at(world, 849.0, 0.0)
	t.check(sim.parties.invite(101, 102, sim.time).get("ok", false), "leader invites archer")
	t.check(sim.parties.accept(102, sim.time).get("ok", false), "archer joins group")
	t.check(sim.parties.invite(101, 104, sim.time).get("ok", false), "leader invites healer")
	t.check(sim.parties.accept(104, sim.time).get("ok", false), "healer joins group")
	var boss := Zombie.new(sim.new_id(), "brute", _at(world, 850.0, 0.0), -1)
	RaidEncounter.empower(boss)
	sim.zombies[boss.id] = boss
	sim.raid_boss_id = boss.id
	t.eq(View.for_viewer(boss, guardian, sim.players, sim.parties, world), {},
		"idle boss without target or threat shows no misleading warning")
	boss.target_id = guardian.id
	t.check(Threat.record(boss.threat, guardian.id, 30.0),
		"confirmed server threat is stored on the boss")
	t.check(Threat.record(boss.threat, archer.id, 20.0),
		"second contributor participates in server threat")
	var tank: Dictionary = View.for_viewer(boss, guardian, sim.players, sim.parties, world)
	t.eq(int(tank.get("boss", -1)), boss.id, "live encounter is identified")
	t.eq(int(tank.get("target", -1)), guardian.id, "actual current target is visible")
	t.eq(int(tank.get("top", -1)), guardian.id, "party threat lead is server-derived")
	t.eq(int(tank.get("your_pct", -1)), 100, "current tank has full party-relative lead")
	t.check(bool(tank.get("targeted", false)), "tank is warned that boss targets them")
	t.eq(int(tank.get("pull_pct", -1)), -1,
		"already-targeted player is not told to steal their own aggro")
	var ranged: Dictionary = View.for_viewer(boss, archer, sim.players, sim.parties, world)
	t.eq(int(ranged.get("your_pct", -1)), 67, "archer sees 20/30 party contribution ratio")
	t.eq(int(ranged.get("pull_pct", -1)), 53,
		"aggro swap threshold includes existing 125% hysteresis")
	t.check(not bool(ranged.get("targeted", false)), "other player is not marked as boss target")
	t.eq(View.for_viewer(boss, outsider, sim.players, sim.parties, world), {},
		"nearby non-party player cannot read the team's threat state")
	t.check(not tank.has("threat") and not tank.has("entries") and
			not tank.has("user_id") and not tank.has("account"),
		"raw hate tables and account identifiers never leave the server")

	t.current = "healing threat, taunt, strangers and stale members"
	boss.threat[healer.id] = 22.0
	var medical: Dictionary = View.for_viewer(boss, healer, sim.players, sim.parties, world)
	t.eq(int(medical.get("your_pct", -1)), 73,
		"medic can monitor party-relative healing threat")
	t.eq(int(medical.get("pull_pct", -1)), 59,
		"medic sees estimated distance to pulling the boss")
	boss.forced_target_id = guardian.id
	boss.forced_target_seconds = 3.0
	var forced: Dictionary = View.for_viewer(boss, archer, sim.players, sim.parties, world)
	t.check(bool(forced.get("taunted", false)), "active guardian taunt is shown to teammates")
	t.near(float(forced.get("taunt_seconds", 0.0)), 3.0, 0.001,
		"server duration is used, not a client-side countdown guess")
	boss.target_id = outsider.id
	var rival: Dictionary = View.for_viewer(boss, archer, sim.players, sim.parties, world)
	t.eq(int(rival.get("target", -1)), 0,
		"current target outside the group is never exposed by peer ID")
	t.check(not bool(rival.get("targeted", false)), "outsider target does not imply the archer is targeted")
	boss.target_id = guardian.id
	boss.forced_target_seconds = 0.0
	archer.position = _at(world, 903.0, 0.0)
	t.eq(View.for_viewer(boss, archer, sim.players, sim.parties, world), {},
		"member beyond the restricted awareness radius receives no boss intel")
	archer.position = _at(world, 852.0, 0.0)
	archer.position = Vector3(852.0, boss.position.y + View.DISPLAY_HEIGHT + 1.0, 0.0)
	t.eq(View.for_viewer(boss, archer, sim.players, sim.parties, world), {},
		"members on an unrelated elevation cannot scout the raid")
	archer.position = _at(world, 852.0, 0.0)
	archer.position = Vector3(INF, 0.0, 0.0)
	t.eq(View.for_viewer(boss, archer, sim.players, sim.parties, world), {},
		"nonfinite player positions cannot leak a boss status")
	archer.position = _at(world, 852.0, 0.0)

	t.current = "very large but finite threat cannot overflow raid percentages"
	boss.target_id = guardian.id
	boss.threat[guardian.id] = 8.0e307
	boss.threat[archer.id] = 6.0e307
	var huge: Dictionary = View.for_viewer(boss, archer, sim.players, sim.parties, world)
	t.eq(int(huge.get("your_pct", -1)), 75,
		"finite extreme threat retains its accurate share without overflow")
	t.eq(int(huge.get("pull_pct", -1)), 60,
		"pull threshold divides before multiplying into display percent")
	boss.threat[guardian.id] = 1.0e-300
	boss.threat[archer.id] = 1.0e307
	var dominant: Dictionary = View.for_viewer(boss, archer, sim.players, sim.parties, world)
	t.eq(int(dominant.get("pull_pct", -1)), 999,
		"unrepresentable threat ratio saturates rather than converting INF to int")
	boss.forced_target_seconds = INF
	boss.forced_target_id = guardian.id
	var invalid_taunt: Dictionary = View.for_viewer(boss, archer, sim.players, sim.parties, world)
	t.check(not bool(invalid_taunt.get("taunted", true)),
		"invalid taunt timer cannot create a permanent HUD warning")
	boss.forced_target_seconds = 0.0
	boss.forced_target_id = -1
	boss.threat[guardian.id] = 30.0
	boss.threat[archer.id] = 20.0

	t.current = "actual snapshots carry only private server fields"
	var tank_snapshot: Dictionary = sim.snapshot_for(101)
	t.eq(int(tank_snapshot["you"]["raid_aggro"].get("target", -1)), guardian.id,
		"server snapshot reports the current party tank")
	t.eq(sim.snapshot_for(103)["you"]["raid_aggro"], {},
		"stranger's personal snapshot contains no group threat")
	var public_boss: Dictionary = {}
	for entity in tank_snapshot["zombies"]:
		if int(entity.get("id", -1)) == boss.id:
			public_boss = entity
	t.check(not public_boss.is_empty(), "raid boss is visible at ordinary interest distance")
	t.check(not public_boss.has("threat") and not public_boss.has("raid_aggro") and
			not public_boss.has("forced_target_id"),
		"public zombie snapshot never publishes a PvE hate list")
	healer.position = _at(world, 945.0, 0.0)
	t.eq(sim.snapshot_for(104)["you"]["raid_aggro"], {},
		"distant healer receives no private team threat intel")
	healer.position = _at(world, 849.0, 0.0)
	boss.threat[guardian.id] = INF
	boss.threat[archer.id] = NAN
	var damaged: Dictionary = View.for_viewer(boss, guardian, sim.players, sim.parties, world)
	t.check(int(damaged.get("your_pct", -1)) <= 100,
		"corrupt threat values are never converted into infinite UI percentages")
	boss.take_damage(2000.0)
	t.eq(sim.snapshot_for(101)["you"]["raid_aggro"], {},
		"dead raid boss produces no stale aggro HUD state")
