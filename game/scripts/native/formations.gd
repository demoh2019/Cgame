extends RefCounted
## Facade for group formations: uses the native CgameFormations engine class when
## it is available and falls back to res://scripts/shared/formations.gd otherwise.
## Same API as the GDScript library (static slots, targets, assign, assignment_cost,
## blend, smooth, shift_slots and the KINDS / HUNGARIAN_LIMIT constants).

const Fallback = preload("res://scripts/shared/formations.gd")
const NATIVE_CLASS := &"CgameFormations"

const HUNGARIAN_LIMIT := 64
const KINDS: PackedStringArray = ["line", "wedge", "circle", "column"]

static var _native: RefCounted = null


static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


static func _impl() -> RefCounted:
	if _native == null:
		_native = ClassDB.instantiate(NATIVE_CLASS)
	return _native


static func slots(kind: String, count: int, spacing: float) -> PackedVector2Array:
	if is_native():
		return _impl().slots(kind, count, spacing)
	return Fallback.slots(kind, count, spacing)


static func targets(leader_pos: Vector2, leader_heading: float, kind: String, count: int, spacing: float) -> PackedVector2Array:
	if is_native():
		return _impl().targets(leader_pos, leader_heading, kind, count, spacing)
	return Fallback.targets(leader_pos, leader_heading, kind, count, spacing)


static func assign(slots_world: PackedVector2Array, members: PackedVector2Array) -> PackedInt32Array:
	if is_native():
		return _impl().assign(slots_world, members)
	return Fallback.assign(slots_world, members)


static func assignment_cost(slots_world: PackedVector2Array, members: PackedVector2Array, assignment: PackedInt32Array) -> float:
	if is_native():
		return _impl().assignment_cost(slots_world, members, assignment)
	return Fallback.assignment_cost(slots_world, members, assignment)


static func blend(from_slots: PackedVector2Array, to_slots: PackedVector2Array, t: float) -> PackedVector2Array:
	if is_native():
		return _impl().blend(from_slots, to_slots, t)
	return Fallback.blend(from_slots, to_slots, t)


static func smooth(current: PackedVector2Array, goal: PackedVector2Array, dt: float, rate: float = 6.0) -> PackedVector2Array:
	if is_native():
		return _impl().smooth(current, goal, dt, rate)
	return Fallback.smooth(current, goal, dt, rate)


static func shift_slots(slots_world: PackedVector2Array, walkable: Callable, leader_pos: Vector2, spacing: float, rings: int = 6) -> PackedVector2Array:
	if is_native():
		return _impl().shift_slots(slots_world, walkable, leader_pos, spacing, rings)
	return Fallback.shift_slots(slots_world, walkable, leader_pos, spacing, rings)
