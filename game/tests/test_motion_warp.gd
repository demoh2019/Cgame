extends RefCounted
## Cosmetic melee motion warping: lunge toward the enemy in front, never into it.

const MotionWarp = preload("res://scripts/client/motion_warp.gd")


func run(t) -> void:
	t.current = "motion warping"
	var origin := Vector3.ZERO
	var ahead: Dictionary = MotionWarp.solve(origin, Vector2(0, 1), 1.6, [Vector3(0, 0, 2.0)])
	t.check(not ahead.is_empty(), "enemy in front is a warp target")
	t.near((ahead["offset"] as Vector3).length(), MotionWarp.MAX_SLIDE, 0.0001, "slide is capped")
	t.near(float(ahead["yaw"]), 0.0, 0.0001, "faces the target")
	var close: Dictionary = MotionWarp.solve(origin, Vector2(0, 1), 1.6, [Vector3(0, 0, 0.9)])
	t.check((close["offset"] as Vector3).length() <= 0.9 - MotionWarp.STOP_SHORT + 0.0001, "never slides into the body")
	t.check(MotionWarp.solve(origin, Vector2(0, 1), 1.6, [Vector3(0, 0, -2.0)]).is_empty(), "nothing behind the swing")
	t.check(MotionWarp.solve(origin, Vector2(0, 1), 1.6, [Vector3(0, 0, 6.0)]).is_empty(), "nothing far out of reach")
	var pick: Dictionary = MotionWarp.solve(origin, Vector2(1, 0), 1.6, [Vector3(2.5, 0, 0.3), Vector3(1.8, 0, -0.2)])
	t.check((pick["offset"] as Vector3).x > 0.0, "warps toward the nearest in the cone")
	t.check(MotionWarp.solve(origin, Vector2.ZERO, 1.6, [Vector3(0, 0, 1)]).is_empty(), "no direction, no warp")
