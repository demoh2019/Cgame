extends RefCounted
## Authored per-cell navigation tile from the shared analytic heightfield.
## No runtime Recast bake or GPU mesh readback; neighbor tiles share the same
## boundary vertices so NavigationServer3D can connect close edges.
##
## NOTE: This navigation surface is the broad walkable terrain only. It does
## not carve tree trunks/rocks or account for character radius and slope.
## Forest stalker collision-ray steering remains responsible for obstacles.

const TerrainHeight = preload("res://scripts/terrain_height.gd")
const SAMPLE_COUNT: int = 8
const TILE_SIZE: float = 32.0


static func build_tile(cell_world_origin: Vector3) -> NavigationMesh:
    var mesh := NavigationMesh.new()
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
    mesh.vertices = vertices

    # Keep each terrain polygon triangular; non-planar quads are not
    # well-defined navigation polygons. Winding faces +Y in Godot's X/Z plane.
    for iz in range(SAMPLE_COUNT):
        for ix in range(SAMPLE_COUNT):
            var a: int = iz * stride + ix
            var b: int = a + 1
            var c: int = a + stride
            var d: int = c + 1
            mesh.add_polygon(PackedInt32Array([a, c, b]))
            mesh.add_polygon(PackedInt32Array([b, c, d]))
    return mesh
