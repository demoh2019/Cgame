extends SceneTree
## Regression: infection, crafting, treatment, legacy saves and corrupt snapshots.

const RULES = preload("res://infection.gd")
const SAVES = preload("res://save_state.gd")
const TEMP_PATH := "user://days_after_infection_test.json"


func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("Infection regression failed: " + reason)
    quit(1)


func _run() -> void:
    if not is_equal_approx(RULES.expose(95.0, 18.0), 100.0):
        _fail("Exposure must clamp to 100.")
        return
    if not is_equal_approx(RULES.expose(15.0, -2.0), 15.0):
        _fail("Invalid negative exposure changed state.")
        return
    if not is_equal_approx(float(RULES.advance(70.0, -1.0)["damage"]), 0.0):
        _fail("Negative delta caused damage.")
        return
    if not is_equal_approx(float(RULES.advance(40.0, 1.0)["damage"]), 0.0):
        _fail("Low infection caused health damage.")
        return
    if float(RULES.advance(75.0, 1.0)["damage"]) <= 0.0:
        _fail("Symptomatic infection caused no damage.")
        return

    var packed: PackedScene = load("res://main.tscn")
    if packed == null:
        _fail("Main scene missing.")
        return
    var game := packed.instantiate()
    root.add_child(game)
    var survivor := game.get_node_or_null("Player") as CharacterBody3D
    if survivor == null:
        _fail("Survivor missing.")
        return
    survivor.set_physics_process(false)

    survivor.call("expose_to_infection", 72.0)
    if not is_equal_approx(float(survivor.get("infection")), 72.0):
        _fail("Survivor infection was not applied.")
        return
    if bool(survivor.call("use_antiseptic")):
        _fail("Using non-owned medicine succeeded.")
        return

    survivor.call("add_item", "fiber_t1", 2)
    if bool(survivor.call("craft_recipe", "antiseptic")):
        _fail("Missing water should block crafting atomically.")
        return
    if int(survivor.call("get_item_count", "fiber_t1")) != 2:
        _fail("Failed crafting spent ingredients.")
        return
    survivor.call("add_item", "water", 1)
    if not bool(survivor.call("craft_recipe", "antiseptic")):
        _fail("Antiseptic could not be crafted.")
        return
    if int(survivor.call("get_item_count", "antiseptic")) != 1:
        _fail("Crafted item was not added.")
        return
    if not bool(survivor.call("use_antiseptic")):
        _fail("Antiseptic could not be consumed.")
        return
    if not is_equal_approx(float(survivor.get("infection")), 17.0):
        _fail("Treatment did not reduce infection by 55.")
        return
    if int(survivor.call("get_item_count", "antiseptic")) != 0:
        _fail("Treatment did not consume exactly one item.")
        return

    survivor.set("infection", 81.0)
    if not SAVES.save_player(survivor, TEMP_PATH):
        _fail("Saving infection failed.")
        return
    survivor.set("infection", 0.0)
    if not SAVES.load_player(survivor, TEMP_PATH):
        _fail("Loading infection failed.")
        return
    if not is_equal_approx(float(survivor.get("infection")), 81.0):
        _fail("Infection was not restored.")
        return

    var bad: Dictionary = SAVES.snapshot(survivor)
    bad["stats"]["infection"] = 200.0
    if SAVES.apply_snapshot(survivor, bad):
        _fail("Corrupt infection must be rejected.")
        return
    if not is_equal_approx(float(survivor.get("infection")), 81.0):
        _fail("Corrupt save partially changed survivor.")
        return

    var old: Dictionary = SAVES.snapshot(survivor)
    old["stats"].erase("infection")
    if not SAVES.apply_snapshot(survivor, old):
        _fail("Older version-1 save must remain compatible.")
        return
    if not is_equal_approx(float(survivor.get("infection")), 0.0):
        _fail("Legacy save did not reset absent infection.")
        return

    DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))
    game.queue_free()
    await process_frame
    print("PASS: Days After infection exposure, crafting, treatment and legacy save compatibility.")
    quit(0)
