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
