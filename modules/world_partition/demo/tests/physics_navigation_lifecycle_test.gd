extends SceneTree

# Standalone Godot 4 test for streamed collision/navigation scene contracts.
# Native callback dispatch itself is covered by the Cgame integration test.
const DETAIL := preload("res://scenes/cell_detail.tscn")
const PROXY := preload("res://scenes/cell_proxy.tscn")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var detail := DETAIL.instantiate() as Node3D
    assert(detail != null)
    get_root().add_child(detail)

    var physics := detail.get_node("TerrainPhysics") as StaticBody3D
    var collision := detail.get_node("TerrainPhysics/GroundShape") as CollisionShape3D
    var region := detail.get_node("WalkableRegion") as NavigationRegion3D
    assert(physics != null and collision != null and region != null)
    assert(physics.collision_layer == 1)
    assert(collision.shape is BoxShape3D)
    assert((collision.shape as BoxShape3D).size == Vector3(128.0, 0.2, 128.0))
    assert(not collision.disabled)
    assert(region.enabled)
    assert(region.navigation_mesh != null)
    assert(region.navigation_mesh.get_polygon_count() == 1)

    detail.call("streaming_activated", Vector2i(0, 0))
    assert(int(detail.get("streaming_activation_count")) == 1)
    assert(not collision.disabled and region.enabled)

    # The NavigationServer only synchronizes the new region after a physics
    # tick. Pathfinding in the same _ready() is not a valid integration test.
    await physics_frame
    await physics_frame
    assert(is_instance_valid(detail))
    var path: PackedVector3Array = NavigationServer3D.map_get_path(
        region.get_navigation_map(),
        Vector3(12, 0, 12),
        Vector3(116, 0, 116),
        true
    )
    assert(path.size() >= 2)

    detail.call("streaming_deactivating", Vector2i(0, 0))
    assert(int(detail.get("streaming_deactivation_count")) == 1)
    assert(collision.disabled)
    assert(not region.enabled)
    detail.free()

    # Distant HLOD scenes must NEVER enter the physics or navigation servers.
    var proxy := PROXY.instantiate() as Node3D
    assert(proxy != null)
    get_root().add_child(proxy)
    assert(proxy.get_node_or_null("TerrainPhysics") == null)
    assert(proxy.get_node_or_null("WalkableRegion") == null)
    proxy.call("streaming_activated", Vector2i(0, 0))
    proxy.call("streaming_deactivating", Vector2i(0, 0))
    proxy.free()

    print("Streaming physics and navigation lifecycle contract passed")
    quit(0)
