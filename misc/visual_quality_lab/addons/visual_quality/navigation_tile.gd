extends NavigationRegion3D
class_name StreamedNavigationTile3D
## A minimal flat navigation polygon for each streamed scene cell. For authored
## levels, replace navigation_mesh with a pre-baked mesh that avoids obstacles.

@export_range(4.0, 256.0, 1.0) var tile_size: float = 14.0
@export var generate_flat_mesh_on_ready: bool = true
@export_range(0.0, 2.0, 0.05) var obstacle_clearance: float = 0.35
## Rect2 uses local X as x and local Z as y. Up to 8 rectangles per tile.
var blocked_rectangles: Array[Rect2] = []


func _ready() -> void:
	if generate_flat_mesh_on_ready and navigation_mesh == null:
		if blocked_rectangles.is_empty():
			navigation_mesh = make_flat_tile(tile_size)
		else:
			navigation_mesh = make_obstacle_tile(tile_size, blocked_rectangles, obstacle_clearance)


static func make_flat_tile(width: float) -> NavigationMesh:
	var result: NavigationMesh = NavigationMesh.new()
	if not is_finite(width) or width <= 0.0:
		return result
	var h: float = width * 0.5
	# Clockwise when viewed from above in the XZ plane; Y-facing polygon.
	result.vertices = PackedVector3Array([
		Vector3(-h, 0.0, -h), Vector3(-h, 0.0, h),
		Vector3(h, 0.0, h), Vector3(h, 0.0, -h)
	])
	result.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	return result



## Generate an obstacle-aware navigation tile from simple rectangles without
## scanning scene geometry or initiating expensive runtime navigation baking.
## Shared, welded grid vertices keep adjacent walkable polygons connected.
static func make_obstacle_tile(width: float, blocked: Array[Rect2], clearance: float = 0.35) -> NavigationMesh:
	var result: NavigationMesh = NavigationMesh.new()
	if not is_finite(width) or width <= 0.0 or not is_finite(clearance):
		return result
	var half: float = width * 0.5
	var margin: float = maxf(clearance, 0.0)
	var x_breaks: PackedFloat32Array = PackedFloat32Array([-half, half])
	var z_breaks: PackedFloat32Array = PackedFloat32Array([-half, half])
	var clipped: Array[Rect2] = []
	# A bounded number of obstacle contours controls polygon count.
	for i in range(mini(blocked.size(), 8)):
		var rect: Rect2 = blocked[i]
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		if not is_finite(rect.position.x) or not is_finite(rect.position.y):
			continue
		var x0: float = clampf(rect.position.x - margin, -half, half)
		var z0: float = clampf(rect.position.y - margin, -half, half)
		var x1: float = clampf(rect.end.x + margin, -half, half)
		var z1: float = clampf(rect.end.y + margin, -half, half)
		if x1 <= x0 or z1 <= z0:
			continue
		clipped.append(Rect2(Vector2(x0, z0), Vector2(x1 - x0, z1 - z0)))
		x_breaks.append(x0)
		x_breaks.append(x1)
		z_breaks.append(z0)
		z_breaks.append(z1)
	x_breaks.sort()
	z_breaks.sort()
	var xs: PackedFloat32Array = deduplicate_breaks(x_breaks)
	var zs: PackedFloat32Array = deduplicate_breaks(z_breaks)
	var vertices: PackedVector3Array = PackedVector3Array()
	for z in zs:
		for x in xs:
			vertices.append(Vector3(x, 0.0, z))
	result.vertices = vertices
	var columns: int = xs.size()
	for zi in range(zs.size() - 1):
		for xi in range(xs.size() - 1):
			var middle: Vector2 = Vector2((xs[xi] + xs[xi + 1]) * 0.5,
				(zs[zi] + zs[zi + 1]) * 0.5)
			var obstructed: bool = false
			for blocker in clipped:
				if blocker.has_point(middle):
					obstructed = true
					break
			if obstructed:
				continue
			var a: int = zi * columns + xi
			var b: int = (zi + 1) * columns + xi
			result.add_polygon(PackedInt32Array([a, b, b + 1, a + 1]))
	return result


static func deduplicate_breaks(sorted_breaks: PackedFloat32Array) -> PackedFloat32Array:
	var unique: PackedFloat32Array = PackedFloat32Array()
	for value in sorted_breaks:
		if unique.is_empty() or absf(value - unique[unique.size() - 1]) > 0.001:
			unique.append(value)
	return unique
