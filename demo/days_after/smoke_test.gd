extends SceneTree
## Run with a built Cgame editor:
## godot --headless --path demo/days_after --script res://smoke_test.gd

const SurvivalState = preload("res://survival_state.gd")


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var stats = SurvivalState.new()
    stats.advance(10.0, true)
    if stats.hunger >= 100.0 or stats.thirst >= 100.0 or stats.stamina >= 100.0:
        _fail("Needs and sprint stamina must drain.")
        return
    if not stats.replenish("water", 1000.0) or stats.thirst != 100.0:
        _fail("Drinking must restore and clamp thirst.")
        return
    if stats.replenish("invalid", 20.0):
        _fail("Unknown supplies must be rejected.")
        return
    stats.hunger = 0.0
    stats.advance(2.0, false)
    if stats.health >= 100.0:
        _fail("Starvation must damage health.")
        return

    var packed := load("res://main.tscn") as PackedScene
    if packed == null:
        _fail("Cannot load the Days After scene.")
        return
    var level := packed.instantiate()
    root.add_child(level)
    await process_frame
    var player = level.get_node_or_null("Player")
    var supplies := get_nodes_in_group("days_after_supplies")
    if player == null or supplies.size() != 4:
        _fail("Expected player and four resource pickups.")
        return
    var pickup: Node = supplies[0]
    var kind: String = pickup.get("kind")
    var amount: int = pickup.get("amount")
    pickup.call("collect", player)
    await process_frame
    if int(player.inventory[kind]) != amount or is_instance_valid(pickup):
        _fail("Pickup must transfer items exactly once and disappear.")
        return
    player.state.hunger = 50.0
    player.add_supply("food", 1)
    if not player.consume("food") or player.state.hunger <= 50.0:
        _fail("Food consumption must restore hunger.")
        return
    level.queue_free()
    await process_frame
    print("PASS: Days After survival state, playable scene, loot and consumption.")
    quit(0)


func _fail(message: String) -> void:
    push_error("Days After smoke test: " + message)
    quit(1)
