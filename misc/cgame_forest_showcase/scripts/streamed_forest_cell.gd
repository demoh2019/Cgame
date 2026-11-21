extends Node3D
## One reusable PackedScene streams in any WorldPartition3D cell.
## The engine positions this root at its cell origin before _ready().
## Per-cell deterministic seeds keep the same foliage layout on reload.

const TerrainHeight = preload("res://scripts/terrain_height.gd")
const ForestNavigationMesh = preload("res://scripts/forest_navigation_mesh.gd")
const CELL_SIZE: float = 32.0
const TREE_COUNT: int = 54
const GRASS_COUNT: int = 225
const ROCK_COUNT: int = 9
const DISTANT_TREE_COUNT: int = 16

# 0 = fully interactive vegetation; 1 = distant GPU-only canopy proxy.
# The native streamer calls set_streaming_lod() before _ready on new cells.

var rng := RandomNumberGenerator.new()
var grass: MultiMeshInstance3D
var obstacles: StaticBody3D
var high_quality: bool = true
var streaming_lod: int = 0
var streaming_simulation_active: bool = true
var streaming_physics_active: bool = true
var streaming_navigation_active: bool = true
var navigation_region: NavigationRegion3D
var navigation_mesh_cache: NavigationMesh
var navigation_blockers: PackedVector3Array = PackedVector3Array()
# One gameplay-built barricade per loaded forest cell. It updates navigation
# through the native dirty-tile queue, without reloading or rebuilding foliage.
const BARRICADE_RADIUS: float = 1.42
var barricade_active: bool = false
var barricade_local_position: Vector3 = Vector3.ZERO
var barricade_body: StaticBody3D
var navigation_rebuilds: int = 0
var beacon_time: float = 0.0
var cell_seed: int = 0
var cell_x: int = 0
var cell_z: int = 0


func _ready() -> void:
    cell_x = int(round(global_position.x / CELL_SIZE))
    cell_z = int(round(global_position.z / CELL_SIZE))
    cell_seed = 913481 + cell_x * 73856093 + cell_z * 19349663
    _rebuild_lod()
    _update_simulation_processing()


func set_streaming_simulation_active(active: bool) -> void:
    # Native WorldPartition3D invokes this before _ready() on first load and
    # again under a bounded per-frame budget as the observer moves.
    streaming_simulation_active = active
    if is_node_ready():
        _update_simulation_processing()


func set_streaming_physics_active(active: bool) -> void:
    # Called by native WorldPartition3D before _ready() and again for tier
    # transitions. Keep authored collision shapes but remove their gameplay
    # layer while dormant; distant foliage and trees remain visible.
    streaming_physics_active = active
    if is_instance_valid(obstacles):
        obstacles.collision_layer = 1 if active else 0
    if is_instance_valid(barricade_body):
        barricade_body.collision_layer = 1 if active else 0


func set_streaming_navigation_active(active: bool) -> void:
    # Called by WorldPartition3D before _ready() and with a bounded
    # per-frame budget. It is separate from physics and visual LOD.
    streaming_navigation_active = active
    if is_node_ready():
        _sync_navigation_region()


func _current_navigation_blockers() -> PackedVector3Array:
    var footprints: PackedVector3Array = navigation_blockers.duplicate()
    if barricade_active:
        footprints.append(Vector3(
            barricade_local_position.x, barricade_local_position.z, BARRICADE_RADIUS))
    return footprints


func _build_current_navigation_mesh() -> NavigationMesh:
    return ForestNavigationMesh.build_tile(
        global_position, get_parent() as WorldPartition3D, _current_navigation_blockers())


func rebuild_streaming_navigation_mesh() -> bool:
    # Opt-in callback used by WorldPartition3D's limited dirty-tile scheduler.
    # Publish a NEW NavMesh resource, not a mutation of the old server mesh.
    if (not is_node_ready() or streaming_lod != 0 or not streaming_navigation_active
            or not is_instance_valid(navigation_region) or not navigation_region.enabled):
        return false
    var refreshed: NavigationMesh = _build_current_navigation_mesh()
    if refreshed == null or refreshed.get_polygon_count() == 0:
        return false
    navigation_mesh_cache = refreshed
    navigation_region.navigation_mesh = refreshed
    navigation_rebuilds += 1
    return true


func _create_barricade_visual() -> void:
    if not barricade_active or streaming_lod != 0 or is_instance_valid(barricade_body):
        return
    barricade_body = StaticBody3D.new()
    barricade_body.name = "DynamicBarricade"
    barricade_body.collision_layer = 1 if streaming_physics_active else 0
    barricade_body.collision_mask = 0
    barricade_body.position = barricade_local_position
    var box := BoxShape3D.new()
    box.size = Vector3(2.0, 1.6, 2.0)
    var collider := CollisionShape3D.new()
    collider.shape = box
    barricade_body.add_child(collider)
    var crate := MeshInstance3D.new()
    crate.name = "BarricadeCrate"
    var mesh := BoxMesh.new()
    mesh.size = box.size
    crate.mesh = mesh
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.52, 0.31, 0.12)
    material.roughness = 0.85
    crate.material_override = material
    barricade_body.add_child(crate)
    add_child(barricade_body)


func toggle_dynamic_barricade(at_world: Vector3) -> bool:
    if not is_node_ready() or streaming_lod != 0:
        return false
    var partition := get_parent() as WorldPartition3D
    if partition == null or not partition.mark_cell_navigation_dirty(Vector2i(cell_x, cell_z)):
        return false # Never change collision without scheduling a NavMesh update.
    if barricade_active:
        barricade_active = false
        if is_instance_valid(barricade_body):
            barricade_body.queue_free()
            barricade_body = null
    else:
        var local: Vector3 = to_local(at_world)
        if not local.is_finite():
            return false
        local.x = clampf(local.x, 3.0, CELL_SIZE - 3.0)
        local.z = clampf(local.z, 3.0, CELL_SIZE - 3.0)
        local.y = _world_height(local.x, local.z) + 0.8
        barricade_local_position = local
        barricade_active = true
        _create_barricade_visual()
    return true


func _sync_navigation_region() -> void:
    if streaming_lod != 0:
        return # A distant LOD scene never allocates a navigation region.
    if not streaming_navigation_active:
        if is_instance_valid(navigation_region):
            navigation_region.enabled = false
        return
    if not is_instance_valid(navigation_region):
        # Cached once per loaded cell; regenerated only on unload/reload.
        if navigation_mesh_cache == null:
            navigation_mesh_cache = _build_current_navigation_mesh()
        if navigation_mesh_cache == null or navigation_mesh_cache.get_polygon_count() == 0:
            return
        navigation_region = NavigationRegion3D.new()
        navigation_region.name = "StreamingNavigationRegion"
        navigation_region.use_edge_connections = true
        navigation_region.navigation_layers = 1
        navigation_region.navigation_mesh = navigation_mesh_cache
        navigation_region.enabled = true
        add_child(navigation_region)
    else:
        navigation_region.enabled = true


func is_streaming_navigation_ready() -> bool:
    # Engine additionally waits two physics frames for NavigationServer3D
    # synchronization; this callback checks only this region's local setup.
    return is_node_ready() and streaming_lod == 0 and streaming_navigation_active \
        and is_instance_valid(navigation_region) and navigation_region.enabled \
        and navigation_region.is_inside_tree() \
        and navigation_region.navigation_mesh != null \
        and navigation_region.navigation_mesh.get_polygon_count() > 0 \
        and navigation_region.get_navigation_map().is_valid()


func is_streaming_physics_ready() -> bool:
    # Remote urgent travel requires a populated near-detail scene and active
    # obstacle body. The separate terrain heightfield is always resident.
    return is_node_ready() and streaming_physics_active and streaming_lod == 0 \
        and is_instance_valid(obstacles) and obstacles.collision_layer == 1 \
        and obstacles.get_child_count() > 0


func is_streaming_activation_ready() -> bool:
    # An opt-in scene activation check supplements the engine's minimum
    # completed physics frames. Near LOD builds colliders during _ready();
    # far LOD has no authored obstacle physics and remains graphics-only.
    return is_node_ready() and (streaming_lod == 1 or
        (is_instance_valid(obstacles) and obstacles.get_child_count() > 0))


func _update_simulation_processing() -> void:
    # An optional near-field ambient effect; static foliage remains visible
    # while this cell's simulation callback is paused.
    set_process(streaming_simulation_active and cell_x == 0 and cell_z == 0)


func _process(delta: float) -> void:
    beacon_time += delta
    var lamp := get_node_or_null("PinnedHomeBeacon/HubLight") as OmniLight3D
    if lamp != null:
        lamp.light_energy = 0.45 + 0.06 * sin(beacon_time * 2.2)


func set_streaming_lod(level: int) -> void:
    # The streamer can call this before this Node3D enters the scene tree.
    # At runtime, rebuild only if the level actually changed.
    var next_level: int = clampi(level, 0, 1)
    if streaming_lod == next_level:
        return
    streaming_lod = next_level
    if is_node_ready():
        _rebuild_lod()


func _rebuild_lod() -> void:
    # Each cell has no authored children; only the root script. Remove previous
    # generated geometry/colliders immediately, defer freeing their resources.
    for generated in get_children():
        remove_child(generated)
        generated.queue_free()
    grass = null
    obstacles = null
    navigation_region = null # Old region is queued for removal with the LOD.
    barricade_body = null # Preserve state while regenerating the cell's LOD.
    navigation_mesh_cache = null # Invalidate if authored obstacle geometry changes.
    navigation_blockers.clear()
    rng.seed = cell_seed

    if streaming_lod == 0:
        obstacles = StaticBody3D.new()
        obstacles.name = "FoliageCollisions"
        obstacles.collision_layer = 1 if streaming_physics_active else 0
        obstacles.collision_mask = 0
        add_child(obstacles)

    # Even far cells retain silhouettes using MultiMesh, but no grass,
    # individual tree/rock colliders, shadow maps, or small stones.
    _spawn_trees()
    if streaming_lod == 0:
        _spawn_grass()
        _spawn_rocks()
        if cell_x == 0 and cell_z == 0:
            _spawn_home_beacon()
    set_high_quality(high_quality)
    _create_barricade_visual()
    _sync_navigation_region()


func _world_height(local_x: float, local_z: float) -> float:
    return TerrainHeight.height_at(global_position.x + local_x,
        global_position.z + local_z) - global_position.y


func _spawn_trees() -> void:
    var trunk_mesh := CylinderMesh.new()
    trunk_mesh.top_radius = 0.25
    trunk_mesh.bottom_radius = 0.40
    trunk_mesh.height = 3.8
    trunk_mesh.radial_segments = 7
    var bark := StandardMaterial3D.new()
    bark.albedo_color = Color(0.22, 0.12, 0.078)
    bark.roughness = 0.96
    trunk_mesh.material = bark

    var foliage_mesh := SphereMesh.new()
    foliage_mesh.radius = 1.0
    foliage_mesh.height = 2.0
    foliage_mesh.radial_segments = 11 if streaming_lod == 0 else 7
    foliage_mesh.rings = 6 if streaming_lod == 0 else 4
    var wind := ShaderMaterial.new()
    wind.shader = preload("res://shaders/foliage_wind.gdshader")
    foliage_mesh.material = wind

    var trunks: Array[Transform3D] = []
    var crowns: Array[Transform3D] = []
    var custom: Array[Color] = []
    var tree_count: int = TREE_COUNT if streaming_lod == 0 else DISTANT_TREE_COUNT
    for i in range(tree_count):
        var px: float = rng.randf_range(3.0, CELL_SIZE - 3.0)
        var pz: float = rng.randf_range(3.0, CELL_SIZE - 3.0)
        if absf(pz - CELL_SIZE * 0.5) < 4.7:
            continue # Keep a continuous walkable central trail across tiles.
        var wx: float = global_position.x + px
        var wz: float = global_position.z + pz
        if Vector2(wx, wz - 9.0).length() < 8.0:
            continue # Keep the player's first clearing open.
        var scale: float = rng.randf_range(0.70, 1.5)
        var ground: float = _world_height(px, pz)
        var orientation := Basis(Vector3.UP, rng.randf_range(-PI, PI))
        if streaming_lod == 0:
            navigation_blockers.append(Vector3(px, pz, 0.34 * scale))
        trunks.push_back(Transform3D(
            orientation.scaled(Vector3(scale * 0.75, scale, scale * 0.75)),
            Vector3(px, ground + scale * 1.90, pz)))
        crowns.push_back(Transform3D(
            orientation.scaled(Vector3(scale * 2.0, scale * 1.75, scale * 2.0)),
            Vector3(px, ground + scale * 4.15, pz)))
        custom.push_back(Color(rng.randf(), rng.randf(), rng.randf(), 1.0))
    _spawn_instances("TreeTrunks", trunk_mesh, trunks, custom, true, false)
    _spawn_instances("WindCanopies", foliage_mesh, crowns, custom, true, false)
    # Distant cells do not allocate physics. Near cells keep simple primitives.
    if obstacles == null:
        return
    for trunk_transform in trunks:
        var scale: float = trunk_transform.basis.y.length()
        var cylinder := CylinderShape3D.new()
        cylinder.radius = 0.32 * scale
        cylinder.height = 3.8 * scale
        var collision := CollisionShape3D.new()
        collision.shape = cylinder
        collision.position = trunk_transform.origin
        obstacles.add_child(collision)


func _spawn_grass() -> void:
    var blade := QuadMesh.new()
    blade.size = Vector2(0.34, 0.75)
    var grass_material := ShaderMaterial.new()
    grass_material.shader = preload("res://shaders/grass_wind.gdshader")
    blade.material = grass_material

    var transforms: Array[Transform3D] = []
    var custom: Array[Color] = []
    for i in range(GRASS_COUNT):
        var px: float = rng.randf_range(0.0, CELL_SIZE)
        var pz: float = rng.randf_range(0.0, CELL_SIZE)
        var scale: float = rng.randf_range(0.6, 1.6)
        var orientation := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
        transforms.push_back(Transform3D(
            orientation.scaled(Vector3(scale, scale, scale)),
            Vector3(px, _world_height(px, pz) + scale * 0.36, pz)))
        custom.push_back(Color(rng.randf(), rng.randf(), 0.0, 1.0))
    grass = _spawn_instances("WindGrass", blade, transforms, custom, false, true)


func _spawn_rocks() -> void:
    var rock := SphereMesh.new()
    rock.radius = 1.0
    rock.height = 2.0
    rock.radial_segments = 8
    rock.rings = 4
    var stone := StandardMaterial3D.new()
    stone.albedo_color = Color(0.28, 0.31, 0.29)
    stone.roughness = 0.92
    rock.material = stone
    var transforms: Array[Transform3D] = []
    var custom: Array[Color] = []
    for i in range(ROCK_COUNT):
        var px: float = rng.randf_range(3.0, CELL_SIZE - 3.0)
        var pz: float = rng.randf_range(3.0, CELL_SIZE - 3.0)
        if absf(pz - CELL_SIZE * 0.5) < 4.7:
            continue # Keep enough room for a radius-aware navmesh corridor.
        var scale: float = rng.randf_range(0.45, 1.6)
        var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
        # Conservative footprint radius for the oriented rock collision box.
        navigation_blockers.append(Vector3(px, pz, 1.25 * scale))
        transforms.push_back(Transform3D(
            basis.scaled(Vector3(scale * 1.4, scale * 0.45, scale)),
            Vector3(px, _world_height(px, pz) + scale * 0.15, pz)))
        custom.push_back(Color.WHITE)
    _spawn_instances("Stones", rock, transforms, custom, true, false)
    for rock_transform in transforms:
        var scale: float = rock_transform.basis.z.length()
        var stone_shape := BoxShape3D.new()
        stone_shape.size = Vector3(scale * 1.9, scale * 0.55, scale * 1.5)
        var collision := CollisionShape3D.new()
        collision.shape = stone_shape
        collision.transform = Transform3D(rock_transform.basis.orthonormalized(),
            rock_transform.origin)
        obstacles.add_child(collision)


func _spawn_instances(label: String, mesh: Mesh,
        transforms: Array[Transform3D], custom: Array[Color],
        cast_shadows: bool, is_grass: bool) -> MultiMeshInstance3D:
    var multi := MultiMesh.new()
    multi.transform_format = MultiMesh.TRANSFORM_3D
    multi.use_custom_data = true
    multi.mesh = mesh
    multi.instance_count = transforms.size()
    for i in range(transforms.size()):
        multi.set_instance_transform(i, transforms[i])
        multi.set_instance_custom_data(i, custom[i])

    var node := MultiMeshInstance3D.new()
    node.name = label
    node.multimesh = multi
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows and streaming_lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    if is_grass:
        node.visibility_range_end = 64.0
        node.visibility_range_end_margin = 11.0
        node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
    else:
        node.visibility_range_end = 145.0
    add_child(node)
    return node


func _spawn_home_beacon() -> void:
    # This light marks the permanent hub as a real streamed scene object.
    # It remains loaded while the player explores, without adding a shadow map.
    var marker := Node3D.new()
    marker.name = "PinnedHomeBeacon"
    marker.position = Vector3(3.0, _world_height(3.0, 9.0), 9.0)
    add_child(marker)

    var base := CylinderMesh.new()
    base.top_radius = 0.55
    base.bottom_radius = 0.80
    base.height = 0.28
    var stone := StandardMaterial3D.new()
    stone.albedo_color = Color(0.19, 0.22, 0.25)
    stone.roughness = 0.9
    base.material = stone
    var pedestal := MeshInstance3D.new()
    pedestal.name = "Pedestal"
    pedestal.mesh = base
    pedestal.position.y = 0.14
    marker.add_child(pedestal)

    var lantern := SphereMesh.new()
    lantern.radius = 0.32
    lantern.height = 0.64
    var glow := StandardMaterial3D.new()
    glow.albedo_color = Color(0.25, 0.75, 0.94)
    glow.roughness = 0.2
    glow.emission_enabled = true
    glow.emission = Color(0.12, 0.60, 1.0)
    glow.emission_energy_multiplier = 5.0
    lantern.material = glow
    var orb := MeshInstance3D.new()
    orb.name = "HubLantern"
    orb.mesh = lantern
    orb.position.y = 1.55
    marker.add_child(orb)

    var lamp := OmniLight3D.new()
    lamp.name = "HubLight"
    lamp.position.y = 1.55
    lamp.light_color = Color(0.38, 0.78, 1.0)
    lamp.light_energy = 0.45
    lamp.omni_range = 7.0
    lamp.shadow_enabled = false
    marker.add_child(lamp)


func set_high_quality(high: bool) -> void:
    high_quality = high
    if grass != null:
        var count: int = grass.multimesh.instance_count
        grass.multimesh.visible_instance_count = -1 if high else int(count * 0.50)
