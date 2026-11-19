extends SceneTree
## Run: godot --headless --path games/days_after --script res://smoke_test_save.gd
## Regression: checkpoint round-trip, entity depletion, invalid and hostile inputs.

const SAVE = preload("res://save_game.gd")
const TEST_PATH: String = "user://days_after_checkpoint_smoke.json"


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var scene := load("res://main.tscn") as PackedScene
    if scene == null:
        push_error("Cannot load playable Days After scene")
        quit(1)
        return
    var game := scene.instantiate() as Node3D
    root.add_child(game)
    for step in range(3):
        await physics_frame

    var ok := true
    var survivor := game.get_node("Survivor") as CharacterBody3D
    var food := game.get_node("FoodRation") as Area3D
    var timber := game.get_node("FallenTimber") as Area3D
    var infected := game.get_node("InfectedScavenger") as CharacterBody3D
    var state = game.get("state")

    game.call("_on_interact", food)
    for charge in range(int(timber.get("max_charges"))):
        game.call("_on_interact", timber)
    infected.call("take_damage", 1000.0)
    state.add_resource("scrap", 2)
    state.add_resource("wood", 2)
    state.craft("makeshift_spear")
    state.equip("makeshift_spear")
    state.apply_damage(15.0)
    survivor.global_position = Vector3(5.0, 0.15, 5.0)
    if food.visible or timber.visible or infected.visible:
        push_error("Collected resources or dead infected remain visible")
        ok = false

    var expected: Dictionary = SAVE.capture(game)
    if not game.call("save_game", TEST_PATH):
        push_error("Checkpoint write failed")
        ok = false

    # Mutate every major state category; loading must restore the exact snapshot.
    state.health = 4.0
    state.inventory["food"] = 25
    state.inventory["makeshift_spear"] = 0
    state.equipped["weapon"] = ""
    state.experience["crafting"] = 0
    survivor.global_position = Vector3(-6.0, 1.0, -7.0)
    food.call("restore_collected", false)
    timber.call("restore_charges", timber.get("max_charges"))
    infected.call("restore_health", 55.0)
    infected.global_position = Vector3(10.0, 2.0, 10.0)

    if not game.call("load_game", TEST_PATH):
        push_error("Checkpoint read failed")
        ok = false
    if SAVE.capture(game) != expected:
        push_error("Checkpoint round-trip lost world, equipment or survivor data")
        ok = false
    if bool(food.get("_collected")) == false or int(timber.get("charges")) != 0 or float(infected.get("health")) != 0.0:
        push_error("Restored depleted world entities became farmable again")
        ok = false
    if food.call("collect") != {} or timber.call("collect") != {}:
        push_error("Depleted entities can be looted twice")
        ok = false

    var preserved: Dictionary = SAVE.capture(game)
    var corrupt := preserved.duplicate(true)
    corrupt["version"] = 99
    if not _write_json(corrupt) or game.call("load_game", TEST_PATH):
        push_error("Unknown checkpoint schema was accepted")
        ok = false
    if SAVE.capture(game) != preserved:
        push_error("Invalid schema partially mutated the world")
        ok = false

    corrupt = preserved.duplicate(true)
    corrupt["state"]["inventory"]["wood"] = -999
    if not _write_json(corrupt) or game.call("load_game", TEST_PATH):
        push_error("Negative item stack was accepted")
        ok = false

    corrupt = preserved.duplicate(true)
    corrupt["resources"]["FallenTimber"] = 5000
    if not _write_json(corrupt) or game.call("load_game", TEST_PATH):
        push_error("Resource duplication save was accepted")
        ok = false

    corrupt = preserved.duplicate(true)
    corrupt["state"]["equipped"]["weapon"] = "unknown_item"
    if not _write_json(corrupt) or game.call("load_game", TEST_PATH):
        push_error("Unknown equipment ID was accepted")
        ok = false
    if SAVE.capture(game) != preserved:
        push_error("Rejected checkpoint changed valid state")
        ok = false

    var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
    if file == null:
        push_error("Could not create truncated test save")
        ok = false
    else:
        file.store_string("{ truncated")
        file.close()
        if game.call("load_game", TEST_PATH):
            push_error("Truncated checkpoint was accepted")
            ok = false
    if SAVE.capture(game) != preserved:
        push_error("Truncated checkpoint mutated game state")
        ok = false

    DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + ".tmp"))
    game.queue_free()
    await process_frame
    if ok:
        print("PASS: checkpoint round-trip, finite loot, defeated enemies, schema and tamper guards")
    quit(0 if ok else 1)


func _write_json(value: Dictionary) -> bool:
    var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(value))
    file.close()
    return true
