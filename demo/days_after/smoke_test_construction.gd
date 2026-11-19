extends SceneTree
## Construction, barricade destruction and offline world snapshot regression.
## Run: godot --headless --path demo/days_after --script res://smoke_test_construction.gd

const WORLD = preload("res://world_state.gd")
const TEMP_PATH := "user://days_after_defenses_test.json"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("Days After construction: " + message)
    quit(1)


func _run() -> void:
    var scene := load("res://main.tscn") as PackedScene
    if scene == null:
        _fail("Cannot load main scene")
        return
    var game := scene.instantiate()
    root.add_child(game)
    var player = game.get_node("Player")
    var construction = game.get_node("Construction")
    player.add_item("wood_t1", 6)
    player.add_item("stone_t1", 3)
    if not construction.build_nearest(player):
        _fail("Valid barricade could not be constructed")
        return
    if construction.get_built_count() != 1:
        _fail("Building did not create one barricade")
        return
    if player.get_item_count("wood_t1") != 4 or player.get_item_count("stone_t1") != 2:
        _fail("Building did not consume exactly 2 wood and 1 stone")
        return
    var barrier = construction.defenses[0]
    if barrier == null:
        _fail("Expected closest pad 0 to be occupied")
        return
    barrier.take_damage(40.0)
    if not is_equal_approx(barrier.health, 60.0):
        _fail("Barricade damage failed")
        return
    if not construction.repair_nearest(player):
        _fail("Barricade repair failed")
        return
    if not is_equal_approx(barrier.health, 95.0) or player.get_item_count("wood_t1") != 3:
        _fail("Repair cost or restoration amount incorrect")
        return

    if not WORLD.save_world(game, TEMP_PATH):
        _fail("World defense snapshot could not be saved")
        return
    barrier.take_damage(1000.0)
    if construction.get_built_count() != 0:
        _fail("Destroyed barricade still tracked")
        return
    if not WORLD.load_world(game, TEMP_PATH):
        _fail("World defense snapshot could not be loaded")
        return
    if construction.get_built_count() != 1:
        _fail("Barricade was not restored")
        return
    barrier = construction.defenses[0]
    if not is_equal_approx(barrier.health, 95.0):
        _fail("Barricade durability was not restored")
        return

    var corrupt: Dictionary = WORLD.snapshot(game)
    corrupt["structures"] = [
        {"slot": 0, "health": 10.0},
        {"slot": 0, "health": 20.0}
    ]
    if WORLD.apply_snapshot(game, corrupt):
        _fail("Duplicate slot corrupt save was accepted")
        return
    if construction.get_built_count() != 1 or not is_equal_approx(barrier.health, 95.0):
        _fail("Invalid world save partially changed defenses")
        return
    corrupt = WORLD.snapshot(game)
    corrupt["structures"] = [{"slot": 99, "health": 100.0}]
    if WORLD.apply_snapshot(game, corrupt):
        _fail("Out-of-bounds slot was accepted")
        return

    # Compatibility with version 1 saves created before shelter defenses.
    var legacy: Dictionary = WORLD.snapshot(game)
    legacy.erase("structures")
    legacy["version"] = 1
    if not WORLD.apply_snapshot(game, legacy) or construction.get_built_count() != 0:
        _fail("Legacy v1 save migration failed")
        return

    DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))
    game.queue_free()
    await process_frame
    print("PASS: Days After construction, repair, destruction, world save v2 and v1 compatibility.")
    quit(0)
