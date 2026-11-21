extends MultiMeshInstance3D
## Procedural, collision-free foliage in one instanced draw batch.
## Exclusion spheres protect spawn, scavenging resources, and ruined structures.
## The native engine filter and the stock-Godot fallback share stable input order.

const GRID_SIZE: int = 25
const MAX_INSTANCES: int = 160
const MIN_SPACING: float = 2.1
const ZONE_CENTERS = [
    Vector3(0.0, 0.0, 3.0),    # Player spawn
    Vector3(-2.0, 0.0, -3.0),  # Water scavenging cluster
    Vector3(2.0, 0.0, -4.0),   # Food ration
    Vector3(3.5, 0.0, -8.0),  # Scrap and approach
    Vector3(-2.0, 0.0, -12.0),# Ruined building
    Vector3(8.0, 0.0, -11.0), # East ruin
    Vector3(10.0, 0.0, 5.0),  # Scrap container
    Vector3(6.0, 0.0, 0.0),   # Barricade
    Vector3(-5.0, 0.0, 1.0),  # Fallen timber
    Vector3(9.0, 0.0, -4.0),  # Tree stump
]
const ZONE_RADII = [3.5, 2.7, 2.3, 2.5, 6.0, 4.0, 3.4, 3.0, 2.2, 2.2]

var _selected_positions := PackedVector3Array()


func _ready() -> void:
    regenerate()


func get_selected_positions() -> PackedVector3Array:
    return _selected_positions.duplicate()


func get_exclusion_centers() -> PackedVector3Array:
    return PackedVector3Array(ZONE_CENTERS)


func get_exclusion_radii() -> PackedFloat64Array:
    return PackedFloat64Array(ZONE_RADII)


func _make_candidates() -> PackedVector3Array:
    var candidates := PackedVector3Array()
    # 137 is coprime to 625, so each grid cell is visited exactly once.
    # Reordered placement spreads the capped output across the entire zone.
    for index in range(GRID_SIZE * GRID_SIZE):
        var cell: int = (index * 137) % (GRID_SIZE * GRID_SIZE)
        var x: int = cell % GRID_SIZE
        var z: int = floori(float(cell) / float(GRID_SIZE))
        var jitter_x: float = float(((cell * 17 + 5) % 11) - 5) * 0.035
        var jitter_z: float = float(((cell * 29 + 3) % 11) - 5) * 0.035
        candidates.push_back(Vector3(-28.8 + float(x) * 2.4 + jitter_x,
            0.22, -28.8 + float(z) * 2.4 + jitter_z))
    return candidates


func _filter_fallback(candidates: PackedVector3Array,
        centers: PackedVector3Array, radii: PackedFloat64Array) -> PackedInt32Array:
    var indices := PackedInt32Array()
    for index in range(candidates.size()):
        var excluded: bool = false
        for zone in range(centers.size()):
            if candidates[index].distance_squared_to(centers[zone]) <= radii[zone] * radii[zone]:
                excluded = true
                break
        if excluded:
            continue
        var blocked: bool = false
        for previous in indices:
            if candidates[index].distance_squared_to(candidates[previous]) < MIN_SPACING * MIN_SPACING:
                blocked = true
                break
        if not blocked:
            indices.push_back(index)
            if indices.size() >= MAX_INSTANCES:
                break
    return indices


func _select_indices(candidates: PackedVector3Array,
        centers: PackedVector3Array, radii: PackedFloat64Array) -> PackedInt32Array:
    if ClassDB.class_exists("PCGSpatialFilter3D"):
        var filter: Object = ClassDB.instantiate("PCGSpatialFilter3D")
        if filter != null and filter.has_method("filter_indices_excluding"):
            return filter.call("filter_indices_excluding", candidates,
                centers, radii, MIN_SPACING, MAX_INSTANCES)
    return _filter_fallback(candidates, centers, radii)


func verify_native_fallback_parity() -> bool:
    var candidates := _make_candidates()
    var centers := get_exclusion_centers()
    var radii := get_exclusion_radii()
    return _select_indices(candidates, centers, radii) == _filter_fallback(candidates, centers, radii)


func regenerate() -> void:
    var candidates := _make_candidates()
    var selected := _select_indices(candidates,
        get_exclusion_centers(), get_exclusion_radii())
    _selected_positions.clear()
    for index in selected:
        _selected_positions.push_back(candidates[index])

    var blades := BoxMesh.new()
    blades.size = Vector3(0.10, 0.44, 0.10)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.28, 0.38, 0.23)
    material.roughness = 1.0
    blades.material = material
    var batch := MultiMesh.new()
    batch.transform_format = MultiMesh.TRANSFORM_3D
    batch.mesh = blades
    batch.instance_count = _selected_positions.size()
    for i in range(_selected_positions.size()):
        var orientation := Basis(Vector3.UP, float(i) * 0.41)
        orientation = orientation.scaled(Vector3(1.0, 0.8 + 0.1 * float(i % 5), 1.0))
        batch.set_instance_transform(i, Transform3D(orientation, _selected_positions[i]))
    multimesh = batch
    cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
