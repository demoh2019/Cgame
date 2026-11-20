extends Node3D
## One 32 m seamless terrain patch. Created and unloaded together with its
## WorldPartition3D forest cell. A shared analytic height function guarantees
## identical heights and vertex normals on adjacent cell boundaries.
##
## Static terrain collision uses HeightMapShape3D, which is more efficient than
## generating a full ConcavePolygonShape3D for each heightfield chunk. Heightmap
## samples are separated by exactly one world unit (no physics-shape scaling).

const TerrainHeight = preload("res://scripts/terrain_height.gd")
const CELL_SIZE: int = 32
const SEGMENTS: int = 32
const VERTICES_PER_SIDE: int = SEGMENTS + 1

var visual: MeshInstance3D
var body: StaticBody3D
var terrain_collision: CollisionShape3D


func _ready() -> void:
    _build_patch()


func _build_patch() -> void:
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var colors := PackedColorArray()
    var uvs := PackedVector2Array()
    var indices := PackedInt32Array()
    var heights := PackedFloat32Array()
    var vertex_count: int = VERTICES_PER_SIDE * VERTICES_PER_SIDE
    vertices.resize(vertex_count)
    normals.resize(vertex_count)
    colors.resize(vertex_count)
    uvs.resize(vertex_count)
    heights.resize(vertex_count)

    var origin: Vector3 = global_position
    for z in range(VERTICES_PER_SIDE):
        for x in range(VERTICES_PER_SIDE):
            var idx: int = z * VERTICES_PER_SIDE + x
            var wx: float = origin.x + float(x)
            var wz: float = origin.z + float(z)
            var height: float = TerrainHeight.height_at(wx, wz) - origin.y
            var normal: Vector3 = TerrainHeight.normal_at(wx, wz)
            vertices[idx] = Vector3(float(x), height, float(z))
            normals[idx] = normal
            uvs[idx] = Vector2(wx, wz) * 0.08
            heights[idx] = height

            var slope: float = clampf(1.0 - normal.y, 0.0, 1.0)
            var variation: float = 0.5 + 0.5 * sin(wx * 0.12 + wz * 0.09)
            var moss := Color(0.16, 0.27, 0.13)
            var soil := Color(0.21, 0.20, 0.13)
            colors[idx] = moss.lerp(soil, clampf(slope * 2.8 + variation * 0.12, 0.0, 1.0))

    for z in range(SEGMENTS):
        for x in range(SEGMENTS):
            var i: int = z * VERTICES_PER_SIDE + x
            indices.push_back(i)
            indices.push_back(i + VERTICES_PER_SIDE)
            indices.push_back(i + 1)
            indices.push_back(i + 1)
            indices.push_back(i + VERTICES_PER_SIDE)
            indices.push_back(i + VERTICES_PER_SIDE + 1)

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_COLOR] = colors
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices

    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var material := StandardMaterial3D.new()
    material.vertex_color_use_as_albedo = true
    material.roughness = 0.97
    mesh.surface_set_material(0, material)

    visual = MeshInstance3D.new()
    visual.name = "GroundMesh"
    visual.mesh = mesh
    visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(visual)

    var collision_shape := HeightMapShape3D.new()
    collision_shape.map_width = VERTICES_PER_SIDE
    collision_shape.map_depth = VERTICES_PER_SIDE
    collision_shape.map_data = heights

    body = StaticBody3D.new()
    body.name = "GroundCollision"
    body.collision_layer = 1
    body.collision_mask = 0
    terrain_collision = CollisionShape3D.new()
    terrain_collision.name = "HeightmapCollision"
    terrain_collision.shape = collision_shape
    # HeightMapShape3D's grid is centered at its CollisionShape3D origin.
    # The visual patch spans local [0, 32] on X/Z, hence the +16 offset.
    terrain_collision.position = Vector3(CELL_SIZE * 0.5, 0.0, CELL_SIZE * 0.5)
    body.add_child(terrain_collision)
    add_child(body)
