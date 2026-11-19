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
    if int(survivor.call("get_item_count", "food")) != 2 or int(survivor.call("get_item_count", "water")) != 1:
        push_error("Loot was not collected exactly once.")
        quit(1)
        return

    survivor.set("hunger", 20.0)
    survivor.set("thirst", 10.0)
    survivor.call("consume_food")
    survivor.call("consume_water")
    if int(survivor.call("get_item_count", "food")) != 1 or int(survivor.call("get_item_count", "water")) != 0:
        push_error("Consumption did not decrement the inventory.")
        quit(1)
        return
    if float(survivor.get("hunger")) < 55.0 or float(survivor.get("thirst")) < 55.0:
        push_error("Consumption did not restore survival stats.")
        quit(1)
        return

    var wood = game.get_node_or_null("TimberA")
    var wood_b = game.get_node_or_null("TimberB")
    var stone = game.get_node_or_null("StoneA")
    if wood == null or wood_b == null or stone == null:
        push_error("Missing tier-one harvesting deposits.")
        quit(1)
        return
    for deposit in [wood, wood_b, stone]:
        deposit.call("interact", survivor)
    if int(survivor.call("get_item_count", "wood_t1")) != 4:
        push_error("Tier-one wood gathering did not populate the inventory.")
        quit(1)
        return
    if not bool(game.call("_craft_campfire")) or game.get_node_or_null("Campfire_1") == null:
        push_error("Campfire crafting failed.")
        quit(1)
        return
    if int(survivor.call("get_item_count", "wood_t1")) != 1:
        push_error("Campfire crafting did not consume wood.")
        quit(1)
        return
    if bool(game.call("_craft_campfire")):
        push_error("Campfire crafting incorrectly ignored missing stone.")
        quit(1)
        return
    var clock = game.get_node_or_null("DayNight")
    if clock == null:
        push_error("Day/night controller is missing.")
        quit(1)
        return
    clock.call("advance", 240.0)
    if int(clock.get("day_number")) != 2:
        push_error("Day/night controller did not reach day two.")
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
