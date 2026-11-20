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
