extends SceneTree
## Deterministic relic navigation regression, without modifying the user's save.
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_quest.gd

const QuestNavigation = preload("res://scripts/quest_navigation.gd")


func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("Relic quest smoke FAILED: " + reason)
    quit(1)


func _run() -> void:
    var player := Node3D.new()
    var near_relic := Node3D.new()
    var far_relic := Node3D.new()
    root.add_child(player)
    root.add_child(near_relic)
    root.add_child(far_relic)
    near_relic.global_position = Vector3(0.0, 0.0, -12.0)
    far_relic.global_position = Vector3(20.0, 0.0, 0.0)

    var relics: Array[Node3D] = [far_relic, near_relic]
    if QuestNavigation.closest_relic(relics, player.global_position) != near_relic:
        _fail("nearest relic selection ignored horizontal distance")
        return
    if QuestNavigation.heading(player, near_relic.global_position) != "прямо":
        _fail("forward waypoint heading is incorrect")
        return
    if not is_equal_approx(
            QuestNavigation.horizontal_distance(player.global_position, near_relic.global_position), 12.0):
        _fail("waypoint distance is incorrect")
        return

    # A local 90-degree yaw should change the relative bearing.
    player.rotation.y = PI * 0.5
    if QuestNavigation.heading(player, near_relic.global_position) != "справа":
        _fail("quest compass did not account for player rotation")
        return
    player.rotation.y = 0.0
    near_relic.queue_free()
    relics.erase(near_relic)
    if QuestNavigation.closest_relic(relics, player.global_position) != far_relic:
        _fail("next relic was not selected after previous completion")
        return

    var world := WorldPartition3D.new()
    root.add_child(world)
    if not QuestNavigation.sync_streaming_source(world, far_relic):
        _fail("quest objective did not register a source")
        return
    if not world.has_streaming_source(QuestNavigation.SOURCE_NAME):
        _fail("quest source missing after registration")
        return
    if world.get_streaming_source_priority(QuestNavigation.SOURCE_NAME) != QuestNavigation.STREAMING_PRIORITY:
        _fail("quest source did not use background priority")
        return
    if world.get_streaming_source_cell(QuestNavigation.SOURCE_NAME) != Vector2i.ZERO:
        _fail("unexpected world cell for 20m target in default 128m grid")
        return
    if not QuestNavigation.sync_streaming_source(world, null):
        _fail("clearing an objective should be supported")
        return
    if world.get_streaming_source_count() != 0:
        _fail("quest source leaked after objective completion")
        return

    print("Relic quest smoke PASSED: nearest target, bearing, distance, retarget and source cleanup")
    quit(0)
