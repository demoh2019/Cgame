extends SceneTree
## Run: godot --headless --path demo/days_after --script res://smoke_test.gd

func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var scene := load("res://main.tscn") as PackedScene
    if scene == null:
        push_error("Days After main scene failed to load.")
        quit(1)
        return

    var game := scene.instantiate()
    root.add_child(game)
    await physics_frame
    await physics_frame

    var player = game.get_node_or_null("Player")
    var hud := game.get_node_or_null("SurvivalHUD/Status")
    if player == null or hud == null:
        push_error("Survivor or survival HUD missing.")
        quit(1)
        return

    var zombies := get_nodes_in_group("zombies")
    if zombies.size() != 6 or get_nodes_in_group("loot").size() < 6:
        push_error("Expected six zombies and at least six resource pickups.")
        quit(1)
        return

    var old_water: int = int(player.inventory.get("water", 0))
    game.call("spawn_pickup", "water", 3, player.global_position + Vector3(1.0, 0.0, 0.0))
    if not game.call("collect_nearest_loot") or int(player.inventory.get("water", 0)) != old_water + 3:
        push_error("Nearby resource collection failed.")
        quit(1)
        return
    if not player.consume("water") or int(player.inventory.get("water", 0)) != old_water + 2:
        push_error("Consumable inventory logic failed.")
        quit(1)
        return

    zombies[0].call("take_damage", 200.0)
    if game.kills != 1:
        push_error("Zombie death counter failed.")
        quit(1)
        return

    player.take_damage(20.0)
    if player.health != 80.0:
        push_error("Survivor damage model failed.")
        quit(1)
        return

    await physics_frame
    print("PASS: Days After scene, survival HUD, zombie AI, loot, consumables and damage.")
    quit(0)
