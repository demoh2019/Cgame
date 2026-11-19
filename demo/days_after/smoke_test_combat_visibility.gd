extends SceneTree
## Regression: neither the player nor infected may melee through solid walls.

var failures := 0


func _expect(condition: bool, description: String) -> void:
    if not condition:
        failures += 1
        push_error("Days After combat visibility: " + description)


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var packed_scene := load("res://main.tscn") as PackedScene
    if packed_scene == null:
        push_error("Main scene failed to load.")
        quit(1)
        return
    var game := packed_scene.instantiate()
    root.add_child(game)
    var survivor: CharacterBody3D = game.get_node("Player")
    var infected: CharacterBody3D = game.get_node("InfectedWalker")
    infected.set_physics_process(false)
    infected.global_position = survivor.global_position + Vector3(0.0, 0.0, -1.5)

    var wall := StaticBody3D.new()
    wall.name = "CombatVisibilityWall"
    wall.position = survivor.global_position + Vector3(0.0, 0.0, -0.75)
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(1.5, 2.2, 0.2)
    collision.shape = shape
    wall.add_child(collision)
    game.add_child(wall)
    await physics_frame

    _expect(not bool(infected.call("can_strike_target")),
        "infected could attack through cover")
    var hp_before: float = float(infected.get("health"))
    game.call("_on_player_attacked", 12.0, 2.7)
    _expect(is_equal_approx(float(infected.get("health")), hp_before),
        "player melee damaged infected through cover")

    wall.queue_free()
    await physics_frame
    _expect(bool(infected.call("can_strike_target")),
        "infected cannot see unobstructed target")
    game.call("_on_player_attacked", 12.0, 2.7)
    _expect(float(infected.get("health")) < hp_before,
        "player cannot strike unobstructed infected")

    game.queue_free()
    await process_frame
    if failures == 0:
        print("PASS: Days After combat line-of-sight blocks walls and permits clear melee.")
    quit(0 if failures == 0 else 1)
