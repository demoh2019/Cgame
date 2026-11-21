extends SceneTree
## <cgame-editor> --headless --path demo/days_after --script res://smoke_test_minimap.gd

const Minimap = preload("res://minimap.gd")


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("Minimap regression: " + message)
    quit(1)


func _run() -> void:
    var mapped := Minimap.world_to_map(Vector3(12, 40, -12), 24.0, Vector2(200, 200))
    if mapped.distance_to(Vector2(146, 54)) > 0.001:
        _fail("North-up world-to-minimap conversion is incorrect.")
        return
    if not Minimap.inside_radius(Vector3(12, 300, -12), 24.0):
        _fail("Map radius should depend on horizontal ground distance only.")
        return
    if Minimap.inside_radius(Vector3(25, 0, 0), 24.0):
        _fail("Out-of-range entity must be hidden.")
        return

    var packed := load("res://main.tscn") as PackedScene
    if packed == null:
        _fail("Cannot load game scene.")
        return
    var game := packed.instantiate()
    root.add_child(game)
    await process_frame
    await process_frame

    var overlay := game.get_node_or_null("MinimapOverlay") as CanvasLayer
    var map := game.get_node_or_null("MinimapOverlay/Minimap") as Control
    var player := game.get_node_or_null("Player") as Node3D
    if overlay == null or map == null or player == null:
        _fail("Missing live map, overlay or player.")
        return
    if map.get("survivor") != player or map.get("world") != game:
        _fail("Map is not tracking the live game scene.")
        return
    if not map.visible:
        _fail("Minimap must start enabled.")
        return

    var key := InputEventKey.new()
    key.physical_keycode = KEY_M
    key.pressed = true
    overlay.call("_unhandled_input", key)
    if map.visible:
        _fail("M must hide the minimap.")
        return
    overlay.call("_unhandled_input", key)
    if not map.visible:
        _fail("M must show the minimap.")
        return

    game.queue_free()
    await process_frame
    print("PASS: tactical minimap world coordinates, range, live tracking and toggle.")
    quit(0)
