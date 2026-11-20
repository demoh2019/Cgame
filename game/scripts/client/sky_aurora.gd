extends RefCounted
## Night aurora curtains (Skyrim / Ghost of Tsushima style) in the sky shader.
## High/Ultra only; zero on Performance/Balanced, in daylight and under clouds.


static func strength(level: int, daylight: float, storm: float) -> float:
	if level < 2:
		return 0.0
	var night: float = clampf((0.25 - daylight) / 0.2, 0.0, 1.0)
	var clear: float = clampf(1.0 - storm * 2.5, 0.0, 1.0)
	return night * clear
