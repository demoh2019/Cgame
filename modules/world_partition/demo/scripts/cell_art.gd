extends Node3D

# Authorable placeholder art: same scene contracts as imported low/high-detail assets.
# Geometry is deterministic, with MultiMesh draw-call batching per cell.
@export var proxy: bool = false

const CELL_SIZE := 128.0
const TREE_COUNT := 160
const PROXY_STRIDE := 8

static var _trunk_mesh: CylinderMesh
static var _crown_detail_mesh: SphereMesh
static var _crown_proxy_mesh: SphereMesh
static var _ground_mesh: PlaneMesh
static var _trunk_material: StandardMaterial3D
static var _leaf_material: StandardMaterial3D
static var _ground_material: StandardMaterial3D

func _ready() -> void:
    _ensure_shared_resources()

    var ground := MeshInstance3D.new()
    ground.name = "Ground"
    ground.mesh = _ground_mesh
    ground.position = Vector3(CELL_SIZE / 2.0, -0.07 if proxy else -0.03, CELL_SIZE / 2.0)
    add_child(ground)

    var count: int = TREE_COUNT / PROXY_STRIDE if proxy else TREE_COUNT
    var trunks := _build_multimesh(_trunk_mesh, count)
    var crowns := _build_multimesh(_crown_proxy_mesh if proxy else _crown_detail_mesh, count)
    var grid := Vector2i(roundi(position.x / CELL_SIZE), roundi(position.z / CELL_SIZE))
    var rng := RandomNumberGenerator.new()
    rng.seed = int(500003 + (grid.x + 1000) * 73856093 + (grid.y + 1000) * 19349663)
    var output_index := 0
    for i in TREE_COUNT:
        var x := rng.randf_range(4.0, 124.0)
        var z := rng.randf_range(4.0, 124.0)
        var height := rng.randf_range(4.0, 8.0)
        var width := rng.randf_range(0.70, 1.12)
        if proxy and i % PROXY_STRIDE != 0:
            continue
        trunks.set_instance_transform(
            output_index,
            Transform3D(Basis().scaled(Vector3(0.65 * width, height, 0.65 * width)), Vector3(x, height / 2.0, z))
        )
        crowns.set_instance_transform(
            output_index,
            Transform3D(Basis().scaled(Vector3(3.3 * width, 3.6, 3.3 * width)), Vector3(x, height + 1.9, z))
        )
        output_index += 1

    _add_instances("Trunks", trunks)
    _add_instances("Canopies", crowns)

func _build_multimesh(mesh: Mesh, count: int) -> MultiMesh:
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.mesh = mesh
    mm.instance_count = count
    return mm

func _add_instances(name: String, mm: MultiMesh) -> void:
    var instance := MultiMeshInstance3D.new()
    instance.name = name
    instance.multimesh = mm
    add_child(instance)

func _ensure_shared_resources() -> void:
    if _trunk_mesh != null:
        return
    _trunk_material = StandardMaterial3D.new()
    _trunk_material.albedo_color = Color(0.29, 0.22, 0.16)
    _trunk_material.roughness = 1.0
    _leaf_material = StandardMaterial3D.new()
    _leaf_material.albedo_color = Color(0.08, 0.27, 0.13)
    _leaf_material.roughness = 0.95
    _ground_material = StandardMaterial3D.new()
    _ground_material.albedo_color = Color(0.19, 0.31, 0.20)
    _ground_material.roughness = 1.0

    _trunk_mesh = CylinderMesh.new()
    _trunk_mesh.top_radius = 0.4
    _trunk_mesh.bottom_radius = 0.5
    _trunk_mesh.height = 1.0
    _trunk_mesh.material = _trunk_material

    _crown_detail_mesh = SphereMesh.new()
    _crown_detail_mesh.radial_segments = 12
    _crown_detail_mesh.rings = 6
    _crown_detail_mesh.material = _leaf_material

    _crown_proxy_mesh = SphereMesh.new()
    _crown_proxy_mesh.radial_segments = 6
    _crown_proxy_mesh.rings = 3
    _crown_proxy_mesh.material = _leaf_material

    _ground_mesh = PlaneMesh.new()
    _ground_mesh.size = Vector2(CELL_SIZE, CELL_SIZE)
    _ground_mesh.material = _ground_material
