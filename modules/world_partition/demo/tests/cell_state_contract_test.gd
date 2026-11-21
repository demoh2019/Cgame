extends SceneTree

# Standalone Godot headless regression for scene-root gameplay state callbacks.
# Does not require Cgame: the native WorldPartition3D orchestration has C++ tests.
const SCENE := preload("res://scenes/cell_detail.tscn")
const SIZE := 128.0

func _initialize() -> void:
    call_deferred("_run")

func _open_cell(coord: Vector2i) -> Node3D:
    var node := SCENE.instantiate() as Node3D
    assert(node != null)
    node.position = Vector3(float(coord.x) * SIZE, 0.0, float(coord.y) * SIZE)
    get_root().add_child(node)
    return node

func _run() -> void:
    var hub := _open_cell(Vector2i(0, 0))
    assert(hub.has_method("capture_streaming_state"))
    assert(hub.call("capture_streaming_state")["reward_claimed"] == false)
    assert(hub.call("claim_hub_reward"))
    assert(not hub.call("claim_hub_reward"))
    var hub_snapshot: Dictionary = hub.call("capture_streaming_state")
    assert(hub_snapshot["reward_claimed"] == true)
    assert((hub.get_node("QuestHub/StateLabel") as Label3D).text == "HUB REWARD CLAIMED")
    hub.free()

    var hub_restored := _open_cell(Vector2i(0, 0))
    hub_restored.call("restore_streaming_state", hub_snapshot)
    assert(hub_restored.call("capture_streaming_state")["reward_claimed"] == true)
    assert(not hub_restored.call("claim_hub_reward"))
    hub_restored.call("restore_streaming_state", {})
    assert(hub_restored.call("capture_streaming_state")["reward_claimed"] == false)
    hub_restored.free()

    var arena := _open_cell(Vector2i(4, 2))
    assert(arena.call("win_arena_round") == 1)
    assert(arena.call("win_arena_round") == 2)
    var arena_state: Dictionary = arena.call("capture_streaming_state")
    assert(arena_state["arena_wins"] == 2)
    arena.free()

    var arena_restored := _open_cell(Vector2i(4, 2))
    arena_restored.call("restore_streaming_state", arena_state)
    assert(arena_restored.call("capture_streaming_state")["arena_wins"] == 2)
    assert(arena_restored.call("win_arena_round") == 3)
    assert((arena_restored.get_node("CombatArena/StateLabel") as Label3D).text == "ARENA WINS: 3  [B]")
    arena_restored.free()

    var champion := _open_cell(Vector2i(5, 3))
    assert(champion.call("capture_streaming_state")["champion_reward_claimed"] == false)
    assert(champion.call("claim_champion_reward"))
    assert(not champion.call("claim_champion_reward"))
    var champion_state: Dictionary = champion.call("capture_streaming_state")
    assert(champion_state["champion_reward_claimed"] == true)
    champion.free()
    var champion_restored := _open_cell(Vector2i(5, 3))
    champion_restored.call("restore_streaming_state", champion_state)
    assert(champion_restored.call("capture_streaming_state")["champion_reward_claimed"] == true)
    assert((champion_restored.get_node("ChampionShrine/StateLabel") as Label3D).text == "CHAMPION REWARD CLAIMED")
    champion_restored.free()

    var ordinary := _open_cell(Vector2i(2, 2))
    assert(ordinary.call("capture_streaming_state").is_empty())
    assert(not ordinary.call("claim_hub_reward"))
    assert(ordinary.call("win_arena_round") == -1)
    ordinary.free()
    print("Gameplay streaming state contract regression passed")
    quit(0)
