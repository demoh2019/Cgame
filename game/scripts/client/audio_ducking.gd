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


## Native AudioDuckMix parity fallback: independent, named duck sources.
## A repeated event refreshes its hold, preserving its previous deeper dip.
## A single invalid source never mutates another live event.
static func trigger_source(sources: Dictionary, source: String, depth_db: float,
		hold_seconds: float = HOLD) -> bool:
	if source.is_empty() or source.length() > 128 or not is_finite(depth_db) \
			or depth_db >= 0.0 or depth_db < -60.0 or not is_finite(hold_seconds) \
			or hold_seconds <= 0.0 or hold_seconds > 30.0:
		return false
	if not sources.has(source) and sources.size() >= 32:
		return false
	var deeper: float = minf(float(sources[source]["depth"]), depth_db) if sources.has(source) else depth_db
	sources[source] = {"depth": deeper, "remaining": hold_seconds}
	return true


static func target_sources(sources: Dictionary) -> float:
	var deepest := 0.0
	for state in sources.values():
		deepest = minf(deepest, float(state["depth"]))
	return deepest


## Advance before mixing: sources expiring exactly at this tick have no hold.
static func tick_sources(sources: Dictionary, current: float, delta: float) -> float:
	if not is_finite(delta) or delta <= 0.0:
		return current
	for source in sources.keys():
		var state: Dictionary = sources[source]
		var remaining: float = float(state["remaining"]) - delta
		if remaining <= 0.0:
			sources.erase(source)
		else:
			state["remaining"] = remaining
	return step(current, target_sources(sources), delta)
