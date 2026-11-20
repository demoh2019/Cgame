extends NavigationRegion3D
class_name StreamedNavigationTile3D
## A minimal flat navigation polygon for each streamed scene cell. For authored
## levels, replace navigation_mesh with a pre-baked mesh that avoids obstacles.

@export_range(4.0, 256.0, 1.0) var tile_size: float = 14.0
@export var generate_flat_mesh_on_ready: bool = true


func _ready() -> void:
	if generate_flat_mesh_on_ready and navigation_mesh == null:
		navigation_mesh = make_flat_tile(tile_size)


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
