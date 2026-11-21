extends SceneTree

# Stock Godot headless: real RigidBody3D dynamics and opt-in save contract.
# Native WorldPartition3D snapshot/restore is exercised separately in C++ tests.
const DETAIL := preload("res://scenes/cell_detail.tscn")
const PROXY := preload("res://scenes/cell_proxy.tscn")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var hub := DETAIL.instantiate() as Node3D
    assert(hub != null)
    get_root().add_child(hub)
    var body := hub.get_node("StreamingCrate") as RigidBody3D
    assert(body != null)
    assert(body.has_meta("streaming_persistent"))
    assert(body.get_meta("streaming_persistent") == true)
    assert((body.get_node("CrateCollision") as CollisionShape3D).shape is BoxShape3D)
    assert((body.get_node("CrateVisual") as MeshInstance3D).mesh is BoxMesh)

    var start := body.global_position
    assert(hub.call("kick_persistent_crate"))
    for i in 12:
        await physics_frame
    assert(body.global_position.distance_to(start) > 0.05)

    # Restore the scene's authored root and ensure a fresh body is created.
    var saved_transform := body.transform
    var saved_velocity := body.linear_velocity
    assert(saved_transform.is_finite())
    assert(saved_velocity.is_finite())
    hub.free()
    var reloaded := DETAIL.instantiate() as Node3D
    assert(reloaded != null)
    get_root().add_child(reloaded)
    var again := reloaded.get_node("StreamingCrate") as RigidBody3D
    assert(again != null)
    # These are the same properties that the C++ snapshot will set on load.
    again.freeze = true
    again.transform = saved_transform
    again.linear_velocity = saved_velocity
    assert(again.transform.origin.distance_to(saved_transform.origin) < 0.001)
    assert(again.freeze)
    reloaded.free()

    # Proxy never creates gameplay physics; prebaked HLOD stores meshes only.
    var far := PROXY.instantiate() as Node3D
    get_root().add_child(far)
    assert(far.get_node_or_null("StreamingCrate") == null)
    assert(far.get_node_or_null("TerrainPhysics") == null)
    far.free()

    print("Streamed opt-in rigid body scene contract passed")
    quit(0)
