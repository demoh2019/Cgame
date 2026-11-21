class_name CgameLocomotionFacade
extends RefCounted
## Distance matching, stride/orientation warp and attack motion warp. Native `CgameLocomotionTools`
## when available, `distance_matching.gd` and `motion_warp.gd` otherwise.


static func playback_time_for_distance(distance_curve: PackedFloat32Array, times: PackedFloat32Array, remaining_distance: float) -> float:
	return CgameAnimNative.call_static(&"CgameLocomotionTools", "distance_matching.gd", &"playback_time_for_distance", [distance_curve, times, remaining_distance])


static func stride_play_rate(actual_speed: float, authored_speed: float, min_rate: float = 0.75, max_rate: float = 1.35) -> float:
	return CgameAnimNative.call_static(&"CgameLocomotionTools", "distance_matching.gd", &"stride_play_rate", [actual_speed, authored_speed, min_rate, max_rate])


static func orientation_warp(velocity_dir: Vector2, facing_yaw: float, max_angle: float = deg_to_rad(60.0)) -> Dictionary:
	return CgameAnimNative.call_static(&"CgameLocomotionTools", "distance_matching.gd", &"orientation_warp", [velocity_dir, facing_yaw, max_angle])


## Returns {"offset": Vector3, "yaw": float}, or {} when there is no target in reach.
static func solve_motion_warp(origin: Vector3, direction: Vector2, reach: float, targets: Array) -> Dictionary:
	if CgameAnimNative.has_native(&"CgameLocomotionTools"):
		return CgameAnimNative.call_static(&"CgameLocomotionTools", "", &"motion_warp_solve", [origin, direction, reach, targets])
	return CgameAnimNative.call_static(&"CgameMotionWarpScript", "motion_warp.gd", &"solve", [origin, direction, reach, targets])
