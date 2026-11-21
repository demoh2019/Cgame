extends RefCounted
## Deterministic per-NPC staggering must never delay first acquisition,
## combat, or core world simulation. Stock Godot retains original AI behavior.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
    t.current = "Native time slots are stable, exhaustive and optional"
    var native_available := ClassDB.class_exists("AIUpdateScheduler")
    var scheduler: Variant = ClassDB.instantiate("AIUpdateScheduler") if native_available else null
    if scheduler != null:
        scheduler.set_slots_per_cycle(4)
        var counts := [0, 0, 0, 0]
        for id in range(128):
            var slot := int(scheduler.get_agent_slot(id))
            t.check(slot >= 0 and slot < 4, "native hash assigns a valid AI phase")
            counts[slot] += 1
            var decisions := 0
            for tick in range(4):
                if scheduler.is_due(id, tick):
                    decisions += 1
            t.eq(decisions, 1, "each infected gets one scheduled scan per cycle")
            t.check(scheduler.is_due(id, 17, true), "urgent scan is never deferred")
        for count in counts:
            t.check(count >= 15, "a crowd is distributed across several phases")

    t.current = "Batch phase mask is index-preserving and scalar-equivalent"
    var batch_available: bool = scheduler != null and scheduler.has_method("get_due_mask")
    if batch_available:
        var cohort_ids := PackedInt64Array()
        for id in range(256):
            cohort_ids.append(50000 + id)
        cohort_ids.append(-1)
        cohort_ids.append(50000)
        for tick in range(12):
            var mask: PackedByteArray = scheduler.get_due_mask(cohort_ids, tick)
            t.eq(mask.size(), cohort_ids.size(), "batch returns exactly one flag per ID")
            for i in range(cohort_ids.size()):
                t.eq(int(mask[i]), 1 if scheduler.is_due(cohort_ids[i], tick) else 0,
                    "batched phases equal scalar phases for every signed ID")
            t.eq(mask[0], mask[257], "duplicate agent IDs have identical admission")
        t.check(scheduler.get_due_mask(cohort_ids, -1).is_empty(),
            "negative authoritative ticks reject the whole batch")
        var huge := PackedInt64Array()
        huge.resize(4097)
        t.check(scheduler.get_due_mask(huge, 0).is_empty(),
            "native API bounds untrusted array sizes to 4096")
        var maximal := PackedInt64Array()
        maximal.resize(4096)
        t.eq(scheduler.get_due_mask(maximal, 0).size(), 4096,
            "legal maximum cohort is processed")
        scheduler.set_slots_per_cycle(1)
        var forced: PackedByteArray = scheduler.get_due_mask(cohort_ids, 99)
        t.eq(forced.size(), cohort_ids.size(), "single-slot cohort returns all flags")
        t.check(forced[0] == 1 and forced[1] == 1,
            "single-slot scheduling never delays a survivor encounter")
        scheduler.set_slots_per_cycle(4)

    t.current = "Direct infected AI preserves first-contact and urgent selection"
    var world := WorldGen.new(42)
    var ground: float = WorldGen.HUB_HEIGHT
    var rng := RandomNumberGenerator.new()
    rng.seed = 17
    var z := Zombie.new(700, "walker", Vector3(0.0, ground, 0.0))
    var players := {11: {"position": Vector3(10.0, ground, 0.0),
        "alive": true, "safe": false, "noise": 0.0}}
    z.ai_selection_allowed = false
    z.think(world, players, 0.1, rng)
    t.eq(z.target_id, 11, "first sighting is immediate even if the slot denies scanning")
    z.target_id = -1
    z.state = Zombie.State.IDLE
    z.think_timer = 0.0
    z.think(world, players, 0.1, rng)
    t.eq(z.target_id, -1, "ordinary repeated scan may be postponed safely")
    z.ai_selection_allowed = true
    z.think(world, players, 0.1, rng)
    t.eq(z.target_id, 11, "next assigned slot allows target reacquisition")

    t.current = "Combat threat bypasses deferred scans"
    z.target_id = -1
    z.state = Zombie.State.IDLE
    z.think_timer = 0.0
    z.ai_selection_allowed = false
    z.threat[11] = 10.0
    z.think(world, players, 0.1, rng)
    t.eq(z.target_id, 11, "existing combat threat cannot be throttled")

    t.current = "Native simulation LOD cadence remains compatible"
    var passive := Zombie.new(701, "walker", Vector3(0.0, ground, 0.0))
    passive.think(world, {}, 0.1, rng)
    passive.think_timer = 0.0
    passive.think(world, {}, 0.1, rng)
    if ClassDB.class_exists("AISimulationLOD2D"):
        t.eq(passive.think_timer, 1.0,
            "far passive scans keep their existing native one-second LOD interval")
    else:
        t.eq(passive.think_timer, 0.25,
            "stock Godot retains the legacy passive scan rate")

    t.current = "Passive infected hold stable LOD across small observer movement"
    var lod_engine: Variant = Zombie._get_ai_lod_scheduler()
    if lod_engine != null and lod_engine.has_method("get_hysteretic_interval"):
        var stable := Zombie.new(702, "walker", Vector3(0.0, ground, 0.0))
        var near_range: float = float(stable.data["lose"])
        var far_range: float = near_range + 24.0
        # Eligible but out of hearing/sight distance: never turns into a
        # combat target and keeps ordinary server simulation each tick.
        var viewers := {99: {"position": Vector3(far_range - 2.0, ground, 0.0),
            "alive": true, "safe": false, "noise": 0.0}}
        stable.think(world, viewers, 0.1, rng)
        t.eq(stable._ai_lod_previous_interval, 0.5,
            "initial deterministic startup phase remembers the nominal medium LOD")
        t.eq(stable.target_id, -1, "distant passive viewer is not an AI target")
        stable.think_timer = 0.0
        viewers[99] = {"position": Vector3(far_range + 2.0, ground, 0.0),
            "alive": true, "safe": false, "noise": 0.0}
        stable.think(world, viewers, 0.1, rng)
        t.eq(stable.think_timer, 0.5,
            "2m boundary movement keeps medium scanning cadence")
        stable.think_timer = 0.0
        viewers[99] = {"position": Vector3(far_range + 6.0, ground, 0.0),
            "alive": true, "safe": false, "noise": 0.0}
        stable.think(world, viewers, 0.1, rng)
        t.eq(stable.think_timer, 1.0, "real movement admits far LOD")
        stable.think_timer = 0.0
        viewers[99] = {"position": Vector3(far_range - 2.0, ground, 0.0),
            "alive": true, "safe": false, "noise": 0.0}
        stable.think(world, viewers, 0.1, rng)
        t.eq(stable.think_timer, 1.0,
            "small return movement cannot cause far/medium flapping")
        stable.think_timer = 0.0
        viewers[99] = {"position": Vector3(far_range - 6.0, ground, 0.0),
            "alive": true, "safe": false, "noise": 0.0}
        stable.think(world, viewers, 0.1, rng)
        t.eq(stable.think_timer, 0.5, "significant approach restores medium cadence")
        stable.think_timer = 0.0
        viewers[99] = {"position": Vector3(2.0, ground, 0.0),
            "alive": true, "safe": false, "noise": 0.0}
        stable.think(world, viewers, 0.1, rng)
        t.eq(stable.target_id, 99, "close survivor still causes immediate acquisition")
        t.eq(stable.think_timer, 0.25,
            "first contact retains legacy near/combat decision cadence")
    else:
        t.check(lod_engine == null or not lod_engine.has_method("get_hysteretic_interval"),
            "stock and older Cgame retain existing AI LOD behavior")

    t.current = "Native crowd separation steers only passive infected"
    var walker := Zombie.new(704, "walker", Vector3(0.0, ground, 0.0))
    walker.state = Zombie.State.WANDER
    walker.set_passive_crowd_separation(Vector2(-1.0, 0.0))
    walker._move_toward(world, Vector2.ZERO, Vector2(0.0, 10.0), 1.0, 0.033)
    t.check(walker.yaw < 0.0,
        "wandering direction includes gentle native separation")
    var attacker := Zombie.new(705, "walker", Vector3(0.0, ground, 0.0))
    attacker.state = Zombie.State.CHASE
    attacker.set_passive_crowd_separation(Vector2(-1.0, 0.0))
    attacker._move_toward(world, Vector2.ZERO, Vector2(0.0, 10.0), 1.0, 0.033)
    t.near(attacker.yaw, 0.0, 0.0001,
        "combat chase ignores ambient crowd steering")
    walker.set_passive_crowd_separation(Vector2.INF)
    t.eq(walker._passive_crowd_separation, Vector2.ZERO,
        "invalid native vectors cannot affect movement")
    walker.set_passive_crowd_separation(Vector2(100.0, 0.0))
    t.eq(walker._passive_crowd_separation, Vector2.RIGHT,
        "movement receives only bounded steering magnitudes")

    t.current = "Authoritative server batches passive crowd avoidance at low frequency"
    var crowd := GameServer.new(WorldGen.new(113), 113)
    crowd.tick_count = 5 # Native steering refresh; no spawn-maintenance pass.
    var crowd_mobs: Array = []
    for index in range(32):
        var cx: float = 0.0 if index == 0 else (
            1.0 if index == 1 else float(index * 10))
        var passive_mob := Zombie.new(60000 + index, "walker",
            Vector3(cx, ground, 0.0))
        passive_mob.state = Zombie.State.WANDER
        passive_mob.wander_target = Vector2(cx, 20.0)
        passive_mob.think_timer = 100.0
        crowd.zombies[passive_mob.id] = passive_mob
        crowd_mobs.append(passive_mob)
    crowd._tick_zombies(1.0 / 30.0)
    var crowd_available: bool = ClassDB.class_exists("AIProximityGrid2D") \
        and ClassDB.instantiate("AIProximityGrid2D").has_method("query_separation_batch")
    var crowd_stats: Dictionary = crowd.get_crowd_separation_stats()
    t.eq(bool(crowd_stats.get("enabled", false)), crowd_available,
        "native crowd steering is enabled only where API exists")
    if crowd_available:
        t.eq(int(crowd_stats.get("sources", -1)), 32,
            "one spatial batch covers every eligible passive infected")
        t.check(crowd_mobs[0]._passive_crowd_separation.x < 0.0,
            "first member receives a safe repulsion from close neighbor")
        t.check(crowd_mobs[1]._passive_crowd_separation.x > 0.0,
            "second member receives the opposite repulsion")
        t.eq(crowd_mobs[31]._passive_crowd_separation, Vector2.ZERO,
            "distant infected has no spurious avoidance")
        crowd.zombies.erase(crowd_mobs[31].id)
        crowd.tick_count = 6 # Below 32: clear even between refresh ticks.
        crowd._tick_zombies(1.0 / 30.0)
        t.check(not crowd.get_crowd_separation_stats()["enabled"],
            "falling below threshold immediately disables crowd steering")
        t.eq(crowd_mobs[0]._passive_crowd_separation, Vector2.ZERO,
            "stale steering never persists after crowd despawns")
    else:
        t.eq(crowd_mobs[0]._passive_crowd_separation, Vector2.ZERO,
            "stock and older Godot use unchanged movement")

    t.current = "GameServer uses native staggering only for large crowds"
    var sim := GameServer.new(WorldGen.new(112), 112)
    sim.tick_count = 2 # Avoid population maintenance in this isolated tick.
    var quiet: Dictionary = sim.get_ai_schedule_stats()
    t.check(not bool(quiet.get("enabled", false)),
        "newly started servers have no active scheduler")

    # All fabricated infected are already initialized. The server tick still
    # advances their normal idle/combat lifecycle even when selection is deferred.
    for index in range(128):
        var crowd_zombie := Zombie.new(50000 + index, "walker",
            Vector3(900.0 + float(index), ground, 900.0))
        crowd_zombie._ai_has_selected_once = true
        crowd_zombie.think_timer = 0.0
        sim.zombies[crowd_zombie.id] = crowd_zombie
    sim._tick_zombies(1.0 / 30.0)
    var stats: Dictionary = sim.get_ai_schedule_stats()
    t.eq(bool(stats.get("enabled", false)), native_available,
        "large crowds activate staggering only with the native Cgame class")
    t.eq(int(stats.get("population", -1)), 128,
        "server diagnostic counts the actual population")
    t.eq(bool(stats.get("batch_used", false)), batch_available and native_available,
        "authoritative server uses native masks only when the API is present")
    t.eq(int(stats.get("batch_size", 0)), 128 if batch_available and native_available else 0,
        "batch reports exactly the active server zombie cohort")
    if native_available:
        t.eq(int(stats.get("slots", -1)), 4,
            "server uses four stable update phases")
        t.eq(int(stats.get("phase_due", 0)) + int(stats.get("phase_deferred", 0)),
            128, "all eligible infected receive exactly one scheduling decision")
        t.check(int(stats.get("phase_deferred", 0)) > 0,
            "crowd target scans are distributed across later ticks")
    else:
        t.eq(int(stats.get("phase_deferred", 0)), 0,
            "stock Godot never throttles existing infected AI")
