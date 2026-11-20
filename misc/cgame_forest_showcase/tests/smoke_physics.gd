extends SceneTree
## Aurora Forest physics regression:
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_physics.gd
##
## Waits for async streaming before querying physics. Covers heightfield
## raycasts, capsule grounding, collision-cell lifetime and streaming safety.

const MAX_PHYSICS_FRAMES: int = 360


func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("Forest physics smoke FAILED: " + reason)
    quit(1)


func _find_cell(stream: WorldPartition3D, coordinate: Vector2i) -> Node3D:
    return stream.get_cell_node(coordinate)

func _run() -> void:
    var packed: PackedScene = load("res://world.tscn")
    if packed == null:
        _fail("main world scene did not load")
        return
    var world := packed.instantiate() as Node3D
    if world == null:
        _fail("world root is not Node3D")
        return
    root.add_child(world)

    var player := world.get_node_or_null("ExplorerBody") as CharacterBody3D
    var boundaries := world.get_node_or_null("WorldBoundsCollision") as StaticBody3D
    var stream := world.get_node_or_null("WorldPartition_32m") as WorldPartition3D
    if player == null or boundaries == null or stream == null:
        _fail("missing character, world boundary or world streamer")
        return
    if world.get_node_or_null("TerrainCollision") != null:
        _fail("old monolithic terrain collider must not remain in the persistent world")
        return
    if bool(player.get("movement_enabled")):
        _fail("character must be frozen before the async spawn tile is loaded")
        return

    var capsule := player.get_node_or_null("CapsuleCollision") as CollisionShape3D
    if capsule == null or not (capsule.shape is CapsuleShape3D):
        _fail("explorer has no capsule shape")
        return

    var origin := Vector2i(0, 0)
    for i in range(MAX_PHYSICS_FRAMES):
        if stream.is_cell_loaded(origin):
            break
        await physics_frame
    if not stream.are_cells_loaded(origin, 0):
        _fail("spawn tile failed to load before physics timeout")
        return

    var tile := _find_cell(stream, origin)
    if tile == null:
        _fail("loaded origin scene root could not be located")
        return
    var ground := tile.get_node_or_null("TerrainPatch/GroundMesh") as MeshInstance3D
    var terrain_body := tile.get_node_or_null("TerrainPatch/GroundCollision") as StaticBody3D
    var collider := tile.get_node_or_null("TerrainPatch/GroundCollision/HeightmapCollision") as CollisionShape3D
    if ground == null or terrain_body == null or collider == null:
        _fail("streamed terrain has no mesh or heightfield collider")
        return
    if not (collider.shape is HeightMapShape3D):
        _fail("streamed terrain collision must use HeightMapShape3D")
        return
    if not bool(player.get("movement_enabled")):
        _fail("character did not unfreeze once the spawn tile loaded")
        return

    # Allow physics server to register the newly instantiated StaticBody3D.
    for i in range(4):
        await physics_frame
    var ray := PhysicsRayQueryParameters3D.create(
        Vector3(0.0, 15.0, 9.0), Vector3(0.0, -15.0, 9.0))
    ray.collision_mask = 1
    var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
    if hit.is_empty() or hit.get("collider") != terrain_body:
        _fail("physics ray missed the streamed heightfield collider")
        return

    # Teleport 3m above the sampled terrain, then verify gravity lands the body.
    var expected_floor: float = float(world.call("height_at", 0.0, 9.0))
    player.call("teleport_to_ground", 0.0, 9.0, expected_floor + 3.0)
    var landed: bool = false
    for i in range(MAX_PHYSICS_FRAMES):
        await physics_frame
        if player.is_on_floor():
            landed = true
            break
    if not landed:
        _fail("capsule failed to land on streamed heightfield")
        return
    var feet: float = player.global_position.y - 0.95
    if absf(feet - expected_floor) > 0.45:
        _fail("player did not stand on streamed terrain (%s vs %s)" % [feet, expected_floor])
        return

    var obstacles := tile.get_node_or_null("FoliageCollisions") as StaticBody3D
    if obstacles == null or obstacles.get_child_count() < 9:
        _fail("streamed rocks/trunks did not create primitive colliders")
        return

    if player.call("_position_has_terrain", Vector3(500, 0, 500)):
        _fail("character reports terrain present outside registered cells")
        return

    print("Forest physics smoke PASSED: streamed heightfield raycast, capsule landing, per-cell obstacles and collision safety")
    quit(0)
