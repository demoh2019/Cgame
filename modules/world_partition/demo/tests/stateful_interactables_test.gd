extends SceneTree

# Runs in stock Godot: interactive child components persist through the
# exact object-state callback contract used by native WorldPartition3D.
const DETAIL := preload("res://scenes/cell_detail.tscn")
const PROXY := preload("res://scenes/cell_proxy.tscn")
const CELL_SIZE := 128.0

func _initialize() -> void:
    call_deferred("_run")

func _open(cell: Vector2i, scene: PackedScene = DETAIL) -> Node3D:
    var root := scene.instantiate() as Node3D
    assert(root != null)
    root.position = Vector3(cell.x * CELL_SIZE, 0.0, cell.y * CELL_SIZE)
    get_root().add_child(root)
    return root

func _run() -> void:
    var hub := _open(Vector2i(0, 0))
    var chest := hub.get_node("TreasureChest") as Node3D
    assert(chest != null)
    assert(chest.is_in_group("streaming_stateful"))
    assert(chest.has_method("capture_streaming_object_state"))
    assert(chest.has_method("restore_streaming_object_state"))
    var initial: Dictionary = chest.call("capture_streaming_object_state")
    assert(initial == {"active": false, "uses": 0})
    assert(hub.call("interact_world_object"))
    assert(not hub.call("interact_world_object"))
    var claimed: Dictionary = chest.call("capture_streaming_object_state")
    assert(claimed["active"] == true and claimed["uses"] == 1)
    assert((chest.get_node("InteractionLabel") as Label3D).text == "TREASURE OPENED")
    hub.free()

    var restored := _open(Vector2i(0, 0))
    var restored_chest := restored.get_node("TreasureChest") as Node3D
    restored_chest.call("restore_streaming_object_state", claimed)
    assert(restored_chest.call("capture_streaming_object_state") == claimed)
    assert(not restored.call("interact_world_object"))
    restored_chest.call("restore_streaming_object_state", {})
    assert(restored_chest.call("capture_streaming_object_state") == initial)
    assert(restored.call("interact_world_object"))
    restored.free()

    # Repeatable mechanisms persist both current state and action counter.
    var arena := _open(Vector2i(4, 2))
    var switch := arena.get_node("ArenaSwitch") as Node3D
    assert(switch.is_in_group("streaming_stateful"))
    assert(arena.call("interact_world_object"))
    assert(arena.call("interact_world_object"))
    var switch_snapshot: Dictionary = switch.call("capture_streaming_object_state")
    assert(switch_snapshot == {"active": false, "uses": 2})
    arena.free()
    var arena_again := _open(Vector2i(4, 2))
    var again_switch := arena_again.get_node("ArenaSwitch") as Node3D
    again_switch.call("restore_streaming_object_state", switch_snapshot)
    assert(again_switch.call("capture_streaming_object_state") == switch_snapshot)
    assert(arena_again.call("interact_world_object"))
    assert(again_switch.call("capture_streaming_object_state")["active"] == true)
    arena_again.free()

    var champion := _open(Vector2i(5, 3))
    var gate := champion.get_node("ChampionGate") as Node3D
    assert(not bool(gate.call("capture_streaming_object_state")["active"]))
    assert(champion.call("interact_world_object"))
    assert(not champion.call("interact_world_object"))
    assert(gate.call("capture_streaming_object_state")["active"] == true)
    champion.free()

    var ordinary := _open(Vector2i(2, 2))
    assert(ordinary.call("get_interactable") == null)
    assert(not ordinary.call("interact_world_object"))
    ordinary.free()

    var distant := _open(Vector2i(0, 0), PROXY)
    assert(distant.get_node_or_null("TreasureChest") == null)
    assert(distant.get_node_or_null("ArenaSwitch") == null)
    distant.free()

    print("Stateful streamed interactables: chest, switch, gate and HLOD exclusions passed")
    quit(0)
