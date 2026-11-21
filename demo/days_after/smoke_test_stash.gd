extends SceneTree
## godot --headless --path demo/days_after --script res://smoke_test_stash.gd
const WORLD_SAVE = preload("res://world_state.gd")
const TEMP_PATH := "user://days_after_world_stash_test.json"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("Days After shelter regression: " + message)
    quit(1)


func _run() -> void:
    var scene := load("res://main.tscn") as PackedScene
    if scene == null:
        _fail("Main scene could not be loaded")
        return
    var game := scene.instantiate()
    root.add_child(game)
    var survivor = game.get_node_or_null("Player")
    var stash = game.get_node_or_null("ShelterStash")
    if survivor == null or stash == null:
        _fail("Survivor or stash not found")
        return

    survivor.call("add_item", "wood_t1", 5)
    if not stash.deposit(survivor, "wood_t1", 3):
        _fail("Deposit rejected a valid stack")
        return
    if survivor.get_item_count("wood_t1") != 2 or stash.get_storage_count("wood_t1") != 3:
        _fail("Deposit did not conserve items")
        return
    if not stash.withdraw(survivor, "wood_t1", 1):
        _fail("Withdrawal rejected a valid stack")
        return
    if survivor.get_item_count("wood_t1") != 3 or stash.get_storage_count("wood_t1") != 2:
        _fail("Withdrawal did not conserve items")
        return
    if stash.withdraw(survivor, "wood_t1", 100) or stash.deposit(survivor, "wood_t1", -1):
        _fail("Invalid transfers were accepted")
        return

    survivor.call("add_item", "rusty_spear", 1)
    if not survivor.equip_item("weapon", "rusty_spear"):
        _fail("Could not equip test spear")
        return
    if stash.deposit(survivor, "rusty_spear", 1):
        _fail("Stored a weapon still equipped")
        return

    survivor.health = 63.0
    if not WORLD_SAVE.save_world(game, TEMP_PATH):
        _fail("Could not save player and stash")
        return
    survivor.health = 12.0
    survivor.inventory.clear()
    stash.stacks.clear()
    if not WORLD_SAVE.load_world(game, TEMP_PATH):
        _fail("Could not reload player and stash")
        return
    if not is_equal_approx(survivor.health, 63.0):
        _fail("Health was not restored")
        return
    if survivor.get_item_count("wood_t1") != 3 or stash.get_storage_count("wood_t1") != 2:
        _fail("Stash or inventory did not round trip")
        return
    if survivor.equipped_weapon != "rusty_spear":
        _fail("Equipment did not round trip")
        return

    var corrupt: Dictionary = WORLD_SAVE.snapshot(game)
    corrupt["stash"] = {"wood_t1": -5}
    if WORLD_SAVE.apply_snapshot(game, corrupt):
        _fail("Invalid stash save was accepted")
        return
    if survivor.health != 63.0 or stash.get_storage_count("wood_t1") != 2:
        _fail("Corrupt save partially applied")
        return
    corrupt = WORLD_SAVE.snapshot(game)
    corrupt["player"]["stats"]["health"] = 120.0
    if WORLD_SAVE.apply_snapshot(game, corrupt):
        _fail("Invalid player save was accepted")
        return

    DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))
    game.queue_free()
    await process_frame
    print("PASS: Days After shelter stash, safe transfers, equipment guard, world save/load and invalid snapshots.")
    quit(0)
