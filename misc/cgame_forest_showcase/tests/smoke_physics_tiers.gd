extends SceneTree
## Headless regression for independent native collision streaming.
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_physics_tiers.gd
##
## Loaded forest geometry must survive dormant physics; urgent sources must
## restore near-detail colliders before gameplay is permitted to travel.

const FOREST: String = "res://cells/forest_cell.tscn"
const MAX_FRAMES: int = 480
const REMOTE: Vector2i = Vector2i(2, 0)


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("Forest physics-tier smoke FAILED: " + message)
    quit(1)


func _wait_cell(stream: WorldPartition3D, cell: Vector2i) -> Node3D:
    for i in range(MAX_FRAMES):
        var root_node: Node3D = stream.get_cell_instance(cell)
        if root_node != null:
            return root_node
        await process_frame
    return null


func _wait_physics(stream: WorldPartition3D, cell: Vector2i, active: bool) -> bool:
    for i in range(MAX_FRAMES):
        stream.update_streaming()
        var root_node: Node3D = stream.get_cell_instance(cell)
        if root_node != null and stream.is_cell_physics_active(cell) == active                 and root_node.get("streaming_physics_active") == active:
            return true
        await process_frame
    return false


func _wait_source_physics(stream: WorldPartition3D, name: String) -> bool:
    for i in range(MAX_FRAMES):
        stream.update_streaming()
        if stream.is_streaming_source_physics_ready(name):
            return true
        await process_frame
    return false


func _run() -> void:
    if not ResourceLoader.exists(FOREST):
        _fail("forest PackedScene missing")
        return

    var observer := Node3D.new()
    observer.name = "Observer"
    root.add_child(observer)
    var stream := WorldPartition3D.new()
    stream.cell_size = 32.0
    stream.load_radius = 2
    stream.unload_radius = 3
    stream.detail_radius = -1 # All cells have full graphics and obstacle meshes.
    stream.physics_radius = 0
    stream.physics_hysteresis_cells = 1
    stream.max_physics_transitions_per_frame = 1
    stream.max_detail_transitions_per_frame = 1
    stream.max_instances_per_frame = 1
    root.add_child(stream)
    stream.observer_path = stream.get_path_to(observer)
    for x in range(3):
        stream.set_cell_scene(Vector2i(x, 0), FOREST)
    var home := Vector2i.ZERO
    var next_cell := Vector2i(1, 0)
    for x in range(3):
        var loaded_root: Node3D = await _wait_cell(stream, Vector2i(x, 0))
        if loaded_root == null:
            _fail("streamed cell failed to load")
            return

    if not stream.is_cell_physics_active(home) or stream.is_cell_physics_active(next_cell):
        _fail("initial physics classification incorrect")
        return
    if stream.get_physics_active_cell_count() != 1:
        _fail("physics-active cell counter did not reflect one near cell")
        return
    var remote_scene: Node3D = stream.get_cell_instance(REMOTE)
    var body := remote_scene.get_node_or_null("FoliageCollisions") as StaticBody3D
    if body == null or body.get_child_count() == 0 or body.collision_layer != 0:
        _fail("distant scene did not retain collision shapes while filtered")
        return
    if remote_scene.get_node_or_null("TreeTrunks") == null:
        _fail("remote visual geometry was removed when collision was dormant")
        return

    # Background quest preloading must NOT turn on remote collision layers.
    if not stream.set_streaming_source("a_quest", Vector3(80, 0, 0), 0, 0):
        _fail("background source registration rejected")
        return
    for i in range(4):
        stream.update_streaming()
        await process_frame
    if stream.is_cell_physics_active(REMOTE) or body.collision_layer != 0:
        _fail("background objective wrongly activated distant collision")
        return

    # An urgent portal activates the remote cell, even outside the normal
    # collision radius. It also forces full-detail visual/collision LOD.
    stream.detail_radius = 0
    for i in range(6):
        stream.update_streaming()
        await process_frame
    if not stream.set_streaming_source("z_portal", Vector3(80, 0, 0), 0, 3):
        _fail("urgent travel source registration rejected")
        return
    if not await _wait_physics(stream, REMOTE, true):
        _fail("urgent source did not activate remote collision policy")
        return
    if not await _wait_source_physics(stream, "z_portal"):
        _fail("urgent source did not pass its physics readiness fence")
        return
    remote_scene = stream.get_cell_instance(REMOTE)
    body = remote_scene.get_node_or_null("FoliageCollisions") as StaticBody3D
    if body == null or body.collision_layer != 1:
        _fail("urgent cell did not restore near-detail obstacle collision")
        return
    if stream.get_cell_detail_level(REMOTE) != 0:
        _fail("urgent portal did not promote destination to full LOD")
        return

    # Test the live PhysicsServer collision filter using a trunk shape's
    # center, rather than trusting only a script property value.
    var first_shape := body.get_child(0) as CollisionShape3D
    if first_shape == null:
        _fail("no near-detail trunk collider to query")
        return
    var center: Vector3 = first_shape.global_position
    var query := PhysicsRayQueryParameters3D.create(
        center + Vector3(-0.75, 0, 0), center + Vector3(0.75, 0, 0))
    query.collision_mask = 1
    await physics_frame
    await process_frame
    # A SceneTree root is a Window; use its World3D physics space.
    var hit: Dictionary = root.get_world_3d().direct_space_state.intersect_ray(query)
    var foliage_id: int = body.get_instance_id()
    if hit.get("collider_id", -1) != foliage_id:
        _fail("physics query did not hit newly activated remote foliage")
        return

    stream.remove_streaming_source("z_portal")
    if not await _wait_physics(stream, REMOTE, false):
        _fail("remote collision policy stayed active after portal removal")
        return
    await physics_frame
    await process_frame
    hit = root.get_world_3d().direct_space_state.intersect_ray(query)
    if hit.get("collider_id", -1) == foliage_id:
        _fail("dormant foliage was still hit by collision ray")
        return
    if not stream.is_cell_loaded(REMOTE) or stream.get_cell_instance(REMOTE) == null:
        _fail("collision deactivation incorrectly unloaded distant scene")
        return
    if stream.is_streaming_source_physics_ready("z_portal"):
        _fail("removed urgent source retained readiness")
        return

    # Pinned hub must override observer distance, but unpin must restore tier.
    if not stream.pin_cell(REMOTE):
        _fail("could not pin distant physics hub")
        return
    if not await _wait_physics(stream, REMOTE, true):
        _fail("pin did not activate collision")
        return
    stream.unpin_cell(REMOTE)
    if not await _wait_physics(stream, REMOTE, false):
        _fail("unpin did not deactivate distant collision")
        return

    # Turning off the independent tier preserves legacy all-loaded collision.
    stream.physics_radius = -1
    for x in range(3):
        if not await _wait_physics(stream, Vector2i(x, 0), true):
            _fail("physics tier opt-out did not reactivate all cells")
            return
    if stream.get_physics_active_cell_count() != 3:
        _fail("expected three active cells after disabling the physics tier")
        return

    print("Forest physics tiers smoke PASSED: filtered foliage, active raycast, priority, near LOD, pins, legacy opt-out")
    quit(0)
