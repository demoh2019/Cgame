extends SceneTree

# Stock Godot 4 headless: route patrol integration using two adjacent real
# nav regions; only the C++ native lease ownership is replaced with a stub.
const DETAIL := preload("res://scenes/cell_detail.tscn")
const PATROL := preload("res://scripts/route_patrol_agent.gd")
const MOCK_STREAMER := preload("res://tests/helpers/mock_route_streamer.gd")

func _initialize() -> void:
    call_deferred("_run")

func _spawn_cell(coord: Vector2i) -> Node3D:
    var scene := DETAIL.instantiate() as Node3D
    assert(scene != null)
    scene.position = Vector3(coord.x * 128.0, 0.0, coord.y * 128.0)
    get_root().add_child(scene)
    return scene

func _run() -> void:
    var left := _spawn_cell(Vector2i(0, 0))
    var right := _spawn_cell(Vector2i(1, 0))
    var streamer := MOCK_STREAMER.new() as Node3D
    get_root().add_child(streamer)
    var npc := PATROL.new() as CharacterBody3D
    assert(npc != null)
    npc.position = Vector3(110, 0.1, 64)
    npc.call("configure", streamer)
    get_root().add_child(npc)

    assert(int(streamer.call("get_cell_lease_count_total")) == 2)
    assert((npc.get_node("PathFollower") as NavigationAgent3D) != null)
    assert((npc.get_node("AgentCollider") as CollisionShape3D).shape is CapsuleShape3D)

    await physics_frame
    await physics_frame
    await physics_frame
    var left_nav := left.get_node("PatrolTrack") as NavigationRegion3D
    var right_nav := right.get_node("PatrolTrack") as NavigationRegion3D
    var bridge := left.get_node("PatrolBridgeLink") as NavigationLink3D
    assert(left_nav.navigation_layers == 2 and right_nav.navigation_layers == 2)
    assert(bridge.navigation_layers == 2 and bridge.bidirectional)
    assert(bridge.enabled)
    var origin := Vector3(110, 0, 64)
    var destination := Vector3(146, 0, 64)
    var path: PackedVector3Array = NavigationServer3D.map_get_path(
        left_nav.get_navigation_map(), origin, destination, true, 2
    )
    assert(path.size() >= 2)
    assert(path[path.size() - 1].distance_to(destination) < 2.0)

    var crossed_boundary := false
    for i in 420:
        await physics_frame
        if npc.global_position.x > 129.0:
            crossed_boundary = true
            break
    assert(crossed_boundary)
    var state: Dictionary = npc.call("capture_patrol_state")
    assert(state.get("position") is Vector3)
    assert(state.get("target_index") is int)
    assert(state.get("completed_crossings") is int)
    assert(state.get("enabled") == true)

    npc.call("set_patrol_enabled", false)
    assert(int(streamer.call("get_cell_lease_count_total")) == 0)
    npc.call("restore_patrol_state", state)
    assert(int(streamer.call("get_cell_lease_count_total")) == 2)

    var restored_state: Dictionary = npc.call("capture_patrol_state")
    assert(restored_state.get("target_index") == state.get("target_index"))
    assert(restored_state.get("completed_crossings") == state.get("completed_crossings"))

    # A disabled streamed cell must stall movement until the nav region is
    # back and a fresh NavigationServer synchronization has completed.
    streamer.set("cells_loaded", false)
    var frozen_position := npc.global_position
    for i in 3:
        await physics_frame
    assert(npc.global_position.distance_to(frozen_position) < 0.01)
    streamer.set("cells_loaded", true)
    for i in 4:
        await physics_frame
    assert(int(npc.call("get_patrol_status")["route_tokens"]) == 2)

    # Opening/closing a world gate changes the route without destroying
    # the detailed scene. The NPC must release its corridor immediately.
    var pass_cell := Vector2i(1, 0)
    var pass_region := right.get_node("WalkableRegion") as NavigationRegion3D
    streamer.call("set_cell_navigation_enabled", pass_cell, false)
    pass_region.enabled = false
    assert(int(streamer.call("get_cell_lease_count_total")) == 0)
    assert(int(npc.call("get_patrol_status")["route_tokens"]) == 0)
    var stopped := npc.global_position
    for i in 6:
        await physics_frame
    assert(npc.global_position.distance_to(stopped) < 0.01)
    streamer.call("set_cell_navigation_enabled", pass_cell, true)
    pass_region.enabled = true
    await physics_frame
    await physics_frame
    assert(int(streamer.call("get_cell_lease_count_total")) == 2)
    assert(int(npc.call("get_patrol_status")["route_tokens"]) == 2)

    # Close only the precise off-mesh bridge, not an entire navigation
    # region. The ordinary walkable world and both patrol islands remain.
    assert(bridge.enabled)
    streamer.call("set_cell_navigation_link_enabled", Vector2i(0, 0), "PatrolBridgeLink", false)
    bridge.enabled = false
    assert(not bridge.enabled)
    assert(left_nav.enabled and right_nav.enabled)
    assert(int(streamer.call("get_cell_lease_count_total")) == 0)
    assert(int(npc.call("get_patrol_status")["route_tokens"]) == 0)
    var paused := npc.global_position
    for i in 4:
        await physics_frame
    assert(npc.global_position.distance_to(paused) < 0.01)
    var blocked_path: PackedVector3Array = NavigationServer3D.map_get_path(
        left_nav.get_navigation_map(), origin, destination, true, 2
    )
    assert(blocked_path.is_empty() or blocked_path[blocked_path.size() - 1].distance_to(destination) > 2.0)
    streamer.call("set_cell_navigation_link_enabled", Vector2i(0, 0), "PatrolBridgeLink", true)
    bridge.enabled = true
    await physics_frame
    await physics_frame
    assert(int(streamer.call("get_cell_lease_count_total")) == 2)
    var reopened: PackedVector3Array = NavigationServer3D.map_get_path(
        left_nav.get_navigation_map(), origin, destination, true, 2
    )
    assert(reopened.size() >= 2)
    assert(reopened[reopened.size() - 1].distance_to(destination) < 2.0)

    npc.free()
    assert(int(streamer.call("get_cell_lease_count_total")) == 0)
    streamer.free()
    left.free()
    right.free()
    print("AI patrol crossed connected streamed navigation regions and released its route")
    quit(0)
