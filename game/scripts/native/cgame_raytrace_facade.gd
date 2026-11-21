extends RefCounted
## Facade over the native CgameBVH / CgamePathTracer engine classes with a transparent fallback to
## the pure GDScript implementation (res://scripts/shared/bvh.gd and path_tracer.gd).
##
## Usage:
##   const RT = preload("res://scripts/shared/cgame_raytrace_facade.gd")
##   var bvh = RT.make_bvh(tris)                       # CgameBVH or GDScript Bvh; both expose
##                                                      # intersect(), occluded(), get_stats()
##   var ao = RT.bake_ambient_occlusion(bvh, verts, normals, 32, 4.0, 1)
##   var img = RT.render_image(bvh, cam, 50.0, Vector2i(256, 192), 4, RT.make_light(...), 1)
##   var prog = RT.make_progressive(Vector2i(256, 192), 7)   # prog.accumulate(...) / to_image()
##
## Do not mix a native BVH with the fallback tracer: the facade picks one backend for everything.

const _GdBvh = preload("res://scripts/shared/bvh.gd")
const _GdTracer = preload("res://scripts/shared/path_tracer.gd")

static var _native_checked := false
static var _native := false


## True when the engine was built with the cgame_raytrace module.
static func is_native() -> bool:
	if not _native_checked:
		_native = ClassDB.class_exists("CgameBVH") and ClassDB.class_exists("CgamePathTracer")
		_native_checked = true
	return _native


## Static native methods are called through a cached instance.
static var _tracer_inst: Object = null


static func _tracer() -> Object:
	if _tracer_inst == null:
		_tracer_inst = ClassDB.instantiate("CgamePathTracer")
	return _tracer_inst


static func make_bvh(tris: PackedVector3Array = PackedVector3Array()) -> Object:
	var bvh: Object = ClassDB.instantiate("CgameBVH") if is_native() else _GdBvh.new()
	bvh.build(tris)
	return bvh


static func make_light(sun_dir: Vector3, sun_color: Color, sky_color: Color,
		albedo_per_tri: PackedColorArray = PackedColorArray(), bounces: int = 3) -> Dictionary:
	return {
		"sun_dir": sun_dir, "sun_color": sun_color, "sky_color": sky_color,
		"albedo": albedo_per_tri, "bounces": bounces,
	}


static func bake_vertex_lighting(bvh: Object, vertices: PackedVector3Array, normals: PackedVector3Array,
		albedo_per_tri: PackedColorArray, sun_dir: Vector3, sun_color: Color, sky_color: Color,
		samples: int, bounces: int, seed: int) -> PackedColorArray:
	if is_native():
		return _tracer().bake_vertex_lighting(bvh, vertices, normals,
				albedo_per_tri, sun_dir, sun_color, sky_color, samples, bounces, seed)
	return _GdTracer.bake_vertex_lighting(bvh, vertices, normals, albedo_per_tri, sun_dir, sun_color,
			sky_color, samples, bounces, seed)


static func bake_ambient_occlusion(bvh: Object, vertices: PackedVector3Array, normals: PackedVector3Array,
		samples: int, max_dist: float, seed: int) -> PackedFloat32Array:
	if is_native():
		return _tracer().bake_ambient_occlusion(bvh, vertices, normals,
				samples, max_dist, seed)
	return _GdTracer.bake_ambient_occlusion(bvh, vertices, normals, samples, max_dist, seed)


static func render_image(bvh: Object, camera: Transform3D, fov_deg: float, size: Vector2i, spp: int,
		light: Dictionary = {}, seed: int = 1) -> Image:
	if is_native():
		return _tracer().render_image(bvh, camera, fov_deg, size, spp,
				light, seed)
	return _GdTracer.render_image(bvh, camera, fov_deg, size, spp, light, seed)


## Progressive renderer with a uniform interface on both backends:
## accumulate(bvh, camera, fov_deg, spp, light), pixel(x, y), to_image(), samples, passes.
class Progressive extends RefCounted:
	var _native_tracer: Object = null
	var _gd_prog = null

	var samples: int:
		get:
			return _native_tracer.get_samples() if _native_tracer else _gd_prog.samples
	var passes: int:
		get:
			return _native_tracer.get_passes() if _native_tracer else _gd_prog.passes

	func _init(p_size: Vector2i, p_seed: int = 1) -> void:
		if ClassDB.class_exists("CgamePathTracer"):
			_native_tracer = ClassDB.instantiate("CgamePathTracer")
			_native_tracer.begin_progressive(p_size, p_seed)
		else:
			_gd_prog = _GdTracer.Progressive.new(p_size, p_seed)

	func accumulate(bvh: Object, camera: Transform3D, fov_deg: float, spp: int, light: Dictionary = {}) -> void:
		if _native_tracer:
			_native_tracer.accumulate(bvh, camera, fov_deg, spp, light)
		else:
			_GdTracer.accumulate(bvh, _gd_prog, camera, fov_deg, spp, light)

	func pixel(x: int, y: int) -> Vector3:
		return _native_tracer.get_pixel(x, y) if _native_tracer else _gd_prog.pixel(x, y)

	func to_image() -> Image:
		return _native_tracer.to_image() if _native_tracer else _gd_prog.to_image()


static func make_progressive(size: Vector2i, seed: int = 1) -> Progressive:
	return Progressive.new(size, seed)
