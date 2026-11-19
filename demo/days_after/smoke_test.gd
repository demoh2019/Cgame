extends SceneTree

## Run with a built Cgame editor:
## ./bin/godot.linuxbsd.editor.x86_64 --headless --path demo/days_after --script res://smoke_test.gd

func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var scene := load("res://main.tscn") as PackedScene
    if scene == null:
        push_error("Days After main scene could not be loaded.")
        quit(1)
        return

    var game := scene.instantiate()
    root.add_child(game)
    var survivor := game.get_node_or_null("Player")
    var food := game.get_node_or_null("FoodCrate")
    var water := game.get_node_or_null("WaterCan")
    var ground := game.get_node_or_null("Ground") as StaticBody3D
    if survivor == null or food == null or water == null or ground == null:
        push_error("Missing player, interactive loot or physical ground.")
        quit(1)
        return

    food.call("interact", survivor)
    food.call("interact", survivor)
    water.call("interact", survivor)
    if survivor.call("get_item_count", "food") != 2 or survivor.call("get_item_count", "water") != 1:
        push_error("Loot was not collected exactly once.")
        quit(1)
        return

    survivor.set("hunger", 20.0)
    survivor.set("thirst", 10.0)
    survivor.call("consume_food")
    survivor.call("consume_water")
    if survivor.call("get_item_count", "food") != 1 or survivor.call("get_item_count", "water") != 0:
        push_error("Consumption did not decrement the inventory.")
        quit(1)
        return
    if float(survivor.get("hunger")) < 55.0 or float(survivor.get("thirst")) < 55.0:
        push_error("Consumption did not restore survival stats.")
        quit(1)
        return

    # New slice: resource gathering, one-time depletion, tool-gated tier 2 and crafting.
    var wood_a := game.get_node_or_null("WoodA")
    var wood_b := game.get_node_or_null("WoodB")
    var stone_a := game.get_node_or_null("StoneA")
    var fiber_a := game.get_node_or_null("FiberA")
    var fiber_b := game.get_node_or_null("FiberB")
    var fiber_t2 := game.get_node_or_null("FiberT2")
    if wood_a == null or wood_b == null or stone_a == null or fiber_a == null or fiber_b == null or fiber_t2 == null:
        push_error("Resource nodes were not created.")
        quit(1)
        return

    # Level 2 resource is locked when both tool and skill are missing.
    fiber_t2.call("interact", survivor)
    if int(survivor.call("get_item_count", "fiber_t2")) != 0 or bool(fiber_t2.get("depleted")):
        push_error("Locked resource yielded tier 2 materials.")
        quit(1)
        return

    wood_a.call("interact", survivor)
    wood_a.call("interact", survivor)  # Must not yield twice during cooldown.
    wood_b.call("interact", survivor)
    stone_a.call("interact", survivor)
    if int(survivor.call("get_item_count", "wood_t1")) != 4:
        push_error("Resource node was collected more than once.")
        quit(1)
        return
    if not bool(survivor.call("craft_recipe", "scavenger_tool")):
        push_error("Crafted tool recipe failed.")
        quit(1)
        return
    if str(survivor.get("equipped_tool")) != "scavenger_tool":
        push_error("Tool was not equipped after crafting.")
        quit(1)
        return

    fiber_a.call("interact", survivor)
    fiber_b.call("interact", survivor)
    if int(survivor.call("gathering_level", "fiber")) < 2:
        push_error("Gathering XP did not unlock the next tier.")
        quit(1)
        return
    fiber_t2.call("interact", survivor)
    if int(survivor.call("get_item_count", "fiber_t2")) != 2:
        push_error("Tier 2 node did not yield materials with skill and tool.")
        quit(1)
        return
    if not bool(survivor.call("craft_recipe", "reinforced_bandage")):
        push_error("Advanced crafting recipe failed.")
        quit(1)
        return
    survivor.set("health", 25.0)
    if not bool(survivor.call("use_bandage", "reinforced_bandage")):
        push_error("Advanced bandage could not be used.")
        quit(1)
        return
    if float(survivor.get("health")) < 85.0:
        push_error("Advanced bandage did not restore health.")
        quit(1)
        return

    # Simulate a timer timeout without a 45-second delay.
    wood_a.call("_restore")
    if bool(wood_a.get("depleted")) or not wood_a.visible:
        push_error("Regenerating resource did not restore.")
        quit(1)
        return

    for i in range(10):
        await physics_frame
    if not survivor.global_position.is_finite():
        push_error("Player transform became nonfinite.")
        quit(1)
        return

    game.queue_free()
    await process_frame
    print("PASS: Days After scene, survival, gathering, crafting, tier gates, respawn and 10 physics frames.")
    quit(0)
