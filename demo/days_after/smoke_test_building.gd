extends SceneTree
## Built Cgame or compatible Godot:
## godot --headless --path demo/days_after --script res://smoke_test_building.gd

const Barricade = preload("res://barricade.gd")
const Zombie = preload("res://zombie.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    call_deferred("_run")


func _check(condition: bool, reason: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        push_error("Days After building: " + reason)


func _run() -> void:
    var scene := load("res://main.tscn") as PackedScene
    if scene == null:
        _check(false, "missing main scene")
        quit(1)
        return
    var game: Node3D = scene.instantiate()
    root.add_child(game)
    var player: CharacterBody3D = game.get_node_or_null("Player") as CharacterBody3D
    var builder: Node3D = game.get_node_or_null("BarricadeBuilder") as Node3D
    if player == null or builder == null:
        _check(false, "missing player or building system in the actual game")
        quit(1)
        return

    await physics_frame
    _check(int(builder.call("active_barricades")) == 0, "starts without a barricade")
    _check(not bool(builder.call("try_build")), "cannot build without resources")
    _check(int(player.call("get_item_count", "wood_t1")) == 0, "failed build does not spend materials")

    player.call("add_item", "wood_t1", 6)
    player.call("add_item", "stone_t1", 4)
    var obstructing_body := StaticBody3D.new()
    obstructing_body.name = "BuildBlockingObstacle"
    obstructing_body.position = Vector3(0.0, 1.0, 4.0)
    var obstacle_shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(2.2, 2.0, 2.2)
    obstacle_shape.shape = box
    obstructing_body.add_child(obstacle_shape)
    game.add_child(obstructing_body)
    await physics_frame
    _check(not bool(builder.call("try_build")), "does not place through a solid obstacle")
    _check(int(player.call("get_item_count", "wood_t1")) == 6, "blocked build refunds wood")
    _check(int(player.call("get_item_count", "stone_t1")) == 4, "blocked build refunds stone")
    obstructing_body.queue_free()
    await physics_frame
    await physics_frame

    _check(bool(builder.call("try_build")), "valid empty ground permits barricade")
    _check(int(builder.call("active_barricades")) == 1, "new barricade belongs to active world")
    _check(int(player.call("get_item_count", "wood_t1")) == 3, "building spent three units of wood")
    _check(int(player.call("get_item_count", "stone_t1")) == 2, "building spent two stones")

    var wall: StaticBody3D = null
    for child in builder.get_children():
        if child.is_in_group("player_barricades"):
            wall = child as StaticBody3D
            break
    if wall == null:
        _check(false, "missing native static collision barricade")
        quit(1)
        return
    _check(wall.get_node_or_null("CollisionShape3D") != null, "barricade has live physics shape")
    _check(wall.collision_layer == 1, "barricade blocks infected on physics layer 1")
    # Allow the new StaticBody3D shape to register in the physics broadphase.
    await physics_frame
    _check(not bool(builder.call("try_build")), "overlapping second barricade is rejected")
    _check(int(player.call("get_item_count", "wood_t1")) == 3, "rejected overlapping build does not charge")

    wall.call("take_damage", 60.0)
    _check(absf(float(wall.get("health")) - 60.0) < 0.01, "barricade takes physical damage")
    wall.call("interact", player)
    _check(absf(float(wall.get("health")) - 100.0) < 0.01, "repair restores 40 durability")
    _check(int(player.call("get_item_count", "wood_t1")) == 2, "repair spends exactly one wood")
    wall.call("interact", player)
    _check(absf(float(wall.get("health")) - 120.0) < 0.01, "repair caps durability")
    _check(int(player.call("get_item_count", "wood_t1")) == 1, "second partial repair costs one wood")
    wall.call("interact", player)
    _check(int(player.call("get_item_count", "wood_t1")) == 1, "full barricade cannot waste repair resources")

    # Headless physics sim: an infected walks into the player's barricade.
    var infected: CharacterBody3D = Zombie.new()
    infected.name = "BarricadeTesterInfected"
    infected.position = Vector3(0.0, 1.05, 1.8)
    infected.set("target", player)
    game.add_child(infected)
    await physics_frame
    var before: float = float(wall.get("health"))
    for index in range(120):
        await physics_frame
        if not is_instance_valid(wall) or wall.is_queued_for_deletion():
            break
    if is_instance_valid(wall) and not wall.is_queued_for_deletion():
        _check(float(wall.get("health")) < before, "infected collision damages real barricade")
        _check(wall.global_position.is_finite(), "barricade world transform stays finite")
        wall.call("take_damage", 1000.0)
        await process_frame
        _check(int(builder.call("active_barricades")) == 0, "destroyed barricade is removed")
    else:
        _check(true, "infected collision destroyed and removed barricade")

    _check(not bool(player.call("try_spend_items", {"wood_t1": 3, "stone_t1": 5})), "atomic spending rejects unaffordable batch")
    _check(int(player.call("get_item_count", "wood_t1")) == 1, "atomic failure preserves all inventory")
    _check(not bool(player.call("try_spend_items", {"stone_t1": -1})), "invalid negative cost rejected")

    game.queue_free()
    await process_frame
    if failures > 0:
        push_error("%d of %d barricade checks failed" % [failures, checks])
        quit(1)
    else:
        print("PASS: Days After barricade building, collision, repairs, infected damage and transactions (%d checks)." % checks)
        quit(0)
