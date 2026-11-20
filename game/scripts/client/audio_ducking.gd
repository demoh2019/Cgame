extends RefCounted
## Sidechain-style ducking (Unity AudioMixer Duck Volume / Unreal Sound Mix + Submix Sidechain).
## Big events dip the music (and ambience a little) for a moment, then it recovers.

const DEPTH_DB := {"death": -12.0, "outpost_taken": -8.0, "skill_up": -6.0, "knockback": -4.0, "zombie_died": -3.0}
const ATTACK := 40.0 # dB per second going down (fast),
const RELEASE := 4.0 # and coming back (slow).
const HOLD := 1.2    # seconds a dip is held before release.


static func depth_for(event_type: String) -> float:
	return float(DEPTH_DB.get(event_type, 0.0))


## New duck amount in dB (<= 0) moving toward `target` (the deepest active dip, 0 = none).
static func step(current: float, target: float, delta: float) -> float:
	if target < current:
		return maxf(current - ATTACK * delta, target)
	return minf(current + RELEASE * delta, target)
