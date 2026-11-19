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
    if int(survivor.get("food_count")) != 2 or int(survivor.get("water_count")) != 1:
        push_error("Loot was not collected exactly once.")
        quit(1)
        return

    survivor.set("hunger", 20.0)
    survivor.set("thirst", 10.0)
    survivor.call("consume_food")
    survivor.call("consume_water")
    if int(survivor.get("food_count")) != 1 or int(survivor.get("water_count")) != 0:
        push_error("Consumption did not decrement the inventory.")
        quit(1)
        return
    if float(survivor.get("hunger")) < 55.0 or float(survivor.get("thirst")) < 55.0:
        push_error("Consumption did not restore survival stats.")
        quit(1)
        return

    for node_name in ["WoodPileA", "WoodPileB", "WoodPileC", "StonePileA", "StonePileB"]:
        var materials = game.get_node_or_null(node_name)
        if materials == null:
            push_error("Missing crafting material pickup: " + node_name)
            quit(1)
            return
        materials.call("interact", survivor)
    if int(survivor.get("wood_count")) != 3 or int(survivor.get("stone_count")) != 2:
        push_error("Materials did not reach inventory.")
        quit(1)
        return
    if not bool(game.call("_craft_campfire")) or game.get_node_or_null("Campfire_1") == null:
        push_error("Campfire recipe did not create a world object.")
        quit(1)
        return
    if int(survivor.get("wood_count")) != 0 or int(survivor.get("stone_count")) != 0:
        push_error("Crafting did not consume materials.")
        quit(1)
        return
    if bool(game.call("_craft_campfire")):
        push_error("Crafting succeeded without resources.")
        quit(1)
        return
    var cycle = game.get_node_or_null("DayNight")
    if cycle == null:
        push_error("Day/night controller is missing.")
        quit(1)
        return
    cycle.call("advance", 240.0)
    if int(cycle.get("day_number")) != 2:
        push_error("Day/night progression failed.")
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
    print("PASS: Days After scene, pickups, survival, inventory and 10 physics frames.")
    quit(0)
