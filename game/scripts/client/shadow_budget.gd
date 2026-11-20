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
