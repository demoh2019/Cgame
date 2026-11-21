extends RefCounted
## Per-chunk shadow caster LOD for the open world.
## A MultiMesh draws many objects in one pass, so limit participation in the sun's
## shadow maps separately from its regular visibility. Simulation is untouched.
## World-space bounds (rather than chunk centres) keep edge trees from losing shadows.

const HYSTERESIS := 5.0
# Crossing 1.5 m of camera movement can never skip a whole 5 m
# shadow-caster hysteresis interval. No per-frame batch traversal.
const CAMERA_REFRESH_METERS := 1.5
const CAMERA_REFRESH_SQUARED := CAMERA_REFRESH_METERS * CAMERA_REFRESH_METERS
static var _revision: int = 0
static var _any_casters_allowed: bool = true

# Balanced is the safe startup default before the player's preference is applied.
static var _radii: Dictionary = {
	"tree": 48.0,
	"structure": 68.0,
	"bush": 26.0,
}


## GraphicsQuality supplies the same profile on startup and whenever a preset changes.
static func configure(profile: Dictionary) -> void:
	var next_radii: Dictionary = {
		"tree": maxf(0.0, float(profile.get("tree_shadow_radius", 0.0))),
		"structure": maxf(0.0, float(profile.get("structure_shadow_radius", 0.0))),
		"bush": maxf(0.0, float(profile.get("bush_shadow_radius", 0.0))),
	}
	# A repeated apply_resolution/quality frame must not invalidate all chunks.
	if _radii != next_radii:
		_radii = next_radii
		_revision += 1
	_any_casters_allowed = (
		float(_radii["tree"]) > 0.0
		or float(_radii["structure"]) > 0.0
		or float(_radii["bush"]) > 0.0)


static func revision() -> int:
	return _revision


## Called once per streamed chunk every 0.5 s. When the eye is stationary,
## skip all caster loops, transform updates and AABB distance calculations.
## New chunks, scene changes and quality changes always refresh the state.
static func needs_refresh(last_eye: Vector2, last_revision: int,
		last_count: int, camera_eye: Vector2, caster_count: int) -> bool:
	if not camera_eye.is_finite() or caster_count <= 0:
		return false
	if last_revision != _revision or last_count != caster_count:
		return true
	if not _any_casters_allowed:
		return false
	if not last_eye.is_finite():
		return true
	return last_eye.distance_squared_to(camera_eye) >= CAMERA_REFRESH_SQUARED


static func radius_for(role: String) -> float:
	return float(_radii.get(role, 0.0))


## Nearest horizontal point on the actual instance batch, not its centre. Works
## when the camera moves inside a large group of trees as well as near tile edges.
static func distance_to_bounds_xz(world_point: Vector3, bounds: AABB) -> float:
	var low: Vector3 = bounds.position
	var high: Vector3 = bounds.end
	var dx: float = maxf(maxf(low.x - world_point.x, world_point.x - high.x), 0.0)
	var dz: float = maxf(maxf(low.z - world_point.z, world_point.z - high.z), 0.0)
	return Vector2(dx, dz).length()


## Five-metre hysteresis prevents shadow maps being repeatedly invalidated at the
## budget boundary. A zero radius disables the caster on Performance entirely.
static func should_cast(role: String, distance: float, currently_casting: bool) -> bool:
	var radius: float = radius_for(role)
	if radius <= 0.0:
		return false
	return distance <= maxf(0.0, radius + (HYSTERESIS if currently_casting else -HYSTERESIS))

## 128-slot native HLOD-style solar-shadow significance budget.
## Role preference: structures before trees before tiny bush shadows.
## All bounds are world-space, so large nearby groups survive culling.
const SHADOW_CAPS := [0, 8, 16, 24]
static var _shadow_native: Object = null
static var _shadow_native_checked := false


static func cap_for_quality(quality: int) -> int:
	return SHADOW_CAPS[clampi(quality, 0, 3)]


static func role_index(role: String) -> int:
	match role:
		"bush":
			return 0
		"tree":
			return 1
		"structure":
			return 2
	return 3


## Returns source indices ordered by visual significance; no scene mutations.
## The pure GDScript fallback matches the native geometric and ranking rules.
static func select_shadow_casters(bounds_min: PackedVector3Array,
		bounds_max: PackedVector3Array, roles: PackedByteArray,
		current: PackedByteArray, camera: Vector3, budget: int,
		prefer_native: bool = true) -> PackedInt32Array:
	var radii := PackedFloat64Array([
		radius_for("bush"), radius_for("tree"), radius_for("structure")])
	if prefer_native:
		if not _shadow_native_checked:
			_shadow_native_checked = true
			if ClassDB.class_exists("SignificanceBudgetPlanner"):
				var instance: Object = ClassDB.instantiate("SignificanceBudgetPlanner")
				if instance != null and instance.has_method("select_shadow_casters"):
					_shadow_native = instance
		if _shadow_native != null:
			return _shadow_native.call("select_shadow_casters", bounds_min, bounds_max,
				roles, current, camera, radii, budget, HYSTERESIS)
	return _select_shadow_fallback(bounds_min, bounds_max, roles, current,
		camera, radii, budget, HYSTERESIS)


static func _select_shadow_fallback(bounds_min: PackedVector3Array,
		bounds_max: PackedVector3Array, roles: PackedByteArray,
		current: PackedByteArray, camera: Vector3, radii: PackedFloat64Array,
		budget: int, hysteresis: float) -> PackedInt32Array:
	var empty := PackedInt32Array()
	var n: int = bounds_min.size()
	if n != bounds_max.size() or n != roles.size() or n != current.size() or \
			n > 16384 or radii.size() != 3 or budget < 0 or budget > 128 or \
			not camera.is_finite() or not is_finite(hysteresis) or \
			hysteresis < 0.0 or hysteresis > 1000.0:
		return empty
	for radius in radii:
		if not is_finite(radius) or radius < 0.0 or radius > 1000000.0:
			return empty
	for i in n:
		var lo: Vector3 = bounds_min[i]
		var hi: Vector3 = bounds_max[i]
		if not lo.is_finite() or not hi.is_finite() or \
				lo.x > hi.x or lo.y > hi.y or lo.z > hi.z or \
				roles[i] > 3 or current[i] > 1 or \
				absf(lo.x) > 1000000.0 or absf(hi.x) > 1000000.0 or \
				absf(lo.z) > 1000000.0 or absf(hi.z) > 1000000.0:
			return empty
	if budget == 0:
		return empty
	var eligible: Array[Dictionary] = []
	for i in n:
		var role: int = int(roles[i])
		if role == 3 or radii[role] <= 0.0:
			continue
		var lo: Vector3 = bounds_min[i]
		var hi: Vector3 = bounds_max[i]
		var dx: float = maxf(maxf(lo.x - camera.x, camera.x - hi.x), 0.0)
		var dz: float = maxf(maxf(lo.z - camera.z, camera.z - hi.z), 0.0)
		var distance: float = sqrt(dx * dx + dz * dz)
		var active: bool = current[i] == 1
		var allowed: float = maxf(0.0, radii[role] +
			(hysteresis if active else -hysteresis))
		if distance > allowed:
			continue
		eligible.append({"index": i, "role": role,
			"adjusted": maxf(0.0, distance - (hysteresis if active else 0.0)),
			"distance": distance})
	eligible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["role"] != b["role"]:
			return int(a["role"]) > int(b["role"])
		if a["adjusted"] != b["adjusted"]:
			return float(a["adjusted"]) < float(b["adjusted"])
		if a["distance"] != b["distance"]:
			return float(a["distance"]) < float(b["distance"])
		return int(a["index"]) < int(b["index"]))
	var chosen := PackedInt32Array()
	for i in mini(budget, eligible.size()):
		chosen.append(int(eligible[i]["index"]))
	return chosen
