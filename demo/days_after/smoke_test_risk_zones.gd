extends SceneTree
## Run on a built Cgame editor:
## --headless --path demo/days_after --script res://smoke_test_risk_zones.gd

const RULES = preload("res://risk_zone_rules.gd")


func _initialize() -> void:
    call_deferred("_test")


func _fail(reason: String) -> void:
    push_error("Days After risk zones: " + reason)
    quit(1)


func _test() -> void:
    var home := Vector3(0.0, 1.0, 7.0)
    var wild := Vector3(10.0, 1.0, 7.0)
    var danger := Vector3(-1.0, 1.0, -17.5)
    if RULES.zone_at(home) != RULES.CAMP or RULES.zone_at(wild) != RULES.WILDERNESS:
        _fail("Wrong camp or wilderness boundaries")
        return
    if RULES.zone_at(danger) != RULES.EXCLUSION:
        _fail("Missing exclusion territory")
        return
    if RULES.gathering_yield(home, home, 2) != 2:
        _fail("Camp must not award hazardous gathering bonus")
        return
    if RULES.gathering_yield(danger, danger, 2) != 3:
        _fail("Exclusion zone gathering bonus missing")
        return
    if RULES.gathering_yield(home, danger, 2) != 2:
        _fail("Remote collection must not award the hazardous gathering bonus")
        return
    if RULES.gathering_yield(danger, danger, -4) != 0:
        _fail("Bad harvest quantities must not become positive")
        return
    if RULES.danger_damage(1.0, home) != 0.0 or RULES.danger_damage(1.0, wild) != 0.0:
        _fail("Radiation must not apply outside the exclusion zone")
        return
    if RULES.danger_damage(1.0, danger) <= 0.0:
        _fail("Missing exposure in exclusion zone")
        return

    var scene := load("res://main.tscn") as PackedScene
    if scene == null:
        _fail("Cannot load the main game scene")
        return
    var game := scene.instantiate()
    root.add_child(game)
    var survivor := game.get_node_or_null("Player") as CharacterBody3D
    var zones := game.get_node_or_null("RiskZoneSystem")
    var node := game.get_node_or_null("ExclusionFiber")
    var advanced := game.get_node_or_null("ExclusionWood")
    var infected := game.get_node_or_null("InfectedWalker")
    if survivor == null or zones == null or node == null or advanced == null or infected == null:
        _fail("Playable scene missing risk system, high-risk node or infected")
        return

    # Real in-world gathering keeps tier rules and pays the area bonus.
    survivor.global_position = danger + Vector3(0.0, 0.0, 1.0)
    var amount: int = int(node.get("yield_count"))
    var before: int = int(survivor.call("get_item_count", "fiber_t1"))
    node.call("interact", survivor)
    if int(survivor.call("get_item_count", "fiber_t1")) - before != amount + 1:
        _fail("Danger-zone resource gathering did not pay the bonus")
        return
    if not bool(node.get("depleted")):
        _fail("Danger node must obey the same resource depletion rules")
        return
    # An exclusion bonus must never bypass the tier-2 skill or tool gate.
    survivor.global_position = advanced.global_position + Vector3(0.0, 0.4, 1.0)
    var advanced_before: int = int(survivor.call("get_item_count", "wood_t2"))
    advanced.call("interact", survivor)
    if bool(advanced.get("depleted")) or int(survivor.call("get_item_count", "wood_t2")) != advanced_before:
        _fail("Tier-2 harvest bypassed progression gates in exclusion zone")
        return

    survivor.set("health", 100.0)
    zones.call("_physics_process", 1.0)
    if not is_equal_approx(float(survivor.get("health")), 97.5):
        _fail("Environmental hazard did not damage the survivor")
        return

    survivor.global_position = home
    survivor.set("health", 100.0)
    zones.call("_physics_process", 1.0)
    if not is_equal_approx(float(survivor.get("health")), 100.0):
        _fail("Shelter should prevent environmental damage")
        return
    infected.global_position = home + Vector3(1.0, 0.0, 0.0)
    infected.set("strike_cooldown", 0.0)
    for frame in range(3):
        await physics_frame
    if not is_equal_approx(float(survivor.get("health")), 100.0):
        _fail("Infected struck the survivor inside the camp")
        return

    game.queue_free()
    await process_frame
    print("PASS: Days After camp protection, danger damage, resource bonus, bounds and infected shelter.")
    quit(0)
