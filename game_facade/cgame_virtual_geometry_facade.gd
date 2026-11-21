extends RefCounted
## Facade over the native virtualized-geometry classes (CgameMeshlets, CgameClusterLOD,
## CgameOcclusionRaster from modules/cgame_virtual_geometry). When the engine was built
## without the module, every call falls back to the GDScript implementations in
## res://scripts/shared/. Both back ends use the same dictionary layout and semantics.
##
## The native classes are resolved through ClassDB at runtime, so this file parses on
## engines that do not contain them.

const MESHLETS_SCRIPT := "res://scripts/shared/meshlets.gd"
const CLUSTER_LOD_SCRIPT := "res://scripts/shared/cluster_lod.gd"
const OCCLUSION_SCRIPT := "res://scripts/shared/occlusion_raster.gd"

static var _meshlets: Object = null
static var _cluster_lod: Object = null
static var _occlusion_script: Script = null
static var _resolved: bool = false
static var _native: bool = false


static func _resolve() -> void:
	if _resolved:
		return
	_resolved = true
	_native = ClassDB.class_exists("CgameMeshlets") and ClassDB.class_exists("CgameClusterLOD") and ClassDB.class_exists("CgameOcclusionRaster")
	if _native:
		# Static native methods are callable through an instance.
		_meshlets = ClassDB.instantiate("CgameMeshlets")
		_cluster_lod = ClassDB.instantiate("CgameClusterLOD")
	else:
		_meshlets = load(MESHLETS_SCRIPT)
		_cluster_lod = load(CLUSTER_LOD_SCRIPT)
		_occlusion_script = load(OCCLUSION_SCRIPT)


## True when the C++ module is available.
static func is_native() -> bool:
	_resolve()
	return _native


## Array of meshlet dictionaries (indices, vertex_ids, bounds_center, bounds_radius, cone_axis, cone_cutoff).
static func build_meshlets(vertices: PackedVector3Array, indices: PackedInt32Array, max_vertices: int = 64, max_triangles: int = 124) -> Array:
	_resolve()
	return _meshlets.call("build_meshlets", vertices, indices, max_vertices, max_triangles)


static func cone_cull(meshlet: Dictionary, camera_pos: Vector3) -> bool:
	_resolve()
	return _meshlets.call("cone_cull", meshlet, camera_pos)


static func frustum_cull(meshlet: Dictionary, planes: Array[Plane]) -> bool:
	_resolve()
	return _meshlets.call("frustum_cull", meshlet, planes)


## Hierarchy dictionary: vertices, clusters, levels, roots.
static func build_hierarchy(vertices: PackedVector3Array, indices: PackedInt32Array, levels: int = 4) -> Dictionary:
	_resolve()
	return _cluster_lod.call("build_hierarchy", vertices, indices, levels)


static func select_cut(hierarchy: Dictionary, camera_pos: Vector3, fov_y: float, screen_height: float, error_pixels: float = 1.0) -> PackedInt32Array:
	_resolve()
	return _cluster_lod.call("select_cut", hierarchy, camera_pos, fov_y, screen_height, error_pixels)


static func triangle_count(hierarchy: Dictionary, cut: PackedInt32Array) -> int:
	_resolve()
	return _cluster_lod.call("triangle_count", hierarchy, cut)


## New occlusion rasteriser: a CgameOcclusionRaster when native, the GDScript OcclusionRaster otherwise.
## Both expose begin / rasterize_occluder / temporal_reproject / build_hiz / hiz_* / is_visible / test_many
## and the tested, culled, occluder_triangles, pixels_written counters.
static func create_occlusion_raster() -> RefCounted:
	_resolve()
	if _native:
		return ClassDB.instantiate("CgameOcclusionRaster")
	return _occlusion_script.new()
