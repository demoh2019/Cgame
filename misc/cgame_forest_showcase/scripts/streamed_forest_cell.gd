extends Node3D
## One reusable PackedScene streams in any WorldPartition3D cell.
## The engine positions this root at its cell origin before _ready().
## Per-cell deterministic seeds keep the same foliage layout on reload.

const TerrainHeight = preload("res://scripts/terrain_height.gd")
const TerrainPatch = preload("res://scripts/streamed_terrain_patch.gd")
const CELL_SIZE: float = 32.0
const TREE_COUNT: int = 54
const GRASS_COUNT: int = 225
const ROCK_COUNT: int = 9

var rng := RandomNumberGenerator.new()
var grass: MultiMeshInstance3D
var obstacles: StaticBody3D
var high_quality: bool = true


func _ready() -> void:
    var cell_x: int = int(round(global_position.x / CELL_SIZE))
    var cell_z: int = int(round(global_position.z / CELL_SIZE))
    rng.seed = 913481 + cell_x * 73856093 + cell_z * 19349663

    # Terrain geometry and heightfield physics are tied to the exact same cell
    # lifecycle as vegetation. No world-wide monolithic mesh stays resident.
    var ground := TerrainPatch.new()
    ground.name = "TerrainPatch"
    add_child(ground)

    # A single static body groups primitive collision shapes for this cell.
    # The engine unloads these shapes together with the visual vegetation.
    obstacles = StaticBody3D.new()
    obstacles.name = "FoliageCollisions"
    obstacles.collision_layer = 1
    obstacles.collision_mask = 0
    add_child(obstacles)
    _spawn_trees()
    _spawn_grass()
    _spawn_rocks()
    set_high_quality(high_quality)


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
    foliage_mesh.radial_segments = 11
    foliage_mesh.rings = 6
    var wind := ShaderMaterial.new()
    wind.shader = preload("res://shaders/foliage_wind.gdshader")
    foliage_mesh.material = wind

    var trunks: Array[Transform3D] = []
    var crowns: Array[Transform3D] = []
    var custom: Array[Color] = []
    for i in range(TREE_COUNT):
        var px: float = rng.randf_range(1.0, CELL_SIZE - 1.0)
        var pz: float = rng.randf_range(1.0, CELL_SIZE - 1.0)
        var wx: float = global_position.x + px
        var wz: float = global_position.z + pz
        if Vector2(wx, wz - 9.0).length() < 8.0:
            continue # Keep the player's first clearing open.
        var scale: float = rng.randf_range(0.70, 1.5)
        var ground: float = _world_height(px, pz)
        var orientation := Basis(Vector3.UP, rng.randf_range(-PI, PI))
        trunks.push_back(Transform3D(
            orientation.scaled(Vector3(scale * 0.75, scale, scale * 0.75)),
            Vector3(px, ground + scale * 1.90, pz)))
        crowns.push_back(Transform3D(
            orientation.scaled(Vector3(scale * 2.0, scale * 1.75, scale * 2.0)),
            Vector3(px, ground + scale * 4.15, pz)))
        custom.push_back(Color(rng.randf(), rng.randf(), rng.randf(), 1.0))
    _spawn_instances("TreeTrunks", trunk_mesh, trunks, custom, true, false)
    _spawn_instances("WindCanopies", foliage_mesh, crowns, custom, true, false)
    # MultiMesh is draw-only; collision shapes must be authored separately.
    # Keep capsule-based player collision cheap with primitive cylinders.
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
        var px: float = rng.randf_range(0.0, CELL_SIZE)
        var pz: float = rng.randf_range(0.0, CELL_SIZE)
        var scale: float = rng.randf_range(0.45, 1.6)
        var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
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
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    if is_grass:
        node.visibility_range_end = 64.0
        node.visibility_range_end_margin = 11.0
        node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
    else:
        node.visibility_range_end = 145.0
    add_child(node)
    return node


func set_high_quality(high: bool) -> void:
    high_quality = high
    if grass != null:
        var count: int = grass.multimesh.instance_count
        grass.multimesh.visible_instance_count = -1 if high else int(count * 0.50)
