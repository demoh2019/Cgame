extends SceneTree
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_navigation_avoidance.gd
## Real collision raycasts make the forest stalker steer around a blocker,
## including in standalone scenes where the native stream manager is absent.

const Stalker = preload("res://scripts/forest_stalker.gd")


func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("Forest obstacle avoidance smoke FAILED: " + reason)
    quit(1)


func _run() -> void:
    var ground := StaticBody3D.new()
    ground.name = "Ground"
    ground.collision_layer = 1
    var ground_shape := CollisionShape3D.new()
    var floor_box := BoxShape3D.new()
    floor_box.size = Vector3(40, 1, 40)
    ground_shape.shape = floor_box
    ground_shape.position.y = -0.5
    ground.add_child(ground_shape)
    root.add_child(ground)

    # A wall centered directly along the enemy's line of approach. Its
    # breadth still leaves enough room to steer around either side.
    var blocker := StaticBody3D.new()
    blocker.name = "Blocker"
    blocker.collision_layer = 1
    var blocker_shape := CollisionShape3D.new()
    var wall := BoxShape3D.new()
    wall.size = Vector3(2.1, 2.5, 0.65)
    blocker_shape.shape = wall
    blocker.add_child(blocker_shape)
    root.add_child(blocker)
    blocker.global_position = Vector3(0, 1, -1.75)

    var target := Node3D.new()
    root.add_child(target)
    target.global_position = Vector3(0, 1, -7)

    var enemy := CharacterBody3D.new()
    enemy.name = "PathfindingSmokeStalker"
    enemy.set_script(Stalker)
    root.add_child(enemy)
    enemy.call("configure", "avoidance_test", target, Vector3(0, 1, 0))
    enemy.call("set_encounter_active", true)

    var start: Vector3 = enemy.global_position
    var max_sideways: float = 0.0
    for i in range(150):
        await physics_frame
        max_sideways = maxf(max_sideways, absf(enemy.global_position.x))
        if (int(enemy.get("avoidance_turns")) > 0 and max_sideways > 0.45):
            break
    if int(enemy.get("avoidance_turns")) < 1:
        _fail("forward obstacle raycast never recognized the blocking collision")
        return
    if max_sideways <= 0.45:
        _fail("obstacle detection did not change the CharacterBody3D path laterally")
        return
    if enemy.global_position.distance_to(start) < 0.6:
        _fail("enemy never moved while navigating an obstacle")
        return
    if int(enemy.get("steering_updates")) < 1:
        _fail("local steering computation did not run")
        return
    if enemy.get("streamer") != null:
        _fail("standalone obstacle test should not depend on a nav manager")
        return

    print("Obstacle avoidance smoke PASSED: real forward ray obstruction, lateral steering and active CharacterBody3D physics")
    quit(0)
