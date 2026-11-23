extends RefCounted
## Walls face the way they were placed (snapped to eighths), keep while their owner comes by, crumble when left alone
## past their upkeep, and carry facing and upkeep through a server restart.

const Structures = preload("res://scripts/shared/structures.gd")
const WallUpkeepIndex = preload("res://scripts/shared/wall_upkeep_index.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldPersistence = preload("res://scripts/server/world_persistence.gd")


func _site(world) -> Vector2:
	for x in range(60, 400, 6):
		for z in range(60, 400, 6):
			if Structures.placement_reason(world, Vector2(x, z), Vector2(x - 3.0, z)) == "":
				return Vector2(x, z)
	return Vector2.INF


func run(t) -> void:
	t.current = "facing snaps to eighths of a circle"
	t.near(Structures.snap_yaw(0.8), PI / 4.0, 0.0001, "0.8 rad snaps to 45 degrees")
	t.near(Structures.snap_yaw(-PI / 2.0), PI * 1.5, 0.0001, "negative angles wrap")
	t.eq(Structures.snap_yaw(NAN), 0.0, "nonsense faces north")

	var world := WorldGen.new(214)
	var sim := GameServer.new(world, 214)
	var builder = sim.add_player(7, "Builder", "builder-account")
	var spot: Vector2 = _site(world)
	t.check(spot.is_finite(), "a buildable spot exists")
	if not spot.is_finite():
		return
	builder.position = Vector3(spot.x - 3.0, world.height_at(spot.x - 3.0, spot.y), spot.y)
	builder.inventory.add("wood_1", 10)
	builder.inventory.add("stone_1", 10)

	t.current = "placement uses the shared rules and stores the facing"
	t.eq(Structures.placement_reason(world, Vector2(5, 5), Vector2(3, 5)), "out_of_range" if Vector2(5, 5).distance_to(Vector2(3, 5)) < Structures.MIN_BUILD_DISTANCE else "safe_zone", "the hub refuses walls")
	var built: Dictionary = sim.cmd_build(7, spot.x, spot.y, 1.6)
	t.check(bool(built.get("ok", false)), "built")
	if not bool(built.get("ok", false)):
		return
	var id: int = int(built["id"])
	t.near(float(sim.barricades[id]["yaw"]), PI / 2.0, 0.0001, "stored facing is snapped")
	t.near(float(Structures.public_state(sim.barricades[id])["yaw"]), PI / 2.0, 0.0001, "and shown to everyone")

	t.current = "an owner nearby keeps the wall; left alone it crumbles"
	sim.barricades[id]["upkeep_until"] = sim.time - 1.0
	sim._tick_barricade_upkeep(60.0)
	t.check(float(sim.barricades[id]["upkeep_until"]) > sim.time, "the owner standing by renews the upkeep")
	t.near(float(sim.barricades[id]["hp"]), Structures.MAX_HEALTH, 0.0001, "and nothing decays")
	builder.position = Vector3(spot.x + 200.0, 0.0, spot.y)
	sim.barricades[id]["upkeep_until"] = sim.time - 1.0
	sim._tick_barricade_upkeep(600.0)
	t.check(float(sim.barricades[id]["hp"]) < Structures.MAX_HEALTH, "an abandoned wall loses health")
	sim._tick_barricade_upkeep(Structures.DECAY_SECONDS)
	t.check(not sim.barricades.has(id), "and is gone at zero")
	t.check(not sim.events.filter(func(e: Dictionary) -> bool: return e["type"] == "barricade_decayed").is_empty(), "the crumble is announced")

	t.current = "facing and upkeep survive a restart; older checkpoints still load"
	builder.position = Vector3(spot.x - 3.0, world.height_at(spot.x - 3.0, spot.y), spot.y)
	var again: Dictionary = sim.cmd_build(7, spot.x, spot.y, PI / 4.0)
	t.check(bool(again.get("ok", false)), "rebuilt")
	var checkpoint: Dictionary = WorldPersistence.capture(sim)
	t.near(float(checkpoint["barricades"][0]["yaw"]), PI / 4.0, 0.0001, "facing saved")
	t.check(float(checkpoint["barricades"][0]["upkeep"]) > 0.0, "upkeep saved")
	var reboot := GameServer.new(WorldGen.new(214), 215)
	t.check(WorldPersistence.restore(reboot, JSON.parse_string(JSON.stringify(checkpoint))), "restored")
	var restored: Dictionary = reboot.barricades.values()[0] if not reboot.barricades.is_empty() else {}
	t.near(float(restored.get("yaw", -1.0)), PI / 4.0, 0.0001, "restored facing")
	t.check(float(restored.get("upkeep_until", 0.0)) > reboot.time, "restored upkeep")
	var forged: Dictionary = checkpoint.duplicate(true)
	forged["barricades"][0]["upkeep"] = Structures.UPKEEP_SECONDS * 10.0
	t.check(WorldPersistence.validate(forged, GameServer.new(WorldGen.new(214), 216)).is_empty(), "endless upkeep is refused")


	t.current = "owner lookup preserves account rights and ignores strangers"
	var guarded := GameServer.new(WorldGen.new(214), 217)
	var owner = guarded.add_player(71, "Owner", "owner-acc")
	var stranger = guarded.add_player(72, "Stranger", "other-acc")
	var guest = guarded.add_player(73, "Guest")
	var watch_pos := Vector2(220.0, 220.0)
	var close: Vector3 = Vector3(watch_pos.x, 0.0, watch_pos.y)
	owner.position = Vector3(0.0, 0.0, 0.0)
	stranger.position = close
	guest.position = Vector3(0.0, 0.0, 0.0)
	var account_wall: Dictionary = {"id": 8101, "x": watch_pos.x, "z": watch_pos.y,
		"hp": Structures.MAX_HEALTH, "tier": 1, "owner": owner.id,
		"owner_account": "owner-acc", "upkeep_until": guarded.time - 1.0}
	var guest_wall: Dictionary = {"id": 8102, "x": watch_pos.x + 40.0, "z": watch_pos.y,
		"hp": Structures.MAX_HEALTH, "tier": 1, "owner": guest.id,
		"owner_account": "", "upkeep_until": guarded.time - 1.0}
	guarded.barricades[8101] = account_wall
	guarded.barricades[8102] = guest_wall
	guarded._tick_barricade_upkeep(60.0)
	t.check(float(account_wall["hp"]) < Structures.MAX_HEALTH,
		"stranger near a private wall cannot keep it alive")
	t.check(float(guest_wall["hp"]) < Structures.MAX_HEALTH,
		"distant guest cannot keep session-owned walls")
	var renewed: float = float(account_wall["hp"])
	owner.position = Vector3(watch_pos.x + Structures.UPKEEP_RANGE, 0.0, watch_pos.y)
	guarded._tick_barricade_upkeep(60.0)
	t.eq(float(account_wall["hp"]), renewed,
		"authenticated owner at exact 15m reach prevents more decay")
	t.eq(float(account_wall["upkeep_until"]), guarded.time + Structures.UPKEEP_SECONDS,
		"owner index renews real authoritative upkeep")
	var account_index: Dictionary = WallUpkeepIndex.live_owners(guarded.players,
		func(p) -> bool: return p.survival.health > 0.0)
	t.check(WallUpkeepIndex.owner_near(account_wall, account_index),
		"account lookup includes alive signed-in owners")
	t.check(not WallUpkeepIndex.owner_near(guest_wall, account_index),
		"guest owner lookup is keyed by peer ID, not account")
	owner.position = Vector3(0.0, 0.0, 0.0)
	var same_account = guarded.add_player(74, "Relogged owner", "owner-acc")
	same_account.position = close
	account_wall["upkeep_until"] = guarded.time - 1.0
	var before_relog: float = float(account_wall["hp"])
	guarded._tick_barricade_upkeep(60.0)
	t.eq(float(account_wall["hp"]), before_relog,
		"reconnected account prevents decay despite a different network peer")
	t.eq(float(account_wall["upkeep_until"]), guarded.time + Structures.UPKEEP_SECONDS,
		"same authenticated account can maintain a wall after peer ID changes")
	same_account.position = Vector3(0.0, 0.0, 0.0)
	guest.position = Vector3(watch_pos.x + 40.0, 0.0,
		watch_pos.y + Structures.UPKEEP_RANGE + 0.01)
	var guest_before: float = float(guest_wall["hp"])
	guarded._tick_barricade_upkeep(60.0)
	t.check(float(guest_wall["hp"]) < guest_before,
		"outside the exact guest upkeep range the wall continues to decay")
	guest.position = Vector3(watch_pos.x + 40.0, 0.0, watch_pos.y)
	var guest_after: float = float(guest_wall["hp"])
	guarded._tick_barricade_upkeep(60.0)
	t.eq(float(guest_wall["hp"]), guest_after, "the legitimate guest can renew their own wall")

	t.current = "owner-only early warnings and critical durability"
	account_wall["upkeep_until"] = guarded.time + WallUpkeepIndex.WARNING_SECONDS - 5.0
	account_wall["hp"] = Structures.MAX_HEALTH * 0.4
	var owner_view: Dictionary = guarded.snapshot_for(owner.id)["you"]["base_upkeep"]
	var stranger_view: Dictionary = guarded.snapshot_for(stranger.id)["you"]["base_upkeep"]
	t.eq(int(owner_view["at_risk"]), 1, "private snapshot warns about the owner's distant wall")
	t.eq(int(owner_view["damaged"]), 1, "private snapshot reports own badly damaged defenses")
	t.near(float(owner_view["soonest_seconds"]), WallUpkeepIndex.WARNING_SECONDS - 5.0,
		0.01, "warning includes exact server countdown")
	t.eq(int(stranger_view["at_risk"]), 0, "a different account never sees owner's upkeep alarm")
	t.eq(int(stranger_view["damaged"]), 0, "a different account cannot infer wall durability")
	t.check(not Structures.public_state(account_wall).has("owner_account"),
		"public wall metadata never leaks account identifiers")
	t.check(not Structures.public_state(account_wall).has("upkeep_until"),
		"public wall metadata does not broadcast private upkeep countdown")
	t.check(not WallUpkeepIndex.needs_attention(
		{"upkeep_until": guarded.time + WallUpkeepIndex.WARNING_SECONDS + 1.0}, guarded.time),
		"healthy upkeep does not notify owners too early")
	t.check(not WallUpkeepIndex.needs_attention({"upkeep_until": NAN}, guarded.time),
		"invalid upkeep timestamps never show a fabricated countdown")
	t.check(WallUpkeepIndex.needs_attention(
		{"upkeep_until": guarded.time}, guarded.time), "expired walls remain warned")
	account_wall["upkeep_until"] = guarded.time + Structures.UPKEEP_SECONDS
	account_wall["hp"] = Structures.MAX_HEALTH
	var healed_view: Dictionary = guarded.snapshot_for(owner.id)["you"]["base_upkeep"]
	t.eq(int(healed_view["at_risk"]), 0, "repairing upkeep clears the risk indicator")
	t.eq(int(healed_view["damaged"]), 0, "repaired defenses clear the damage indicator")
