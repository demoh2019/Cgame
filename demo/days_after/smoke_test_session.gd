extends SceneTree

## <cgame-editor> --headless --path demo/days_after --script res://smoke_test_session.gd
const Session = preload("res://session_state.gd")
const TEMP_PATH := "user://days_after_world_session_test.json"


func _initialize() -> void:
    call_deferred("_run")


func _check(valid: bool, message: String) -> bool:
    if valid:
        return true
    push_error("World session regression: " + message)
    quit(1)
    return false


func _run() -> void:
    var scene := load("res://main.tscn") as PackedScene
    if not _check(scene != null, "main scene must load"):
        return
    var game := scene.instantiate() as Node3D
    root.add_child(game)
    var player := game.get_node_or_null("Player") as Node3D
    var food := game.get_node_or_null("FoodCrate") as Area3D
    var wood := game.get_node_or_null("WoodA") as Area3D
    if not _check(player != null and food != null and wood != null,
            "player, persistent pickup and respawning deposit exist"):
        return

    var initial: Dictionary = Session.snapshot(game)
    if not _check(Session.validate_snapshot(game, initial),
            "fresh game snapshot must validate"):
        return

    food.call("interact", player)
    wood.call("interact", player)
    if not _check(bool(food.get("collected")) and not food.visible
            and bool(wood.get("depleted")) and not wood.visible
            and int(player.call("get_item_count", "food")) == 2
            and int(player.call("get_item_count", "wood_t1")) == 2,
            "one-time pickups and timed deposits must change world and inventory"):
        return

    player.set("health", 65.0)
    if not _check(Session.save_session(game, TEMP_PATH), "save a combined snapshot"):
        return

    player.set("health", 17.0)
    player.set("inventory", {})
    food.call("set_collected_state", false)
    wood.call("_restore")
    if not _check(not bool(food.get("collected")) and not bool(wood.get("depleted")),
            "live world was modified after the save"):
        return

    if not _check(Session.load_session(game, TEMP_PATH), "load the same session"):
        return
    if not _check(float(player.get("health")) == 65.0
            and int(player.call("get_item_count", "food")) == 2
            and int(player.call("get_item_count", "wood_t1")) == 2
            and bool(food.get("collected")) and not food.visible
            and bool(wood.get("depleted")) and not wood.visible,
            "inventory, survivor stats, pickups and resource depletion round-trip"):
        return

    food.call("interact", player)
    wood.call("interact", player)
    if not _check(int(player.call("get_item_count", "food")) == 2
            and int(player.call("get_item_count", "wood_t1")) == 2,
            "loading must not duplicate already collected items"):
        return

    # Any invalid world or survivor field must reject the entire operation.
    var invalid: Dictionary = Session.snapshot(game)
    invalid["world"]["pickups"]["FoodCrate"] = "not-a-bool"
    if not _check(not Session.apply_snapshot(game, invalid)
            and float(player.get("health")) == 65.0
            and bool(food.get("collected")),
            "corrupt pickup data rejected without partial mutation"):
        return
    invalid = Session.snapshot(game)
    invalid["world"]["resources"]["WoodA"]["remaining_seconds"] = -10.0
    if not _check(not Session.apply_snapshot(game, invalid)
            and bool(wood.get("depleted")),
            "negative respawn time rejected without changing world"):
        return
    invalid = Session.snapshot(game)
    invalid["survivor"]["stats"]["health"] = -5.0
    if not _check(not Session.apply_snapshot(game, invalid)
            and float(player.get("health")) == 65.0
            and bool(wood.get("depleted")),
            "invalid survivor snapshot cannot mutate the world"):
        return
    invalid = Session.snapshot(game)
    invalid["world"]["pickups"]["UnknownPickup"] = false
    if not _check(not Session.apply_snapshot(game, invalid),
            "unknown world objects cannot appear in saves"):
        return

    if not _check(Session.apply_snapshot(game, initial),
            "restore world to fresh initial snapshot"):
        return
    if not _check(not bool(food.get("collected")) and food.visible
            and not bool(wood.get("depleted")) and wood.visible
            and int(player.call("get_item_count", "food")) == 0,
            "earlier snapshot restores available loot and resource state"):
        return

    var invalid_file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
    invalid_file.store_string("{this-is-not-json")
    invalid_file.close()
    if not _check(not Session.load_session(game, TEMP_PATH)
            and not bool(food.get("collected"))
            and int(player.call("get_item_count", "food")) == 0,
            "malformed JSON cannot alter a live game"):
        return

    DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))
    game.queue_free()
    await process_frame
    print("PASS: Days After session save/load, inventory, pickups, resource timers and atomic rejection.")
    quit(0)
