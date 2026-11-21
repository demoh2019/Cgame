extends SceneTree

# This integration test REQUIRES the custom Cgame executable compiled with
# modules/world_partition. The stock Godot CI does not execute this script.
const CELL := Vector2i(0, 0)
const LEASE_CELL := Vector2i(5, -4)
const SCENE_PATH := "res://scenes/cell_detail.tscn"
const CHECKPOINT := "user://cgame_native_state_regression.dat"

var layer_notifications: Array[Dictionary] = []
var cell_notifications: Array[Dictionary] = []
var object_notifications: Array[Dictionary] = []
var native_world: Node3D
var activated_cells: Array[Vector2i] = []
var deactivating_cells: Array[Vector2i] = []

func _on_native_cell_activated(cell: Vector2i) -> void:
    activated_cells.append(cell)
    var scene := native_world.call("get_cell_instance", cell) as Node3D
    assert(scene != null)
    assert(int(scene.get("streaming_activation_count")) == 1)
    var stats: Dictionary = native_world.call("get_cell_simulation_stats", cell)
    assert(int(stats["collision_objects"]) == 1)
    assert(int(stats["collision_shapes"]) == 1)
    assert(int(stats["navigation_regions"]) == 1)
    assert((scene.get_node("WalkableRegion") as NavigationRegion3D).enabled)

func _on_native_cell_deactivating(cell: Vector2i) -> void:
    deactivating_cells.append(cell)
    var scene := native_world.call("get_cell_instance", cell) as Node3D
    assert(scene != null)
    assert(int(scene.get("streaming_deactivation_count")) == 1)
    assert((scene.get_node("TerrainPhysics/GroundShape") as CollisionShape3D).disabled)
    assert(not (scene.get_node("WalkableRegion") as NavigationRegion3D).enabled)

func _on_layer_changed(layer: String, enabled: bool) -> void:
    layer_notifications.append({"name": layer, "enabled": enabled})

func _on_object_state_changed(cell: Vector2i, states: Dictionary) -> void:
    object_notifications.append({"cell": cell, "states": states.duplicate(true)})

func _on_cell_state_changed(cell: Vector2i, state: Dictionary) -> void:
    cell_notifications.append({"cell": cell, "state": state.duplicate(true)})

func _initialize() -> void:
    call_deferred("_run")

func _wait_for_cell(world: Node3D, desired: bool, cell: Vector2i = CELL) -> bool:
    for i in 240:
        world.call("update_streaming")
        if bool(world.call("is_cell_loaded", cell)) == desired:
            return true
        await process_frame
    return false

func _run() -> void:
    if not ClassDB.class_exists("WorldPartition3D"):
        push_error("Native test requires a Cgame build with world_partition.")
        quit(2)
        return

    var observer := Node3D.new()
    observer.name = "StateTestObserver"
    get_root().add_child(observer)

    var world := ClassDB.instantiate("WorldPartition3D") as Node3D
    assert(world != null)
    world.name = "StateTestWorld"
    get_root().add_child(world)
    native_world = world
    world.connect("cell_activated", Callable(self, "_on_native_cell_activated"))
    world.connect("cell_deactivating", Callable(self, "_on_native_cell_deactivating"))
    world.connect("layer_state_changed", Callable(self, "_on_layer_changed"))
    world.connect("cell_state_changed", Callable(self, "_on_cell_state_changed"))
    world.connect("cell_object_state_changed", Callable(self, "_on_object_state_changed"))
    world.set("cell_size", 128.0)
    world.set("persist_rigid_bodies", true)
    world.set("persist_streaming_objects", true)
    world.set("load_radius", 0)
    world.set("unload_radius", 1)
    world.set("observer_path", world.get_path_to(observer))
    world.call("set_cell_scene", CELL, SCENE_PATH)
    world.call("set_cell_layer", CELL, "quest_event")
    world.call("set_layer_enabled", "quest_event", false)
    assert(layer_notifications.size() == 1)
    assert(layer_notifications[0]["enabled"] == false)
    world.call("set_layer_enabled", "quest_event", false)
    assert(layer_notifications.size() == 1)  # Effective no-op does not emit.
    for i in 3:
        world.call("update_streaming")
    assert(not bool(world.call("is_cell_loaded", CELL)))
    world.call("set_layer_enabled", "quest_event", true)
    assert(layer_notifications.size() == 2)
    assert(layer_notifications[1]["enabled"] == true)

    assert(await _wait_for_cell(world, true))
    assert(activated_cells.has(CELL))
    var first := world.call("get_cell_instance", CELL) as Node3D
    assert(first != null)
    var treasure := first.get_node("TreasureChest") as Node3D
    assert(treasure.is_in_group("streaming_stateful"))
    assert(first.call("interact_world_object"))
    var object_state: Dictionary = world.call("capture_cell_object_states", CELL)
    assert(object_state["TreasureChest"]["active"] == true)
    assert(object_state["TreasureChest"]["uses"] == 1)
    assert(object_notifications.size() == 1)
    assert(object_notifications[0]["cell"] == CELL)
    assert(world.call("capture_cell_object_states", CELL) == object_state)
    assert(object_notifications.size() == 1)  # No duplicate notification.
    var first_crate := first.get_node("StreamingCrate") as RigidBody3D
    assert(first_crate != null)
    assert(first_crate.get_meta("streaming_persistent") == true)
    first_crate.freeze = true
    first_crate.position = Vector3(82, 5, 66)
    var body_states: Dictionary = world.call("snapshot_cell_physics_states")
    assert(body_states.has(CELL))
    var body_record: Dictionary = body_states[CELL]["StreamingCrate"]
    var saved_transform: Transform3D = body_record["transform"]
    assert(saved_transform.origin == Vector3(82, 5, 66))
    assert(body_record["freeze"] == true)
    assert(first.call("claim_hub_reward"))
    assert(first.call("capture_streaming_state")["reward_claimed"] == true)
    world.call("set_cell_state", CELL, first.call("capture_streaming_state"))
    assert(cell_notifications.size() == 1)
    assert(cell_notifications[0]["state"]["reward_claimed"] == true)
    world.call("set_cell_state", CELL, first.call("capture_streaming_state"))
    assert(cell_notifications.size() == 1)  # Identical data is not an event.

    # Move the observer outside the unload radius to destroy the scene.
    observer.position = Vector3(1024, 0, 0)
    assert(await _wait_for_cell(world, false))
    assert(deactivating_cells.has(CELL))
    assert(bool(world.call("has_cell_state", CELL)))
    assert(world.call("get_cell_state", CELL)["reward_claimed"] == true)
    assert(world.call("get_cell_object_states", CELL)["TreasureChest"]["active"] == true)
    assert(int(world.call("get_cell_object_state_count")) == 1)
    assert(int(world.call("get_cell_physics_state_count")) == 1)
    var unloaded_physics: Dictionary = world.call("get_cell_physics_state", CELL)
    assert(unloaded_physics["StreamingCrate"]["freeze"] == true)
    assert(cell_notifications.size() == 1)  # Unload snapshot unchanged.

    # A pinned cell must stream back in even while the camera is far away.
    world.call("pin_cell", CELL)
    assert(await _wait_for_cell(world, true))
    var restored := world.call("get_cell_instance", CELL) as Node3D
    var restored_crate := restored.get_node("StreamingCrate") as RigidBody3D
    assert(restored_crate != null)
    assert(restored_crate.freeze)
    assert(restored_crate.transform.origin.distance_to(saved_transform.origin) < 0.001)
    assert(restored.call("capture_streaming_state")["reward_claimed"] == true)
    var treasure_again := restored.get_node("TreasureChest") as Node3D
    assert(treasure_again.call("capture_streaming_object_state")["active"] == true)
    assert(not restored.call("interact_world_object"))
    assert(not restored.call("claim_hub_reward"))

    # Snapshot includes the currently resident scene. Save/loading does not
    # need to reinstantiate any Node or deserialize Object references.
    var snapshot: Dictionary = world.call("snapshot_cell_states")
    assert(snapshot[CELL]["reward_claimed"] == true)
    var output := FileAccess.open(CHECKPOINT, FileAccess.WRITE)
    assert(output != null)
    output.store_var(snapshot, false)
    output.close()

    var input := FileAccess.open(CHECKPOINT, FileAccess.READ)
    assert(input != null)
    var loaded: Variant = input.get_var(false)
    input.close()
    assert(loaded is Dictionary)

    # Object-state imports reset missing records on loaded nodes, separately
    # from physics and quest flags; older checkpoint fields remain optional.
    var saved_objects: Dictionary = world.call("snapshot_cell_object_states")
    world.call("load_cell_object_states", {})
    assert(treasure_again.call("capture_streaming_object_state")["active"] == false)
    world.call("load_cell_object_states", saved_objects)
    assert(treasure_again.call("capture_streaming_object_state")["active"] == true)

    # Omitting a cell record resets an already-active scene.
    world.call("load_cell_states", {})
    assert(restored.call("capture_streaming_state")["reward_claimed"] == false)
    world.call("load_cell_states", loaded)
    assert(restored.call("capture_streaming_state")["reward_claimed"] == true)

    # Even pinned cells are evicted by an inactive gameplay Data Layer.
    world.call("set_layer_enabled", "quest_event", false)
    assert(layer_notifications.back()["enabled"] == false)
    assert(await _wait_for_cell(world, false))
    assert(bool(world.call("is_cell_pinned", CELL)))
    assert(world.call("get_cell_state", CELL)["reward_claimed"] == true)
    world.call("set_layer_enabled", "quest_event", true)
    assert(layer_notifications.back()["enabled"] == true)
    assert(await _wait_for_cell(world, true))
    var returned := world.call("get_cell_instance", CELL) as Node3D
    assert(returned.call("capture_streaming_state")["reward_claimed"] == true)

    # A bulk import emits only effective transitions. Removing a disabled
    # entry returns that layer to its implicit enabled default.
    var notifications_before: int = layer_notifications.size()
    world.call("set_layer_states", {"quest_event": false})
    assert(layer_notifications.size() == notifications_before + 1)
    assert(layer_notifications.back()["enabled"] == false)
    world.call("set_layer_states", {"quest_event": false})
    assert(layer_notifications.size() == notifications_before + 1)
    world.call("set_layer_states", {})
    assert(layer_notifications.size() == notifications_before + 2)
    assert(layer_notifications.back()["enabled"] == true)

    # Independent owners hold a different cell without a valid observer.
    world.set("observer_path", NodePath())
    world.call("set_cell_scene", LEASE_CELL, SCENE_PATH)
    var quest_lease: int = int(world.call("acquire_cell_lease", LEASE_CELL))
    var cinematic_lease: int = int(world.call("acquire_cell_lease", LEASE_CELL))
    assert(quest_lease > 0 and cinematic_lease > 0 and quest_lease != cinematic_lease)
    assert(int(world.call("get_cell_lease_count", LEASE_CELL)) == 2)
    assert(await _wait_for_cell(world, true, LEASE_CELL))

    # Quest ending must not unload a cinematic still running there.
    assert(bool(world.call("release_cell_lease", quest_lease)))
    world.call("update_streaming")
    assert(bool(world.call("is_cell_loaded", LEASE_CELL)))
    assert(int(world.call("get_cell_lease_count", LEASE_CELL)) == 1)

    # Data Layers still supersede a valid lease.
    world.call("set_cell_layer", LEASE_CELL, "cinematic")
    world.call("set_layer_enabled", "cinematic", false)
    assert(await _wait_for_cell(world, false, LEASE_CELL))
    assert(int(world.call("get_cell_lease_count", LEASE_CELL)) == 1)
    world.call("set_layer_enabled", "cinematic", true)
    assert(await _wait_for_cell(world, true, LEASE_CELL))

    # Releasing the final handle makes the distant cell unloadable.
    assert(bool(world.call("release_cell_lease", cinematic_lease)))
    assert(await _wait_for_cell(world, false, LEASE_CELL))
    assert(not bool(world.call("release_cell_lease", cinematic_lease)))
    assert(int(world.call("get_cell_lease_count_total")) == 0)

    # Native route prefetch, independent of observation and ordinary leases.
    var target_cell := Vector2i(1, 0)
    world.call("set_cell_scene", target_cell, SCENE_PATH)
    var corridor: Array = world.call("get_cell_route", CELL, target_cell)
    assert(corridor.size() == 2)
    assert(corridor[0] == CELL and corridor[1] == target_cell)
    var route_tokens: Array = world.call("acquire_cell_route", CELL, target_cell)
    assert(route_tokens.size() == 2)
    assert(await _wait_for_cell(world, true, target_cell))

    # Route acquisition must be atomic if an event layer blocks its endpoint.
    world.call("set_cell_layer", target_cell, "locked_path")
    world.call("set_layer_enabled", "locked_path", false)
    assert(world.call("acquire_cell_route", CELL, target_cell).is_empty())
    assert(int(world.call("get_cell_lease_count_total")) == 2)
    world.call("set_layer_enabled", "locked_path", true)
    assert(await _wait_for_cell(world, true, target_cell))
    var target_root := world.call("get_cell_instance", target_cell) as Node3D
    assert(target_root != null)
    var target_nav := target_root.get_node("WalkableRegion") as NavigationRegion3D
    assert(target_nav.enabled)
    world.call("set_cell_navigation_enabled", target_cell, false)
    assert(not bool(world.call("is_cell_navigation_enabled", target_cell)))
    assert(not target_nav.enabled)
    assert(world.call("acquire_cell_route", CELL, target_cell).is_empty())
    assert(int(world.call("get_cell_lease_count_total")) == 2)
    var blocked_nav: Dictionary = world.call("get_navigation_cell_states")
    assert(blocked_nav[target_cell] == false)
    world.call("set_navigation_cell_states", {})
    assert(target_nav.enabled)
    assert(bool(world.call("is_cell_navigation_enabled", target_cell)))
    world.call("set_navigation_cell_states", blocked_nav)
    assert(not target_nav.enabled)
    world.call("set_cell_navigation_enabled", target_cell, true)
    assert(target_nav.enabled)
    assert(int(world.call("release_cell_route", route_tokens)) == 2)
    assert(int(world.call("release_cell_route", route_tokens)) == 0)
    assert(int(world.call("get_cell_lease_count_total")) == 0)

    world.set("streaming_enabled", false)
    assert(activated_cells.size() >= 2)
    assert(deactivating_cells.size() >= 2)
    world.queue_free()
    observer.queue_free()
    await process_frame
    print("Native WorldPartition3D cell state streaming integration passed")
    quit(0)
