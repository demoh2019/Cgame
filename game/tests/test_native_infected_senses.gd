extends RefCounted
## Native Cgame perception must not circumvent existing server authoritative
## detection rules; stock Godot runs these checks using the empty fallback.

const NativeSenses = preload("res://scripts/shared/native_infected_senses.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Defs = preload("res://scripts/shared/defs.gd")


func run(t) -> void:
    t.current = "Native perception bridge safely detects engine capabilities"
    var senses := NativeSenses.new()
    t.eq(senses.has_native_vision(), ClassDB.class_exists("AIVisualSensor2D"),
        "vision support is negotiated through the native class registry")
    t.eq(senses.has_native_hearing(), ClassDB.class_exists("AIHearingSensor2D"),
        "hearing support is negotiated through the native class registry")

    t.current = "Native vision remembers the last confirmed position only"
    senses.record_confirmed_sight(Vector2.ZERO, Vector2(8, 0), 20.0, true, 0.1)
    if senses.has_native_vision():
        t.check(senses.remembers_sight(), "accepted LOS creates temporary sight memory")
        t.eq(senses.last_seen_position(), Vector2(8, 0), "last seen position is stored")
        senses.record_confirmed_sight(Vector2.ZERO, Vector2(18, 0), 20.0, false, 0.1)
        t.eq(senses.last_seen_position(), Vector2(8, 0),
            "hidden target motion never leaks into sight memory")
        senses.reset()
        t.check(not senses.remembers_sight(), "reset clears native visual memory")
    else:
        t.check(not senses.remembers_sight(), "stock Godot omits native visual memory")

    t.current = "Native hearing records only caller-accepted sounds"
    t.check(not senses.record_confirmed_sound(Vector2.ZERO, Vector2(80, 0), 20.0),
        "sound outside listening range cannot forge memory")
    if senses.has_native_hearing():
        t.check(senses.record_confirmed_sound(Vector2.ZERO, Vector2(12, 0), 20.0),
            "an accepted sound is recorded by native hearing")
        t.eq(senses.last_heard_position(), Vector2(12, 0),
            "hearing preserves accepted event location")
        senses.advance_time(4.0)
        t.check(not senses.remembers_sound(), "sound memory expires in real seconds")
    else:
        t.check(not senses.remembers_sound(), "stock Godot has a safe no-op fallback")

    t.current = "Existing authoritative zombie hearing populates native memory"
    var height: float = WorldGen.HUB_HEIGHT
    var world := WorldGen.new(42)
    var infected := Zombie.new(972, "walker", Vector3(0.0, height, 0.0))
    var rng := RandomNumberGenerator.new()
    rng.seed = 972
    var players := {41: {"position": Vector3(12.0, height, 0.0),
        "alive": true, "safe": false, "noise": Defs.SPRINT_NOISE_RADIUS}}
    infected.think(world, players, 0.1, rng)
    if ClassDB.class_exists("AIHearingSensor2D"):
        t.check(infected._native_senses != null,
            "server accepted hearing instantiates the optional native cache")
        if infected._native_senses != null:
            t.check(infected._native_senses.remembers_sound(),
                "native bridge remembers the authoritative sound event")
            t.eq(infected._native_senses.last_heard_position(), Vector2(12, 0),
                "native cache stores the detected survivor position")
    t.eq(infected.target_id, 41,
        "native sensing does not change the existing authoritative target decision")

    t.current = "Safe-zone players never create native hearing stimulus"
    var protected := Zombie.new(973, "walker", Vector3(0.0, height, 0.0))
    protected.think(world, {41: {"position": Vector3(12.0, height, 0.0),
        "alive": true, "safe": true, "noise": Defs.GUNSHOT_NOISE_RADIUS}},
        0.1, rng)
    t.eq(protected.target_id, -1, "protected survivors remain immune")
    t.check(protected._native_senses == null,
        "immune survivors never enter native sensor memory")
