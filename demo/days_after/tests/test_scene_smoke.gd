extends SceneTree
## Lightweight scene integration smoke: scene, player, resource deposits and labels.

func _initialize() -> void:
    call_deferred("_verify")


func _verify() -> void:
    var packed_scene: PackedScene = load("res://main.tscn")
    assert(packed_scene != null)
    var scene := packed_scene.instantiate()
    root.add_child(scene)
    for i in range(5):
        await physics_frame
    assert(scene != null and is_instance_valid(scene))
    assert(scene.get_node_or_null("Survivor") is CharacterBody3D)
    assert(get_nodes_in_group("days_after_resource").size() == 8)
    assert(get_nodes_in_group("days_after_loot").size() == 5)
    for node in get_nodes_in_group("days_after_resource"):
        assert(node is StaticBody3D)
        assert(not bool(node.get_meta("depleted", true)))
        assert(node.get_node("RespawnTimer") is Timer)
    print("Days After playable scene smoke: PASS")
    quit(0)
