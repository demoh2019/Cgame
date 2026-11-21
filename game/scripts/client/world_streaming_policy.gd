extends RefCounted
## World Partition-style stream priority follows the actual movement mode.
## This only reorders already-resident eligible cells; the engine remains
## responsible for load/unload radius, queue hygiene and shared CPU budget.

const WALK_LOOKAHEAD := 2.0
const RIDING_LOOKAHEAD := 3.0
const IDLE_VELOCITY_SQ := 0.16


static func lookahead_seconds(mounted: bool, velocity: Vector3) -> float:
	# Teleports and invalid correction samples should never steer streaming.
	if not velocity.is_finite() or velocity.length_squared() < IDLE_VELOCITY_SQ:
		return 0.0
	return RIDING_LOOKAHEAD if mounted else WALK_LOOKAHEAD


## Do not resend identical settings to the native streamer every render frame.
## User preference, world radius and generation budget stay untouched.
static func apply(streamer: WorldStreamer, mounted: bool, velocity: Vector3) -> void:
	if streamer == null:
		return
	var desired: float = lookahead_seconds(mounted, velocity)
	if not is_equal_approx(streamer.lookahead_seconds, desired):
		streamer.lookahead_seconds = desired


## Visibility-weighted streaming source inspired by Unreal World Partition.
## View weighting affects ONLY scheduling, never player-centered residency.
## No camera or mesh work is performed in the native chunk generator.
const VIEW_WEIGHTS := [0.35, 0.48, 0.66, 0.80]
# Degrees of camera change from the last real queue publication.
# The native engine batches rapid turns behind a 50 ms CPU refresh guard.
# Performance reorders less frequently; Ultra responds faster in busy scenes.
const FAST_TURN_ANGLES := [60.0, 45.0, 35.0, 30.0]


static func view_weight(level: int) -> float:
	return float(VIEW_WEIGHTS[clampi(level, 0, VIEW_WEIGHTS.size() - 1)])


static func fast_turn_angle(level: int) -> float:
	return float(FAST_TURN_ANGLES[clampi(level, 0, FAST_TURN_ANGLES.size() - 1)])


static func ground_view(camera: Camera3D) -> Vector3:
	if camera == null:
		return Vector3.ZERO
	var forward: Vector3 = -camera.global_transform.basis.z
	if not forward.is_finite():
		return Vector3.ZERO
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3.ZERO
	return forward.normalized()


## Run after Camera3D look_at(), so zoom/photo orbit uses the actual
## rendered view instead of stale movement input. Native Cgame setters are
## idempotent; do not touch loaded cells or resource allocations here.
static func apply_view(streamer: WorldStreamer, camera: Camera3D,
		graphics_level: int) -> void:
	if streamer == null:
		return
	var weight: float = view_weight(graphics_level)
	if not is_equal_approx(streamer.view_priority, weight):
		streamer.view_priority = weight
	var degrees: float = fast_turn_angle(graphics_level)
	if not is_equal_approx(streamer.fast_view_refresh_degrees, degrees):
		streamer.fast_view_refresh_degrees = degrees
	var direction: Vector3 = ground_view(camera)
	if not streamer.view_direction.is_equal_approx(direction):
		streamer.view_direction = direction


## Nearby personal map markers become a bounded second streaming source.
## Distant quest/map markers remain purely UI: they cannot load a second island
## or bypass the player's authoritative chunk residency and CPU budgets.
static func waypoint_radius(cell_size: float, mounted: bool) -> float:
	if not is_finite(cell_size) or cell_size <= 0.0:
		return 0.0
	return minf(cell_size * (2.0 if mounted else 1.5), 48.0)


static func waypoint_is_near(point: Vector2, player: Vector3,
		load_radius: float, cell_size: float) -> bool:
	if not point.is_finite() or not player.is_finite() or \
			not is_finite(load_radius) or not is_finite(cell_size) or \
			load_radius <= 0.0 or cell_size <= 0.0:
		return false
	return point.distance_to(Vector2(player.x, player.z)) <= load_radius + cell_size


## Called after focus_position updates, once per frame. Only the fork's
## WorldStreamer implements this opt-in API; ordinary script code stays
## compatible with projects that run on a binary without the extension.
static func apply_waypoint(streamer: WorldStreamer, waypoint: Vector2,
		player: Vector3, mounted: bool) -> void:
	if streamer == null or not streamer.has_method("set_auxiliary_source"):
		return
	var is_active: bool = bool(streamer.call("has_auxiliary_source"))
	if not waypoint_is_near(waypoint, player, streamer.load_radius, streamer.cell_size):
		if is_active:
			streamer.call("clear_auxiliary_source")
		return
	var radius: float = waypoint_radius(streamer.cell_size, mounted)
	var destination := Vector3(waypoint.x, 0.0, waypoint.y)
	if not is_active or \
			not (streamer.call("get_auxiliary_source_position") as Vector3).is_equal_approx(destination) or \
			not is_equal_approx(float(streamer.call("get_auxiliary_source_radius")), radius):
		streamer.call("set_auxiliary_source", destination, radius)
