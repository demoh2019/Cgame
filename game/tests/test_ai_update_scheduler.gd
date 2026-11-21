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
