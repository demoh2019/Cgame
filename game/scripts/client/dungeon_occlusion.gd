extends RefCounted
## Conservative procedural occluders for the streamed underground wall kit.
## Like Unreal's precomputed visibility or Unity's static occluders, the blocking
## geometry is deliberately simpler than the visible art. No collider or
## authoritative dungeon layout is touched.

const MIN_WALL_LENGTH := 2.0
const MIN_WALL_HEIGHT := 0.65
const INNER_WIDTH := 0.82
const INNER_HEIGHT := 0.7
const INNER_DEPTH := 0.55


## The CPU occlusion solver is useful in a room maze, not in our open overworld.
## Compatibility and low-end Performance do not pay for an additional CPU pass.
static func use_occlusion(level: int, method: String, underground: bool) -> bool:
	return underground and clampi(level, 0, 3) >= 1 and (method == "forward_plus" or method == "mobile")


## Reject small decorative meshes and non-wall-shaped bounds. Avoid culling
## through doors and windows: callers pass only solid wall kit pieces.
static func supports_wall(bounds: AABB) -> bool:
	var length: float = maxf(bounds.size.x, bounds.size.z)
	var depth: float = minf(bounds.size.x, bounds.size.z)
	return length >= MIN_WALL_LENGTH and bounds.size.y >= MIN_WALL_HEIGHT and depth <= length * 0.45


## Shrink every axis so the software occluder stays safely inside the actual wall.
## The reduced height also respects the top-down camera that looks over low walls.
static func inner_bounds(bounds: AABB) -> AABB:
	var shrink := Vector3(INNER_WIDTH, INNER_HEIGHT, INNER_DEPTH)
	# The longer horizontal side is the wall's horizontal length.
	if bounds.size.z > bounds.size.x:
		shrink = Vector3(INNER_DEPTH, INNER_HEIGHT, INNER_WIDTH)
	var size: Vector3 = bounds.size * shrink
	return AABB(bounds.get_center() - size * 0.5, size)


## Create only one cheap BoxOccluder3D within the largest solid mesh piece.
## All transformations are expressed in the wall root's local space, which
## handles GLTF child transforms and _kit's yaw, scaling and instancing.
static func add_wall(wall: Node3D) -> bool:
	if wall == null or not wall.is_inside_tree():
		return false
	var largest := AABB()
	var has_candidate := false
	var longest := 0.0
	for child in wall.find_children("*", "MeshInstance3D", true, false):
		var visual := child as MeshInstance3D
		if visual == null or visual.mesh == null:
			continue
		var relative: Transform3D = wall.global_transform.affine_inverse() * visual.global_transform
		var bounds: AABB = relative * visual.get_aabb()
		if not supports_wall(bounds):
			continue
		var face_area: float = maxf(bounds.size.x, bounds.size.z) * bounds.size.y
		if not has_candidate or face_area > longest:
			largest = bounds
			longest = face_area
			has_candidate = true
	if not has_candidate:
		return false
	var inner: AABB = inner_bounds(largest)
	var box := BoxOccluder3D.new()
	box.size = inner.size
	var occluder := OccluderInstance3D.new()
	occluder.occluder = box
	occluder.position = inner.get_center()
	wall.add_child(occluder)
	return true


## A viewport property switch is cheap compared with rebuilding streamed chunks.
## Don't set it every render frame if the underground state has not changed.
static func update_viewport(viewport: Viewport, level: int, method: String, underground: bool) -> void:
	if viewport == null:
		return
	var required := use_occlusion(level, method, underground)
	if viewport.use_occlusion_culling != required:
		viewport.use_occlusion_culling = required
