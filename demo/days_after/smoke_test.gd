extends SceneTree

## With a compiled Cgame editor:
## ./bin/godot.linuxbsd.editor.x86_64 --headless --path demo/days_after --script res://smoke_test.gd

func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("DAYS AFTER SMOKE TEST FAILED: " + reason)
    quit(1)


func _run() -> void:
    var scene := load("res://main.tscn") as PackedScene
    if scene == null:
        _fail("Main scene could not be loaded")
        return

    var game := scene.instantiate()
    root.add_child(game)
    var survivor := game.get_node_or_null("Player")
    var food := game.get_node_or_null("FoodCrate")
    var water := game.get_node_or_null("WaterCan")
    var ground := game.get_node_or_null("Ground") as StaticBody3D
    var wood := game.get_node_or_null("WoodPile")
    var stone := game.get_node_or_null("StonePile")
    var fiber_a := game.get_node_or_null("FiberPatchA")
    var fiber_b := game.get_node_or_null("FiberPatchB")
    var fiber_t2 := game.get_node_or_null("AdvancedFiber")
    if survivor == null or food == null or water == null or ground == null:
        _fail("Missing basic survival nodes")
        return
    if wood == null or stone == null or fiber_a == null or fiber_b == null or fiber_t2 == null:
        _fail("Missing gathering deposits")
        return

    # Existing survival loop must not regress.
    food.call("interact", survivor)
    food.call("interact", survivor)
    water.call("interact", survivor)
    if int(survivor.call("get_item_count", "food")) != 2:
        _fail("Food pickup was collected twice or not at all")
        return
    if int(survivor.call("get_item_count", "water")) != 1:
        _fail("Water pickup count incorrect")
        return
    survivor.set("hunger", 20.0)
    survivor.set("thirst", 10.0)
    survivor.call("consume_food")
    survivor.call("consume_water")
    if int(survivor.call("get_item_count", "food")) != 1:
        _fail("Food was not consumed")
        return
    if int(survivor.call("get_item_count", "water")) != 0:
        _fail("Water was not consumed")
        return
    if float(survivor.get("hunger")) < 55.0 or float(survivor.get("thirst")) < 55.0:
        _fail("Food/water did not restore stats")
        return

    # Tiered gathering is gated by experience and equipped tools.
    fiber_t2.call("interact", survivor)
    if bool(fiber_t2.get("depleted")):
        _fail("T2 deposit depleted without sufficient gathering skill")
        return
    fiber_a.call("interact", survivor)
    fiber_a.call("interact", survivor)
    if int(survivor.call("get_item_count", "fiber_t1")) != 2:
        _fail("Duplicate harvesting was allowed")
        return
    if int(survivor.call("gathering_level", "fiber")) != 1:
        _fail("Gathering skill increased too early")
        return
    fiber_b.call("interact", survivor)
    if int(survivor.call("gathering_level", "fiber")) < 2:
        _fail("Gathering experience did not unlock tier 2")
        return
    fiber_t2.call("interact", survivor)
    if bool(fiber_t2.get("depleted")):
        _fail("T2 deposit depleted without a crafted tool")
        return

    wood.call("interact", survivor)
    stone.call("interact", survivor)
    if not bool(survivor.call("craft_recipe", "scavenger_tool")):
        _fail("Could not craft a scavenger tool from gathered materials")
        return
    if str(survivor.get("equipped_tool")) != "scavenger_tool":
        _fail("Crafting did not equip the progression tool")
        return
    if bool(survivor.call("craft_recipe", "scavenger_tool")):
        _fail("Tool was crafted without sufficient resources")
        return
    fiber_t2.call("interact", survivor)
    fiber_t2.call("interact", survivor)
    if int(survivor.call("get_item_count", "fiber_t2")) != 3:
        _fail("Advanced resource yield incorrect or repeatable")
        return

    # Crafting consumes the right tier of ingredients and grants real healing.
    if not bool(survivor.call("craft_recipe", "field_bandage")):
        _fail("Basic bandage recipe failed")
        return
    if int(survivor.call("get_item_count", "fiber_t1")) != 2:
        _fail("Basic recipe ingredient debit incorrect")
        return
    survivor.set("health", 30.0)
    if not bool(survivor.call("use_bandage", "field_bandage")):
        _fail("Could not use crafted basic bandage")
        return
    if float(survivor.get("health")) != 60.0:
        _fail("Basic bandage healing incorrect")
        return
    if not bool(survivor.call("craft_recipe", "reinforced_bandage")):
        _fail("Advanced bandage recipe failed")
        return
    if not bool(survivor.call("use_bandage", "reinforced_bandage")):
        _fail("Could not use crafted advanced bandage")
        return
    if float(survivor.get("health")) != 100.0:
        _fail("Advanced bandage healing exceeded or missed health cap")
        return
    if int(survivor.get("crafting_xp")) != 60:
        _fail("Crafting experience not awarded correctly")
        return

    for i in range(10):
        await physics_frame
    if not survivor.global_position.is_finite():
        _fail("Player transform became nonfinite")
        return
    game.queue_free()
    await process_frame
    print("PASS: survival, pickup deduplication, T1->T2 gathering, tool gating, crafting, healing and 10 physics frames.")
    quit(0)
