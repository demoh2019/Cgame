extends NavigationRegion3D
## Lightweight procedural NavigationMesh generated from exactly the same
## analytic terrain height function as the visible/collidable streamed tile.
##
## Unlike editor bake from MeshInstances, this creates 128 polygons directly:
## 9x9 vertices at 4m spacing, 2 triangles per 4m quad. All tile boundaries
## use the same function and height samples; cells unload with the scene.
## This is WALKABLE-TERRAIN navigation, not an obstacle-carved navmesh.
## Physical trunks/rocks must still be avoided by physics or local steering.

const TerrainHeight = preload("res://scripts/terrain_height.gd")
const EDGE: int = 32
const STEP: int = 4
const SAMPLE_COUNT: int = EDGE / STEP + 1


func _ready() -> void:
    name = "GroundNavigation"
    enabled = true
    use_edge_connections = true
    var nav := NavigationMesh.new()
    nav.agent_radius = 0.35
    nav.agent_height = 1.9
    nav.agent_max_climb = 0.45
    nav.agent_max_slope = 48.0

    var vertices := PackedVector3Array()
    vertices.resize(SAMPLE_COUNT * SAMPLE_COUNT)
    for z in range(SAMPLE_COUNT):
        for x in range(SAMPLE_COUNT):
            var local_x: float = float(x * STEP)
            var local_z: float = float(z * STEP)
            var world_x: float = global_position.x + local_x
            var world_z: float = global_position.z + local_z
            vertices[z * SAMPLE_COUNT + x] = Vector3(
                local_x,
                TerrainHeight.height_at(world_x, world_z) - global_position.y,
                local_z)
    nav.vertices = vertices

    for z in range(SAMPLE_COUNT - 1):
        for x in range(SAMPLE_COUNT - 1):
            var corner: int = z * SAMPLE_COUNT + x
            # Same upward-facing winding as streamed_terrain_patch.gd.
            nav.add_polygon(PackedInt32Array([
                corner, corner + SAMPLE_COUNT, corner + 1]))
            nav.add_polygon(PackedInt32Array([
                corner + 1, corner + SAMPLE_COUNT,
                corner + SAMPLE_COUNT + 1]))
    navigation_mesh = nav
