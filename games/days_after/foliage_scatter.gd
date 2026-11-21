extends MultiMeshInstance3D
## Procedural, collision-free foliage in one instanced draw batch.
## Exclusion spheres protect spawn, scavenging resources, and ruined structures.
## Native PCG and stock-Godot fallback agree on stable-ID density and exclusions.

const GRID_SIZE: int = 25
const MAX_INSTANCES: int = 160
const MIN_SPACING: float = 2.1
const DENSITY_SEED: int = 90421
const DENSITY_MODULUS: int = 2147483647
const TRAIL_INNER_RADIUS: float = 1.8
const TRAIL_OUTER_RADIUS: float = 6.0
# Editable waypoint polyline: a curved walkable route from outskirts to ruins.
const TRAIL_POINTS = [
    Vector3(7.0, 0.0, 26.0),
    Vector3(4.0, 0.0, 13.0),
    Vector3(0.0, 0.0, 3.0),
    Vector3(-2.0, 0.0, -12.0),
    Vector3(-7.0, 0.0, -26.0),
]
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
# Unlike spheres, boxes closely fit elongated ruin walls and containers.
# Keep geometry presentation-only: no physics/interaction shape is culled.
const BOX_MINS = [
    Vector3(-9.8, -1.0, -18.0),  # RuinWest wall
    Vector3(-9.5, -1.0, -17.7),  # RuinNorth wall
    Vector3(6.3, -1.0, -16.0),   # RuinEast wall
    Vector3(3.3, -1.0, -1.5),    # Barricade footprint
    Vector3(7.6, -1.0, 2.0),     # Scrap container footprint
    Vector3(-4.2, -1.0, -7.2),   # Supply crate
]
const BOX_MAXS = [
    Vector3(-6.3, 1.3, -4.0),
    Vector3(5.6, 1.3, -14.2),
    Vector3(9.7, 1.3, -5.5),
    Vector3(8.7, 1.3, 1.5),
    Vector3(12.4, 1.3, 8.0),
    Vector3(-1.8, 1.3, -4.8),
]

# An actual angled fence in main.gd, not an inflated axis-aligned box.
# Centers and half-extents are in world units, yaws use Godot +Y radians.
const ORIENTED_BOX_CENTERS = [Vector3(13.0, 0.7, 13.0)]
const ORIENTED_BOX_HALF_EXTENTS = [Vector3(5.4, 1.4, 1.4)]
const ORIENTED_BOX_YAWS = [deg_to_rad(35.0)]

var _selected_positions := PackedVector3Array()


func _ready() -> void:
    regenerate()


func get_selected_positions() -> PackedVector3Array:
    return _selected_positions.duplicate()


func get_exclusion_centers() -> PackedVector3Array:
    return PackedVector3Array(ZONE_CENTERS)


func get_exclusion_radii() -> PackedFloat64Array:
    return PackedFloat64Array(ZONE_RADII)


func get_exclusion_box_mins() -> PackedVector3Array:
    return PackedVector3Array(BOX_MINS)


func get_exclusion_box_maxs() -> PackedVector3Array:
    return PackedVector3Array(BOX_MAXS)


func get_oriented_box_centers() -> PackedVector3Array:
    return PackedVector3Array(ORIENTED_BOX_CENTERS)


func get_oriented_box_half_extents() -> PackedVector3Array:
    return PackedVector3Array(ORIENTED_BOX_HALF_EXTENTS)


func get_oriented_box_yaws() -> PackedFloat64Array:
    return PackedFloat64Array(ORIENTED_BOX_YAWS)


func _make_ids() -> PackedInt32Array:
    var stable_ids := PackedInt32Array()
    for index in range(GRID_SIZE * GRID_SIZE):
        # Physical grid-cell ID, independent of input-array order.
        stable_ids.push_back((index * 137) % (GRID_SIZE * GRID_SIZE))
    return stable_ids


func get_trail_points() -> PackedVector3Array:
    return PackedVector3Array(TRAIL_POINTS)


func get_trail_inner_radius() -> float:
    return TRAIL_INNER_RADIUS


func get_trail_outer_radius() -> float:
    return TRAIL_OUTER_RADIUS


func _sample_trail_fallback(positions: PackedVector3Array) -> PackedFloat32Array:
    var path := get_trail_points()
    var factors := PackedFloat32Array()
    for point in positions:
        var nearest_squared: float = INF
        for segment in range(path.size() - 1):
            var a: Vector3 = path[segment]
            var b: Vector3 = path[segment + 1]
            var dx: float = b.x - a.x
            var dz: float = b.z - a.z
            var length_squared: float = dx * dx + dz * dz
            var along: float = 0.0
            if length_squared > 0.0:
                along = clampf(((point.x - a.x) * dx +
                    (point.z - a.z) * dz) / length_squared, 0.0, 1.0)
            var off_x: float = point.x - (a.x + along * dx)
            var off_z: float = point.z - (a.z + along * dz)
            nearest_squared = minf(nearest_squared, off_x * off_x + off_z * off_z)
        if nearest_squared <= TRAIL_INNER_RADIUS * TRAIL_INNER_RADIUS:
            factors.push_back(0.0)
        elif nearest_squared >= TRAIL_OUTER_RADIUS * TRAIL_OUTER_RADIUS:
            factors.push_back(1.0)
        else:
            var t: float = (sqrt(nearest_squared) - TRAIL_INNER_RADIUS) / (
                TRAIL_OUTER_RADIUS - TRAIL_INNER_RADIUS)
            factors.push_back(t * t * (3.0 - 2.0 * t))
    return factors


func get_trail_factors(prefer_native: bool = true) -> PackedFloat32Array:
    var positions := _make_candidates()
    if prefer_native and ClassDB.class_exists("PCGPathFalloff3D"):
        var path_filter: Object = ClassDB.instantiate("PCGPathFalloff3D")
        if path_filter != null and path_filter.has_method("sample_factors"):
            return path_filter.call("sample_factors", positions,
                get_trail_points(), TRAIL_INNER_RADIUS, TRAIL_OUTER_RADIUS)
    return _sample_trail_fallback(positions)


func verify_trail_native_fallback_parity() -> bool:
    var native_mask: PackedFloat32Array = get_trail_factors()
    var fallback_mask: PackedFloat32Array = get_trail_factors(false)
    if native_mask.size() != fallback_mask.size():
        return false
    for i in range(native_mask.size()):
        if absf(native_mask[i] - fallback_mask[i]) > 0.00002:
            return false
    return true


func _make_densities(prefer_native: bool = true) -> PackedFloat32Array:
    var densities := PackedFloat32Array()
    for index in range(GRID_SIZE * GRID_SIZE):
        var cell: int = (index * 137) % (GRID_SIZE * GRID_SIZE)
        var x: int = cell % GRID_SIZE
        var z: int = floori(float(cell) / float(GRID_SIZE))
        # A worn north-south approach has little vegetation, while
        # undisturbed outer woodland is much denser.
        var density: float = 0.94
        if x >= 10 and x <= 14:
            density = 0.13
        elif z < 6:
            density = 0.46
        elif x < 8:
            density = 0.74
        densities.push_back(density)
    # Feed this smooth trail-distance mask into the seeded native density
    # sampler; no per-instance physics or extra renderer draw calls.
    var trail_factors: PackedFloat32Array = get_trail_factors(prefer_native)
    for i in range(densities.size()):
        densities.set(i, densities[i] * trail_factors[i])
    return densities


func get_density_values() -> PackedFloat32Array:
    return _make_densities()


func _density_accepts(stable_id: int, density: float) -> bool:
    var hashed: int = (stable_id * 48271 + DENSITY_SEED * 69621 + 1729) % DENSITY_MODULUS
    hashed = (hashed * 16807 + 13) % DENSITY_MODULUS
    return float(hashed) / float(DENSITY_MODULUS) < density


func _density_fallback(densities: PackedFloat32Array,
        stable_ids: PackedInt32Array) -> PackedInt32Array:
    var indices := PackedInt32Array()
    for i in range(densities.size()):
        if _density_accepts(stable_ids[i], densities[i]):
            indices.push_back(i)
    return indices


func get_density_sampled_count() -> int:
    return _density_fallback(_make_densities(), _make_ids()).size()


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


func _in_any_box(point: Vector3,
        box_mins: PackedVector3Array, box_maxs: PackedVector3Array) -> bool:
    for b in range(box_mins.size()):
        var lo: Vector3 = box_mins[b]
        var hi: Vector3 = box_maxs[b]
        if (point.x >= lo.x and point.x <= hi.x
                and point.y >= lo.y and point.y <= hi.y
                and point.z >= lo.z and point.z <= hi.z):
            return true
    return false


# Inverse of Godot Y-axis yaw (local X points toward world -Z).
# Inclusive boundaries keep foliage clear of rotated wall collisions.
func _in_any_oriented_box(point: Vector3,
        oriented_centers: PackedVector3Array,
        oriented_half_extents: PackedVector3Array,
        oriented_yaws: PackedFloat64Array) -> bool:
    for b in range(oriented_centers.size()):
        var offset: Vector3 = point - oriented_centers[b]
        var yaw: float = oriented_yaws[b]
        var lx: float = cos(yaw) * offset.x - sin(yaw) * offset.z
        var lz: float = sin(yaw) * offset.x + cos(yaw) * offset.z
        var half: Vector3 = oriented_half_extents[b]
        if absf(lx) <= half.x and absf(offset.y) <= half.y and absf(lz) <= half.z:
            return true
    return false


func _filter_fallback(candidates: PackedVector3Array,
        centers: PackedVector3Array, radii: PackedFloat64Array,
        box_mins: PackedVector3Array, box_maxs: PackedVector3Array,
        sampled_indices: PackedInt32Array) -> PackedInt32Array:
    var indices := PackedInt32Array()
    var obb_centers := get_oriented_box_centers()
    var obb_halves := get_oriented_box_half_extents()
    var obb_yaws := get_oriented_box_yaws()
    for index in sampled_indices:
        var point: Vector3 = candidates[index]
        if _in_any_box(point, box_mins, box_maxs) or \
                _in_any_oriented_box(point, obb_centers, obb_halves, obb_yaws):
            continue
        var excluded: bool = false
        for zone in range(centers.size()):
            if point.distance_squared_to(centers[zone]) <= radii[zone] * radii[zone]:
                excluded = true
                break
        if excluded:
            continue
        var blocked: bool = false
        for previous in indices:
            if point.distance_squared_to(candidates[previous]) < MIN_SPACING * MIN_SPACING:
                blocked = true
                break
        if not blocked:
            indices.push_back(index)
            if indices.size() >= MAX_INSTANCES:
                break
    return indices


func _select_indices(candidates: PackedVector3Array,
        centers: PackedVector3Array, radii: PackedFloat64Array,
        box_mins: PackedVector3Array, box_maxs: PackedVector3Array,
        prefer_native: bool = true) -> PackedInt32Array:
    var densities := _make_densities(prefer_native)
    var stable_ids := _make_ids()
    if prefer_native and ClassDB.class_exists("PCGSpatialFilter3D"):
        var filter: Object = ClassDB.instantiate("PCGSpatialFilter3D")
        if (filter != null and filter.has_method("filter_indices_density")
                and filter.has_method("filter_indices_excluding_oriented_volumes")):
            var sampled: PackedInt32Array = filter.call("filter_indices_density",
                candidates, densities, stable_ids, DENSITY_SEED, 4096)
            var sampled_positions := PackedVector3Array()
            for index in sampled:
                sampled_positions.push_back(candidates[index])
            var local_indices: PackedInt32Array = filter.call(
                "filter_indices_excluding_oriented_volumes", sampled_positions,
                centers, radii, box_mins, box_maxs,
                get_oriented_box_centers(), get_oriented_box_half_extents(),
                get_oriented_box_yaws(), MIN_SPACING, MAX_INSTANCES)
            var selected := PackedInt32Array()
            for local_index in local_indices:
                selected.push_back(sampled[local_index])
            return selected
    return _filter_fallback(candidates, centers, radii, box_mins,
        box_maxs, _density_fallback(densities, stable_ids))


func get_box_only_candidate_count() -> int:
    # Confirms rectangular footprints are actually doing additional work.
    var candidates := _make_candidates()
    var box_mins := get_exclusion_box_mins()
    var box_maxs := get_exclusion_box_maxs()
    var centers := get_exclusion_centers()
    var radii := get_exclusion_radii()
    var count: int = 0
    for point in candidates:
        if not _in_any_box(point, box_mins, box_maxs):
            continue
        var in_sphere: bool = false
        for z in range(centers.size()):
            if point.distance_squared_to(centers[z]) <= radii[z] * radii[z]:
                in_sphere = true
                break
        if not in_sphere:
            count += 1
    return count


func get_oriented_box_only_candidate_count() -> int:
    # Explicitly verifies that the rotated wall excludes candidates which
    # would survive the existing spheres/AABBs (no accidental no-op).
    var candidates := _make_candidates()
    var box_mins := get_exclusion_box_mins()
    var box_maxs := get_exclusion_box_maxs()
    var obb_centers := get_oriented_box_centers()
    var obb_halves := get_oriented_box_half_extents()
    var obb_yaws := get_oriented_box_yaws()
    var centers := get_exclusion_centers()
    var radii := get_exclusion_radii()
    var count := 0
    for point in candidates:
        if not _in_any_oriented_box(point, obb_centers, obb_halves, obb_yaws):
            continue
        if _in_any_box(point, box_mins, box_maxs):
            continue
        var in_sphere := false
        for b in range(centers.size()):
            if point.distance_squared_to(centers[b]) <= radii[b] * radii[b]:
                in_sphere = true
                break
        if not in_sphere:
            count += 1
    return count


func verify_native_fallback_parity() -> bool:
    var candidates := _make_candidates()
    var centers := get_exclusion_centers()
    var radii := get_exclusion_radii()
    var box_mins := get_exclusion_box_mins()
    var box_maxs := get_exclusion_box_maxs()
    return (verify_trail_native_fallback_parity()
        and _select_indices(candidates, centers, radii, box_mins, box_maxs)
        == _select_indices(candidates, centers, radii, box_mins, box_maxs, false))


func regenerate() -> void:
    var candidates := _make_candidates()
    var selected := _select_indices(candidates,
        get_exclusion_centers(), get_exclusion_radii(),
        get_exclusion_box_mins(), get_exclusion_box_maxs())
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
