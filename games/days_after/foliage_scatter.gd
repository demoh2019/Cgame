extends MultiMeshInstance3D
## Collision-free PCG foliage grouped into up to three mesh-specific GPU batches.
## Exclusion spheres protect spawn, scavenging resources, and ruined structures.
## Native PCG and stock-Godot fallback agree on stable-ID density and exclusions.

const GRID_SIZE: int = 25
const MAX_INSTANCES: int = 160
const MIN_SPACING: float = 2.1
const WeightedVariants = preload("res://pcg_weighted_variants.gd")
const PointTransforms = preload("res://pcg_point_transforms.gd")
const TRANSFORM_SEED := 42019
const TRANSFORM_HORIZONTAL_MIN := 0.82
const TRANSFORM_HORIZONTAL_MAX := 1.18
const TRANSFORM_VERTICAL_MIN := 0.88
const TRANSFORM_VERTICAL_MAX := 1.16
const LODPlan = preload("res://pcg_instance_lod.gd")
const LOD_SWITCH_DISTANCE := 24.0
const LOD_HYSTERESIS := 3.0
const LOD_REFRESH_SECONDS := 0.25
const VARIANT_WEIGHTS = [6.0, 3.0, 1.0]
const VARIANT_SEED := 81419
const VARIANT_COLORS := [
    Color(0.27, 0.41, 0.21), # Damp green vegetation (60%)
    Color(0.47, 0.45, 0.27), # Autumn/dry-green vegetation (30%)
    Color(0.57, 0.36, 0.20), # Dead straw vegetation (10%)
]
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
# Hand-authored concave clearing around the old western ruin approach.
# Unlike a rectangular/spherical exclusion, vegetation tapers gradually at
# its irregular edge; the native mask is evaluated only on regeneration.
const RUIN_CLEARING_FEATHER: float = 3.5
const RUIN_CLEARING_POLYGON = [
    Vector3(-21.0, 0.0, -17.0),
    Vector3(-15.0, 0.0, -20.0),
    Vector3(-11.0, 0.0, -16.0),
    Vector3(-10.0, 0.0, -11.0),
    Vector3(-15.0, 0.0, -8.0),
    Vector3(-20.0, 0.0, -11.0),
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
const ORIENTED_BOX_YAWS = [0.6108652381980153] # 35 degrees in radians.

var _selected_positions := PackedVector3Array()
var _selected_variants := PackedInt32Array()
var _selected_stable_ids := PackedInt64Array()
var _selected_transforms: Array = []
var _variant_batches: Array = []
var _lod_tiers := PackedInt32Array()
var _lod_buckets: Array = []
var _lod_batch_rebuild_counts := PackedInt32Array([0, 0, 0, 0, 0, 0])
var _last_lod_dirty_flags := PackedByteArray([0, 0, 0, 0, 0, 0])


## Diagnostics: GPU MultiMesh allocations per mesh/LOD combination.
## Counters are cumulative for this FoliageScatter node's lifetime.
func get_lod_batch_rebuild_counts() -> PackedInt32Array:
    return _lod_batch_rebuild_counts.duplicate()


func get_last_lod_dirty_flags() -> PackedByteArray:
    return _last_lod_dirty_flags.duplicate()


func get_total_lod_batch_rebuild_count() -> int:
    var total := 0
    for count in _lod_batch_rebuild_counts:
        total += count
    return total

var _lod_meshes: Array = []
var _lod_materials: Array = []
var _lod_viewer: Node3D = null
var _last_lod_viewer := Vector3(0.0, 0.15, 3.0)
var _lod_elapsed := 0.0


## Optional viewer drives low-frequency per-instance LOD changes. Does not
## regenerate PCG points or reroll any weighted visual decisions.
func set_viewer(viewer: Node3D) -> void:
    _lod_viewer = viewer
    if viewer != null and is_inside_tree():
        force_lod_refresh(viewer.global_position)


func _process(delta: float) -> void:
    if _lod_viewer == null or not is_instance_valid(_lod_viewer):
        return
    _lod_elapsed += delta
    if _lod_elapsed < LOD_REFRESH_SECONDS:
        return
    _lod_elapsed = 0.0
    var viewer_pos: Vector3 = _lod_viewer.global_position
    if viewer_pos.is_finite() and viewer_pos.distance_squared_to(_last_lod_viewer) >= 0.25:
        _refresh_lod(viewer_pos, false)


## Tests and editor tools can force a snapshot from any world-space viewer.
func force_lod_refresh(viewer_position: Vector3) -> bool:
    return _refresh_lod(viewer_position, true)


func get_lod_tiers() -> PackedInt32Array:
    return _lod_tiers.duplicate()


func get_lod_renderer(variant: int, lod: int) -> MultiMeshInstance3D:
    if variant < 0 or variant >= VARIANT_WEIGHTS.size():
        return null
    if lod == 0:
        return get_variant_renderer(variant)
    if lod != 1:
        return null
    return get_node_or_null("PCGMeshVariant%dLOD1" % variant) as MultiMeshInstance3D


func get_lod_source_indices(variant: int, lod: int) -> PackedInt32Array:
    var index: int = variant * 2 + lod
    if lod < 0 or lod > 1 or variant < 0 or variant >= VARIANT_WEIGHTS.size() or \
            index >= _lod_buckets.size():
        return PackedInt32Array()
    var indices: PackedInt32Array = _lod_buckets[index]
    return indices.duplicate()


func get_lod_batch_sizes() -> PackedInt32Array:
    var counts := PackedInt32Array()
    for group in _lod_buckets:
        var indices: PackedInt32Array = group
        counts.push_back(indices.size())
    return counts


func verify_lod_native_fallback_parity() -> bool:
    if _lod_tiers.size() != _selected_positions.size():
        return false
    var native: PackedInt32Array = LODPlan.plan_instance_lods(
        _selected_positions, _last_lod_viewer, _lod_tiers,
        LOD_SWITCH_DISTANCE, LOD_HYSTERESIS)
    var fallback: PackedInt32Array = LODPlan.plan_instance_lods(
        _selected_positions, _last_lod_viewer, _lod_tiers,
        LOD_SWITCH_DISTANCE, LOD_HYSTERESIS, false)
    return native == fallback and native == _lod_tiers and \
        _lod_buckets == LODPlan.partition_variant_lods(
            _selected_variants, _lod_tiers, VARIANT_WEIGHTS.size(), false)



## Parent MultiMeshInstance3D is variant zero for backward-compatible paths.
## Other variants are persistent child GPU batches, never per-plant Nodes.
func get_variant_renderer(variant: int) -> MultiMeshInstance3D:
    if variant == 0:
        return self
    if variant < 0 or variant >= VARIANT_WEIGHTS.size():
        return null
    return get_node_or_null("PCGMeshVariant%d" % variant) as MultiMeshInstance3D


func get_variant_batch_sizes() -> PackedInt32Array:
    var sizes := PackedInt32Array()
    for variant in range(VARIANT_WEIGHTS.size()):
        if _variant_batches.size() == VARIANT_WEIGHTS.size():
            var indices: PackedInt32Array = _variant_batches[variant]
            sizes.append(indices.size())
        else:
            sizes.append(0)
    return sizes


func get_variant_source_indices(variant: int) -> PackedInt32Array:
    if variant >= 0 and variant < _variant_batches.size():
        var indices: PackedInt32Array = _variant_batches[variant]
        return indices.duplicate()
    return PackedInt32Array()


func get_rendered_instance_count() -> int:
    var total := 0
    for variant in range(VARIANT_WEIGHTS.size()):
        for lod in 2:
            var renderer: MultiMeshInstance3D = get_lod_renderer(variant, lod)
            if renderer != null and renderer.multimesh != null:
                total += renderer.multimesh.instance_count
    return total


func verify_variant_partition_native_fallback_parity() -> bool:
    return _variant_batches == WeightedVariants.partition_indices(
        _selected_variants, VARIANT_WEIGHTS.size(), false)



func get_selected_variants() -> PackedInt32Array:
    return _selected_variants.duplicate()


func get_selected_stable_ids() -> PackedInt64Array:
    return _selected_stable_ids.duplicate()


func get_selected_transforms() -> Array:
    return _selected_transforms.duplicate()


func verify_point_transform_native_fallback_parity() -> bool:
    var native: Array = PointTransforms.generate_transforms(
        _selected_positions, _selected_stable_ids, TRANSFORM_SEED,
        TAU, TRANSFORM_HORIZONTAL_MIN, TRANSFORM_HORIZONTAL_MAX,
        TRANSFORM_VERTICAL_MIN, TRANSFORM_VERTICAL_MAX)
    var fallback: Array = PointTransforms.generate_transforms(
        _selected_positions, _selected_stable_ids, TRANSFORM_SEED,
        TAU, TRANSFORM_HORIZONTAL_MIN, TRANSFORM_HORIZONTAL_MAX,
        TRANSFORM_VERTICAL_MIN, TRANSFORM_VERTICAL_MAX, false)
    if native.size() != _selected_positions.size() or native.size() != fallback.size():
        return false
    for index in native.size():
        var engine_transform: Transform3D = native[index]
        var script_transform: Transform3D = fallback[index]
        var saved_transform: Transform3D = _selected_transforms[index]
        if engine_transform.origin != script_transform.origin or \
                engine_transform.origin != saved_transform.origin or \
                not engine_transform.basis.is_equal_approx(script_transform.basis) or \
                not engine_transform.basis.is_equal_approx(saved_transform.basis):
            return false
    return true


func verify_variant_native_fallback_parity() -> bool:
    return (WeightedVariants.choose_variants(_selected_stable_ids,
        PackedFloat32Array(VARIANT_WEIGHTS), VARIANT_SEED, false) == _selected_variants)


func get_variant_counts() -> PackedInt32Array:
    var counts := PackedInt32Array([0, 0, 0])
    for variant in _selected_variants:
        if variant >= 0 and variant < counts.size():
            counts[variant] += 1
    return counts



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


func get_ruin_clearing_polygon() -> PackedVector3Array:
    return PackedVector3Array(RUIN_CLEARING_POLYGON)


func get_ruin_clearing_feather() -> float:
    return RUIN_CLEARING_FEATHER


func _sample_polygon_fallback(positions: PackedVector3Array,
        invert: bool = false) -> PackedFloat32Array:
    var polygon := get_ruin_clearing_polygon()
    var factors := PackedFloat32Array()
    var feather_squared: float = RUIN_CLEARING_FEATHER * RUIN_CLEARING_FEATHER
    for point in positions:
        var inside: bool = false
        var nearest_squared: float = INF
        for edge in range(polygon.size()):
            var a: Vector3 = polygon[edge]
            var b: Vector3 = polygon[(edge + 1) % polygon.size()]
            var dx: float = b.x - a.x
            var dz: float = b.z - a.z
            var distance_squared: float = dx * dx + dz * dz
            var along: float = clampf(
                ((point.x - a.x) * dx + (point.z - a.z) * dz) /
                distance_squared, 0.0, 1.0)
            var offset_x: float = point.x - (a.x + along * dx)
            var offset_z: float = point.z - (a.z + along * dz)
            nearest_squared = minf(nearest_squared,
                offset_x * offset_x + offset_z * offset_z)
            if ((a.z > point.z) != (b.z > point.z)) and (
                    point.x < a.x + (point.z - a.z) * dx / dz):
                inside = not inside
        var factor: float = 0.0
        if not inside and nearest_squared > 1.0e-12:
            if nearest_squared >= feather_squared:
                factor = 1.0
            else:
                var t: float = sqrt(nearest_squared) / RUIN_CLEARING_FEATHER
                factor = t * t * (3.0 - 2.0 * t)
        factors.push_back(1.0 - factor if invert else factor)
    return factors


func get_polygon_factors(prefer_native: bool = true,
        invert: bool = false) -> PackedFloat32Array:
    var positions := _make_candidates()
    if prefer_native and ClassDB.class_exists("PCGPolygonMask3D"):
        var mask: Object = ClassDB.instantiate("PCGPolygonMask3D")
        if mask != null and mask.has_method("sample_factors"):
            var native: PackedFloat32Array = mask.call("sample_factors",
                positions, get_ruin_clearing_polygon(),
                RUIN_CLEARING_FEATHER, invert)
            if native.size() == positions.size():
                return native
    return _sample_polygon_fallback(positions, invert)


func verify_polygon_native_fallback_parity() -> bool:
    var outside_native: PackedFloat32Array = get_polygon_factors()
    var outside_script: PackedFloat32Array = get_polygon_factors(false)
    var inside_native: PackedFloat32Array = get_polygon_factors(true, true)
    var inside_script: PackedFloat32Array = get_polygon_factors(false, true)
    if (outside_native.size() != GRID_SIZE * GRID_SIZE
            or outside_native.size() != outside_script.size()
            or inside_native.size() != outside_native.size()
            or inside_script.size() != outside_native.size()):
        return false
    for i in outside_native.size():
        if (absf(outside_native[i] - outside_script[i]) > 0.00002
                or absf(inside_native[i] - inside_script[i]) > 0.00002
                or absf(outside_native[i] + inside_native[i] - 1.0) > 0.00002):
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
    var clearing_factors: PackedFloat32Array = get_polygon_factors(prefer_native)
    # Combine orthogonal PCG masks multiplicatively. Stable cell IDs,
    # seeded variants and LOD behavior remain unchanged.
    for i in range(densities.size()):
        densities.set(i, densities[i] * trail_factors[i] * clearing_factors[i])
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
    _selected_stable_ids.clear()
    var source_ids: PackedInt32Array = _make_ids()
    for index in selected:
        _selected_positions.push_back(candidates[index])
        _selected_stable_ids.push_back(source_ids[index])
    # Selection runs only when a cosmetic batch is rebuilt, never per frame.
    # Stable physical cell IDs preserve the visual variant on regeneration.
    _selected_variants = WeightedVariants.choose_variants(
        _selected_stable_ids, PackedFloat32Array(VARIANT_WEIGHTS), VARIANT_SEED)
    if _selected_variants.size() != _selected_positions.size():
        _selected_variants.resize(_selected_positions.size())
        _selected_variants.fill(0) # Fail open: retain all cosmetic plants.

    # Unreal PCG Static Mesh Spawner-inspired: each distinct geometry uses
    # one MultiMesh, never one MeshInstance3D/actor per plant.
    _variant_batches = WeightedVariants.partition_indices(
        _selected_variants, VARIANT_WEIGHTS.size())
    var assigned: int = 0
    if _variant_batches.size() == VARIANT_WEIGHTS.size():
        for group in _variant_batches:
            var indices: PackedInt32Array = group
            assigned += indices.size()
    if assigned != _selected_positions.size() or \
            _variant_batches.size() != VARIANT_WEIGHTS.size():
        # Fail open on malformed data: preserve the decorative plants using
        # the first simple geometry and deterministic stock-Godot bucketing.
        _selected_variants.fill(0)
        _variant_batches = WeightedVariants.partition_indices(
            _selected_variants, VARIANT_WEIGHTS.size(), false)

    # Native PCG Transform Points: store stable rotation/scale once per
    # accepted physical cell ID. Re-bucketing or camera LOD changes never
    # resample transforms or use the current MultiMesh element order.
    _selected_transforms = PointTransforms.generate_transforms(
        _selected_positions, _selected_stable_ids, TRANSFORM_SEED,
        TAU, TRANSFORM_HORIZONTAL_MIN, TRANSFORM_HORIZONTAL_MAX,
        TRANSFORM_VERTICAL_MIN, TRANSFORM_VERTICAL_MAX)
    if _selected_transforms.size() != _selected_positions.size():
        _selected_transforms = []
        for point in _selected_positions:
            _selected_transforms.append(Transform3D(Basis(), point))

    # PCG selection is intentionally complete before any LOD work. Changing
    # viewer never re-samples a position, density mask or stable variant ID.
    _lod_tiers.clear()
    # Regeneration may change cached transforms even when LOD membership
    # coincidentally matches. The next evaluation must update every GPU slot.
    _lod_buckets.clear()
    var viewer_position := Vector3(0.0, 0.15, 3.0)
    if _lod_viewer != null and is_instance_valid(_lod_viewer):
        viewer_position = _lod_viewer.global_position
    _refresh_lod(viewer_position, true)


func _refresh_lod(viewer_position: Vector3, force: bool) -> bool:
    if not viewer_position.is_finite() or _selected_variants.size() != _selected_positions.size():
        return false
    var planned: PackedInt32Array = LODPlan.plan_instance_lods(
        _selected_positions, viewer_position, _lod_tiers,
        LOD_SWITCH_DISTANCE, LOD_HYSTERESIS)
    if planned.size() != _selected_positions.size():
        return false
    if not _lod_buckets.is_empty() and planned == _lod_tiers:
        # Even a forced no-change refresh must not reupload GPU buffers.
        _last_lod_viewer = viewer_position
        _last_lod_dirty_flags.fill(0)
        return force

    var dirty := PackedByteArray()
    if _lod_buckets.is_empty():
        # First fill or explicit regeneration: all six slots must exist
        # even when some variants are currently empty.
        dirty.resize(VARIANT_WEIGHTS.size() * 2)
        dirty.fill(1)
    else:
        dirty = LODPlan.plan_dirty_variant_lod_groups(
            _selected_variants, _lod_tiers, planned, VARIANT_WEIGHTS.size())
        if dirty.size() != VARIANT_WEIGHTS.size() * 2:
            return false

    var groups: Array = LODPlan.partition_variant_lods(
        _selected_variants, planned, VARIANT_WEIGHTS.size())
    if groups.size() != VARIANT_WEIGHTS.size() * 2:
        return false
    var visited := PackedInt32Array()
    visited.resize(_selected_positions.size())
    for group in groups:
        var indices: PackedInt32Array = group
        for source_index in indices:
            if source_index < 0 or source_index >= visited.size():
                return false
            visited[source_index] += 1
    for count in visited:
        if count != 1:
            return false
    _last_lod_viewer = viewer_position
    _lod_tiers = planned
    _lod_buckets = groups
    _last_lod_dirty_flags = dirty
    _build_lod_renderers(dirty)
    return true


func _get_lod_mesh(variant: int, lod: int) -> PrimitiveMesh:
    # Cache the six small meshes and their materials across camera movement.
    if _lod_meshes.is_empty():
        for i in range(VARIANT_WEIGHTS.size() * 2):
            _lod_meshes.append(null)
    var key: int = variant * 2 + lod
    if _lod_meshes[key] != null:
        return _lod_meshes[key]

    if _lod_materials.is_empty():
        for i in 2:
            var material := StandardMaterial3D.new()
            material.albedo_color = Color.WHITE
            material.vertex_color_use_as_albedo = true
            material.roughness = 1.0
            if i == 1:
                material.cull_mode = BaseMaterial3D.CULL_DISABLED
                material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
            _lod_materials.append(material)

    var geometry: PrimitiveMesh
    if lod == 1:
        # Two-triangle camera-facing vegetation proxy for every source mesh.
        var proxy := QuadMesh.new()
        proxy.size = [Vector2(0.12, 0.44), Vector2(0.18, 0.54),
            Vector2(0.19, 0.34)][variant]
        geometry = proxy
    else:
        match variant:
            0:
                var blade := BoxMesh.new()
                blade.size = Vector3(0.10, 0.44, 0.10)
                geometry = blade
            1:
                var reed := CylinderMesh.new()
                reed.top_radius = 0.018
                reed.bottom_radius = 0.095
                reed.height = 0.54
                reed.radial_segments = 5
                geometry = reed
            2:
                var straw := SphereMesh.new()
                straw.radius = 0.095
                straw.height = 0.34
                straw.radial_segments = 6
                straw.rings = 3
                geometry = straw
    geometry.material = _lod_materials[lod]
    _lod_meshes[key] = geometry
    return geometry


func _build_lod_renderers(dirty: PackedByteArray) -> void:
    # Reallocate only groups with changed membership. Untouched MultiMesh
    # resources retain their GPU buffers, transforms, colors and IDs.
    for variant in range(VARIANT_WEIGHTS.size()):
        for lod in 2:
            var group_index: int = variant * 2 + lod
            if dirty[group_index] == 0:
                continue
            var renderer: MultiMeshInstance3D = get_lod_renderer(variant, lod)
            if renderer == null:
                renderer = MultiMeshInstance3D.new()
                renderer.name = ("PCGMeshVariant%dLOD1" % variant) if lod == 1 \
                    else ("PCGMeshVariant%d" % variant)
                renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
                add_child(renderer)
            var indices: PackedInt32Array = _lod_buckets[variant * 2 + lod]
            var batch := MultiMesh.new()
            batch.transform_format = MultiMesh.TRANSFORM_3D
            batch.use_colors = true
            batch.mesh = _get_lod_mesh(variant, lod)
            batch.instance_count = indices.size()
            for local_index in indices.size():
                var source_index: int = indices[local_index]
                var sampled: Transform3D = _selected_transforms[source_index]
                var width_scale: float = [0.8, 1.0, 1.15][variant]
                var height_scale: float = [0.90, 0.78, 0.63][variant]
                var orientation: Basis = sampled.basis.scaled(
                    Vector3(width_scale, height_scale, width_scale))
                batch.set_instance_transform(local_index,
                    Transform3D(orientation, sampled.origin))
                batch.set_instance_color(local_index, VARIANT_COLORS[variant])
            renderer.multimesh = batch
            renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            _lod_batch_rebuild_counts[group_index] += 1
