extends RefCounted
## Deterministic per-cell sampled terrain for native clearance/slope filtering.
## The engine owns obstacle-intersection tests and NavigationMesh triangles.
## Adjacent tile samples share world coordinates along their seams.

const TerrainHeight = preload("res://scripts/terrain_height.gd")
const SAMPLE_COUNT: int = 16
const TILE_SIZE: float = 32.0
const AGENT_RADIUS: float = 0.45
const MAX_SLOPE_DEGREES: float = 42.0


static func sample_vertices(cell_world_origin: Vector3) -> PackedVector3Array:
    var vertices := PackedVector3Array()
    var stride: int = SAMPLE_COUNT + 1
    for iz in range(stride):
        for ix in range(stride):
            var local_x: float = TILE_SIZE * float(ix) / float(SAMPLE_COUNT)
            var local_z: float = TILE_SIZE * float(iz) / float(SAMPLE_COUNT)
            var local_y: float = TerrainHeight.height_at(
                cell_world_origin.x + local_x,
                cell_world_origin.z + local_z) - cell_world_origin.y
            vertices.append(Vector3(local_x, local_y, local_z))
    return vertices


static func build_tile(cell_world_origin: Vector3, partition: WorldPartition3D,
        blockers: PackedVector3Array) -> NavigationMesh:
    var vertices: PackedVector3Array = sample_vertices(cell_world_origin)
    if is_instance_valid(partition):
        # Vector3(blocker_local_x, blocker_local_z, collider_radius).
        # Native builder rejects slopes >42 degrees and safely expands each
        # blocker by AGENT_RADIUS to approximate character capsule clearance.
        return partition.build_navigation_tile(
            vertices, SAMPLE_COUNT, blockers, AGENT_RADIUS, MAX_SLOPE_DEGREES)

    # Standalone scene previews are allowed without WorldPartition3D. The
    # native filtered route is the only one used in the streamed game.
    var preview := NavigationMesh.new()
    preview.vertices = vertices
    for iz in range(SAMPLE_COUNT):
        for ix in range(SAMPLE_COUNT):
            var a: int = iz * (SAMPLE_COUNT + 1) + ix
            var b: int = a + 1
            var c: int = a + SAMPLE_COUNT + 1
            var d: int = c + 1
            preview.add_polygon(PackedInt32Array([a, c, b]))
            preview.add_polygon(PackedInt32Array([b, c, d]))
    return preview
