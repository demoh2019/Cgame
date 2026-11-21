extends RefCounted
## Distance Matching and Orientation Warping, inspired by UE5 Lyra locomotion
## (Distance Matching for starts/stops/pivots, Orientation Warping for strafing).


## Inverse of a monotonic distance curve: returns the playback time at which the
## animation has `remaining_distance` left. Works for increasing or decreasing curves.
static func playback_time_for_distance(distance_curve: PackedFloat32Array, times: PackedFloat32Array, remaining_distance: float) -> float:
	var n: int = mini(distance_curve.size(), times.size())
	if n == 0:
		return 0.0
	if n == 1:
		return times[0]
	var ascending: bool = distance_curve[0] <= distance_curve[n - 1]
	var first: float = distance_curve[0]
	var last: float = distance_curve[n - 1]
	if ascending:
		if remaining_distance <= first:
			return times[0]
		if remaining_distance >= last:
			return times[n - 1]
	else:
		if remaining_distance >= first:
			return times[0]
		if remaining_distance <= last:
			return times[n - 1]
	var lo: int = 0
	var hi: int = n - 1
	while hi - lo > 1:
		var mid: int = (lo + hi) / 2
		var go_right: bool = distance_curve[mid] <= remaining_distance if ascending else distance_curve[mid] >= remaining_distance
		if go_right:
			lo = mid
		else:
			hi = mid
	var d0: float = distance_curve[lo]
	var d1: float = distance_curve[hi]
	if is_equal_approx(d0, d1):
		return times[lo]
	var f: float = (remaining_distance - d0) / (d1 - d0)
	return lerpf(times[lo], times[hi], f)


## Stride warping: playback rate that makes the authored stride match actual speed.
static func stride_play_rate(actual_speed: float, authored_speed: float, min_rate: float = 0.75, max_rate: float = 1.35) -> float:
	if authored_speed <= 0.001:
		return 1.0
	return clampf(actual_speed / authored_speed, min_rate, max_rate)


## Orientation warping. velocity_dir is the horizontal travel direction, yaw
## convention atan2(x, y). Returns the lower-body offset (clamped) and the opposite
## upper-body counter-rotation so the torso keeps facing the aim direction.
## Backwards travel is folded so back-pedalling needs no warp.
static func orientation_warp(velocity_dir: Vector2, facing_yaw: float, max_angle: float = deg_to_rad(60.0)) -> Dictionary:
	if velocity_dir.length_squared() < 0.0001:
		return {"lower_body_yaw": 0.0, "upper_body_yaw": 0.0}
	var vel_yaw: float = atan2(velocity_dir.x, velocity_dir.y)
	var diff: float = angle_difference(facing_yaw, vel_yaw)
	if absf(diff) > PI * 0.5 + 0.0001:
		diff -= signf(diff) * PI
	var lower: float = clampf(diff, -max_angle, max_angle)
	return {"lower_body_yaw": lower, "upper_body_yaw": -lower}
