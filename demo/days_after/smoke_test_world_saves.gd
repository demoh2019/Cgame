extends SceneTree
## Built Cgame: --headless --path demo/days_after --script res://smoke_test_world_saves.gd

const Saves = preload("res://save_state.gd")
const TEMP_PATH := "user://days_after_world_save_test.json"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("Days After world persistence: " + message)
    quit(1)


func _run() -> void:
    var scene := load("res://main.tscn") as PackedScene
    if scene == null:
        _fail("Cannot load game scene")
        return
    var game := scene.instantiate()
    root.add_child(game)
    var survivor := game.get_node_or_null("Player") as Node3D
    var food := game.get_node_or_null("FoodCrate") as Area3D
    var wood := game.get_node_or_null("WoodA") as Area3D
    if survivor == null or food == null or wood == null:
        _fail("Expected the survivor, food and a gathering deposit")
        return

    food.call("interact", survivor)
    wood.call("interact", survivor)
    var snapshot: Dictionary = Saves.snapshot(survivor)
    if not Saves.validate_snapshot(snapshot):
        _fail("New world snapshot failed validation")
        return
    if not bool(snapshot["world"]["pickups"]["FoodCrate"]):
        _fail("Collected supply crate was not recorded")
        return
    if not bool(snapshot["world"]["resources"]["WoodA"]["depleted"]):
        _fail("Harvested wood node was not recorded")
        return
    var remaining: float = float(snapshot["world"]["resources"]["WoodA"]["remaining"])
    if remaining <= 0.0 or remaining > 45.0:
        _fail("Resource respawn time was not saved")
        return

    food.call("set_collected_state", false)
    wood.call("set_depleted_state", false, 0.0)
    survivor.set("health", 46.0)
    survivor.set("inventory", {})
    if not Saves.apply_snapshot(survivor, snapshot):
        _fail("Could not apply a valid world snapshot")
        return
    if not bool(food.get("collected")) or not bool(wood.get("depleted")):
        _fail("Loot/resource depletion did not round-trip")
        return
    if int(survivor.call("get_item_count", "food")) != 2 or int(survivor.call("get_item_count", "wood_t1")) != 2:
        _fail("Survivor loot and resource inventory did not round-trip")
        return

    var invalid: Dictionary = snapshot.duplicate(true)
    invalid["world"]["pickups"]["UnknownWorldNode"] = true
    survivor.set("health", 53.0)
    if Saves.apply_snapshot(survivor, invalid):
        _fail("Unknown world objects must be rejected")
        return
    if float(survivor.get("health")) != 53.0 or not bool(wood.get("depleted")):
        _fail("Invalid world data partially changed live state")
        return

    invalid = snapshot.duplicate(true)
    invalid["world"]["resources"]["WoodA"]["remaining"] = -12.0
    if Saves.apply_snapshot(survivor, invalid):
        _fail("Negative resource respawn timers must be rejected")
        return

    # Legacy saves remain usable without rewriting the world's resource nodes.
    var legacy: Dictionary = snapshot.duplicate(true)
    legacy.erase("world")
    legacy["version"] = 1
    food.call("set_collected_state", false)
    if not Saves.apply_snapshot(survivor, legacy):
        _fail("Version 1 survivor save failed to load")
        return
    if bool(food.get("collected")):
        _fail("Old survivor-only saves should not mutate world objects")
        return

    if not Saves.apply_snapshot(survivor, snapshot):
        _fail("Could not restore the world before disk testing")
        return
    if not Saves.save_player(survivor, TEMP_PATH):
        _fail("Could not write world and survivor state to disk")
        return
    food.call("set_collected_state", false)
    wood.call("set_depleted_state", false, 0.0)
    survivor.set("inventory", {})
    if not Saves.load_player(survivor, TEMP_PATH):
        _fail("Could not reload the saved world from disk")
        return
    if not bool(food.get("collected")) or not bool(wood.get("depleted")):
        _fail("Disk load did not restore the world")
        return

    DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))
    game.queue_free()
    await process_frame
    print("PASS: Days After survivor/world snapshot, respawn timer, v1 compatibility and atomic corruption rejection.")
    quit(0)
