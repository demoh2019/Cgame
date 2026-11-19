extends SceneTree
## Built Cgame: --headless --path demo/days_after --script res://smoke_test_saves.gd

const Saves = preload("res://save_state.gd")
const TEMP_PATH := "user://days_after_save_test.json"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("Days After save regression: " + message)
    quit(1)


func _run() -> void:
    var scene := load("res://main.tscn") as PackedScene
    if scene == null:
        _fail("Missing game scene.")
        return
    var game := scene.instantiate()
    root.add_child(game)
    var survivor := game.get_node_or_null("Player") as Node3D
    if survivor == null:
        _fail("Missing survivor.")
        return

    survivor.set("health", 74.0)
    survivor.set("hunger", 55.0)
    survivor.set("thirst", 31.0)
    survivor.call("add_item", "wood_t1", 5)
    survivor.call("add_item", "scavenger_tool", 1)
    survivor.set("equipped_tool", "scavenger_tool")
    survivor.set("crafting_xp", 71)
    survivor.set("combat_xp", 23)
    var gathering: Dictionary = survivor.get("gathering_xp")
    gathering["wood"] = 95
    survivor.global_position = Vector3(2.0, 2.0, 4.0)

    if not Saves.save_player(survivor, TEMP_PATH):
        _fail("Cannot write a valid save.")
        return
    survivor.set("health", 13.0)
    survivor.set("hunger", 10.0)
    survivor.set("inventory", {})
    survivor.set("equipped_tool", "")
    survivor.set("crafting_xp", 0)
    survivor.global_position = Vector3.ZERO
    if not Saves.load_player(survivor, TEMP_PATH):
        _fail("Cannot load a valid save.")
        return
    if survivor.get("health") != 74.0 or survivor.get("hunger") != 55.0:
        _fail("Survival stats did not round-trip.")
        return
    if int(survivor.call("get_item_count", "wood_t1")) != 5 or str(survivor.get("equipped_tool")) != "scavenger_tool":
        _fail("Inventory or equipment did not round-trip.")
        return
    if int(survivor.get("crafting_xp")) != 71 or int(survivor.get("combat_xp")) != 23:
        _fail("Progression did not round-trip.")
        return
    if int((survivor.get("gathering_xp") as Dictionary)["wood"]) != 95:
        _fail("Gathering skill did not round-trip.")
        return
    if survivor.global_position != Vector3(2.0, 2.0, 4.0):
        _fail("Position did not round-trip.")
        return

    var corrupt: Dictionary = Saves.snapshot(survivor)
    corrupt["version"] = 999
    if Saves.apply_snapshot(survivor, corrupt):
        _fail("Unknown version must be rejected.")
        return
    corrupt = Saves.snapshot(survivor)
    corrupt["inventory"]["wood_t1"] = -10
    if Saves.apply_snapshot(survivor, corrupt):
        _fail("Negative inventory must be rejected.")
        return
    if int(survivor.call("get_item_count", "wood_t1")) != 5:
        _fail("Invalid save must never partially mutate the player.")
        return

    DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))
    game.queue_free()
    await process_frame
    print("PASS: survivor save/load, equipment, professions, validation, atomic rejection.")
    quit(0)
