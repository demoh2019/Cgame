extends RefCounted
## The open sea: a radial LOD mesh that follows the camera (dense ripples close by, coarse rings
## out to the horizon, so Gerstner swell has vertices to move), and an island depth map so the
## swell dies down and breaks into surf where the sea gets shallow. The depth map is filled
## a couple of rows per frame from WorldGen.ground_at.

const Defs = preload("res://scripts/shared/defs.gd")

const SEGMENTS := 160
const RADIUS := 900.0
const FIRST_RING := 0.8
const GROWTH := 1.065 # Each ring a little wider than the last.
const MAP_SIZE := 256
const MAP_EXTENT := 6400.0
const ROWS_PER_FRAME := 2

var _image: Image
var _row := 0
var texture: ImageTexture


## Concentric rings around the origin; ring spacing grows geometrically with distance.
static func build_mesh() -> ArrayMesh:
	var radii := PackedFloat32Array([0.0])
	var r := FIRST_RING
	var step := FIRST_RING
	while r < RADIUS:
		radii.append(r)
		step *= GROWTH
		r += step
	radii.append(RADIUS)
	var vertices := PackedVector3Array([Vector3.ZERO])
	var indices := PackedInt32Array()
	for ring in range(1, radii.size()):
		for s in SEGMENTS:
			var angle: float = TAU * float(s) / float(SEGMENTS)
			vertices.append(Vector3(cos(angle) * radii[ring], 0.0, sin(angle) * radii[ring]))
	for s in SEGMENTS:
		indices.append_array([0, 1 + (s + 1) % SEGMENTS, 1 + s])
	for ring in range(1, radii.size() - 1):
		var inner: int = 1 + (ring - 1) * SEGMENTS
		var outer: int = 1 + ring * SEGMENTS
		for s in SEGMENTS:
			var n: int = (s + 1) % SEGMENTS
			indices.append_array([inner + s, inner + n, outer + s, inner + n, outer + n, outer + s])
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-RADIUS, -6.0, -RADIUS), Vector3(RADIUS * 2.0, 12.0, RADIUS * 2.0))
	return mesh


## Fill a few rows of the depth map; returns true once the whole map is ready (then it is uploaded).
func step_depth_map(world) -> bool:
	if texture != null:
		return true
	if _image == null:
		_image = Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RF)
	var cell: float = MAP_EXTENT / float(MAP_SIZE)
	for r in ROWS_PER_FRAME:
		if _row >= MAP_SIZE:
			break
		for i in MAP_SIZE:
			var x: float = -MAP_EXTENT * 0.5 + (float(i) + 0.5) * cell
			var z: float = -MAP_EXTENT * 0.5 + (float(_row) + 0.5) * cell
			_image.set_pixel(i, _row, Color(maxf(Defs.WATER_LEVEL - world.ground_at(x, z), 0.0), 0, 0))
		_row += 1
	if _row >= MAP_SIZE:
		texture = ImageTexture.create_from_image(_image)
		return true
	return false
