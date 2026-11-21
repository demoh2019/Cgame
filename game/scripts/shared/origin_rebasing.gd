extends RefCounted
## Floating-origin world rebasing: when the camera drifts further than `threshold` from the
## engine origin, every top-level Node3D is shifted back by a multiple of `grid_step`, so float32
## precision stays high near the camera while the logical world can be arbitrarily large.
##
## Concept (not code) from the common "floating origin" technique (Unity floating-origin
## samples, UE World Origin Rebasing docs). Original GDScript; no third-party code copied, so no
## license obligations.
##
## The shift is always a multiple of `grid_step`, so shaders using world-space noise can stay
## seamless: sample noise at (world_pos + noise_offset(period)) with `period` dividing grid_step.
## The accumulated origin is stored as int cells (exact, 64-bit) and positions as
## (cell, float remainder) pairs, so no precision is lost however many shifts happen.

const EXCLUDE_GROUP := &"origin_rebase_exclude"

## Distance of the camera from the engine origin that triggers a rebase.
var threshold: float = 2048.0
## All shifts are multiples of this. Keep it a multiple of any shader noise period.
var grid_step: float = 512.0
## Ignore the Y axis when deciding / shifting (flat worlds keep their vertical precision).
var horizontal_only: bool = true
## World position of the engine origin, in grid_step cells (exact int64).
var origin_cells: Vector3i = Vector3i.ZERO
var shift_count: int = 0

var _listeners: Array[Callable] = []


## Returns the shift to apply (ZERO when the camera is still within `threshold`).
func check(camera_world_pos: Vector3) -> Vector3:
	var p := camera_world_pos
	if horizontal_only:
		p.y = 0.0
	if p.length() <= threshold:
		return Vector3.ZERO
	var s := Vector3(
		-snappedf(p.x, grid_step),
		0.0 if horizontal_only else -snappedf(p.y, grid_step),
		-snappedf(p.z, grid_step))
	return s


## Moves non-excluded top-level Node3D children of `root` by `shift`, accounts the shift in the
## origin and notifies listeners. Returns the number of moved nodes.
func apply(root: Node3D, shift: Vector3) -> int:
	if shift == Vector3.ZERO:
		return 0
	var moved := 0
	for child in root.get_children():
		var n := child as Node3D
		if n == null or n.is_in_group(EXCLUDE_GROUP):
			continue
		n.position += shift
		moved += 1
	commit(shift)
	return moved


## Accounts a shift (already applied by the caller, e.g. to physics bodies) and fires listeners.
func commit(shift: Vector3) -> void:
	if shift == Vector3.ZERO:
		return
	origin_cells -= Vector3i(roundi(shift.x / grid_step), roundi(shift.y / grid_step), roundi(shift.z / grid_step))
	shift_count += 1
	for cb in _listeners:
		if cb.is_valid():
			cb.call(shift)


## Register a callback `func(shift: Vector3)` for systems that cache world positions.
func add_listener(cb: Callable) -> void:
	if not _listeners.has(cb):
		_listeners.append(cb)


func remove_listener(cb: Callable) -> void:
	_listeners.erase(cb)


## Engine-local position -> logical world position (float32, fine for display / short ranges).
func to_global_world(p: Vector3) -> Vector3:
	return Vector3(origin_cells) * grid_step + p


## Logical world position -> engine-local position.
func to_local_world(p: Vector3) -> Vector3:
	return p - Vector3(origin_cells) * grid_step


## Drift-free form of a local position: {"cell": Vector3i, "rem": Vector3} with the world position
## equal to cell * grid_step + rem and rem in [0, grid_step).
func to_global_split(p: Vector3) -> Dictionary:
	var fx := floorf(p.x / grid_step)
	var fy := floorf(p.y / grid_step)
	var fz := floorf(p.z / grid_step)
	var rem := Vector3(p.x - fx * grid_step, p.y - fy * grid_step, p.z - fz * grid_step)
	return {"cell": origin_cells + Vector3i(int(fx), int(fy), int(fz)), "rem": rem}


## Inverse of to_global_split relative to the current origin.
func from_global_split(cell: Vector3i, rem: Vector3) -> Vector3:
	var d := cell - origin_cells
	return Vector3(float(d.x) * grid_step + rem.x, float(d.y) * grid_step + rem.y, float(d.z) * grid_step + rem.z)


## Offset to add to engine-local positions before sampling world-space noise of the given period
## (period must divide grid_step for the result to be seamless across shifts).
func noise_offset(period: float) -> Vector3:
	return Vector3(
		fposmod(float(origin_cells.x) * grid_step, period),
		fposmod(float(origin_cells.y) * grid_step, period),
		fposmod(float(origin_cells.z) * grid_step, period))
