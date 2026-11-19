extends SceneTree

## Headless integration: single Days After game combining survival and
## classless gathering/crafting progression.
## Run: cgame --headless --path demo/days_after --script res://smoke_test.gd

var failures := 0


func _initialize() -> void:
    call_deferred("_run")


func _check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        push_error("Days After integration: " + message)


func _run() -> void:
    var scene := load("res://main.tscn") as PackedScene
    if scene == null:
        push_error("Failed to load Days After main.tscn")
        quit(1)
        return

    var game := scene.instantiate()
    root.add_child(game)
    var player = game.get_node_or_null("Player")
    var food = game.get_node_or_null("FoodCrate")
    var water = game.get_node_or_null("WaterCan")
    var wood_a = game.get_node_or_null("WoodPileA")
    var wood_b = game.get_node_or_null("WoodPileB")
    var stone = game.get_node_or_null("StonePileA")
    var fiber = game.get_node_or_null("FiberPatchA")
    var tier_two = game.get_node_or_null("WoodTier2")
    _check(player != null, "missing playable survivor")
    _check(food != null and water != null, "missing basic survival pickups")
    _check(wood_a != null and wood_b != null and stone != null and fiber != null,
            "missing level-one gathering nodes")
    _check(tier_two != null, "missing tier-two gathering goal")
    _check(game.get_node_or_null("Ground") is StaticBody3D, "missing collidable world")
    _check(InputMap.has_action("craft_tool"), "crafting input not registered")
    _check(InputMap.has_action("craft_bandage"), "bandage input not registered")
    if failures > 0:
        game.queue_free()
        quit(1)
        return

    food.call("interact", player)
    food.call("interact", player)
    water.call("interact", player)
    _check(int(player.call("get_item_count", "food")) == 2,
            "food should transfer exactly once")
    _check(int(player.call("get_item_count", "water")) == 1,
            "water should transfer")

    player.set("hunger", 20.0)
    player.set("thirst", 10.0)
    player.call("consume_food")
    player.call("consume_water")
    _check(int(player.call("get_item_count", "food")) == 1, "food cost was wrong")
    _check(int(player.call("get_item_count", "water")) == 0, "water cost was wrong")
    _check(is_equal_approx(float(player.get("hunger")), 55.0),
            "eating should restore 35 hunger")
    _check(is_equal_approx(float(player.get("thirst")), 55.0),
            "drinking should restore 45 thirst")

    # A high-tier node must remain in the world when the player cannot harvest it.
    tier_two.call("interact", player)
    _check(not bool(tier_two.get("depleted")), "T2 resource bypassed progression gate")
    _check(int(player.call("get_item_count", "wood_t2")) == 0,
            "T2 resource was granted without the skill and tool")

    wood_a.call("interact", player)
    wood_b.call("interact", player)
    stone.call("interact", player)
    fiber.call("interact", player)
    _check(int(player.call("get_item_count", "wood_t1")) == 4,
            "wood gather count wrong")
    _check(int(player.call("gathering_level", "wood")) >= 2,
            "wood profession did not level up")
    _check(int(player.call("get_item_count", "stone_t1")) == 2,
            "stone gather count wrong")
    _check(int(player.call("get_item_count", "fiber_t1")) == 2,
            "fiber gather count wrong")
    _check(not bool(tier_two.get("depleted")),
            "locked deposit should remain harvestable later")

    _check(bool(player.call("craft_recipe", "scavenger_tool")),
            "tool cannot be crafted from harvested supplies")
    _check(str(player.get("equipped_tool")) == "scavenger_tool",
            "crafted tool should equip")
    tier_two.call("interact", player)
    _check(bool(tier_two.get("depleted")), "T2 deposit should now be harvestable")
    _check(int(player.call("get_item_count", "wood_t2")) == 2,
            "T2 resource quantity wrong")

    _check(bool(player.call("craft_recipe", "field_bandage")),
            "field bandage should craft from gathered fiber")
    _check(not bool(player.call("craft_recipe", "field_bandage")),
            "crafting should not succeed when ingredients are gone")
    player.set("health", 60.0)
    _check(bool(player.call("use_bandage", "field_bandage")), "bandage use failed")
    _check(is_equal_approx(float(player.get("health")), 90.0),
            "bandage should heal by 30")
    _check(int(player.call("get_item_count", "field_bandage")) == 0,
            "used bandage must be consumed")

    for frame in range(10):
        await physics_frame
    _check((player as Node3D).global_position.is_finite(),
            "player transform became nonfinite")

    game.queue_free()
    await process_frame
    if failures == 0:
        print("PASS: survival, loot, tiered professions, crafting, equipment, and physics.")
    quit(0 if failures == 0 else 1)
