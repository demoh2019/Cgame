extends RefCounted
## Spatial filtering: terrain occlusion, distance air absorption and the listener's own muffling
## (Unity Audio Low Pass + occlusion plugins / Unreal Sound Attenuation: Air Absorption + Occlusion).

const OPEN_CUTOFF := 20500.0
const MUFFLED_CUTOFF := 1400.0


## True when the straight line from listener to source dips below the terrain somewhere between them.
static func terrain_blocked(from: Vector3, to: Vector3, height_at: Callable, steps: int = 8, margin: float = 0.4) -> bool:
	for i in range(1, steps):
		var p := from.lerp(to, float(i) / float(steps))
		if float(height_at.call(p.x, p.z)) > p.y + margin:
			return true
	return false


## Cutoff for a source: drops with distance (air absorbs highs, more so in rain/fog) and when occluded.
static func source_cutoff(distance: float, occluded: bool, humidity: float = 0.0) -> float:
	var k := 1.0 / (1.0 + distance * (0.012 + 0.02 * clampf(humidity, 0.0, 1.0)))
	var cutoff := lerpf(3500.0, OPEN_CUTOFF, k)
	if occluded:
		cutoff = minf(cutoff, MUFFLED_CUTOFF)
	return cutoff


## Matches the native AudioOcclusionPolicy's per-source log-frequency
## response when the game runs on a standard Godot build.
static func obstruction_cutoff(base_cutoff: float, amount: float) -> float:
	var cutoff: float = clampf(base_cutoff if is_finite(base_cutoff) else 5000.0,
		20.0, OPEN_CUTOFF)
	var weight: float = clampf(amount if is_finite(amount) else 0.0, 0.0, 1.0)
	if weight <= 0.0:
		return cutoff
	return exp(lerpf(log(cutoff), log(minf(cutoff, MUFFLED_CUTOFF)), weight))


static func obstruction_db(amount: float) -> float:
	var weight: float = clampf(amount if is_finite(amount) else 0.0, 0.0, 1.0)
	return -8.0 * weight


## Bus low-pass target for the listener: muffled underground, slightly dulled in a storm.
static func listener_cutoff(underground: bool, storm: float) -> float:
	if underground:
		return 9000.0
	return lerpf(OPEN_CUTOFF, 12000.0, clampf(storm, 0.0, 1.0))


## Frame-rate independent glide in the log-frequency domain (pitch perception is logarithmic).
static func glide(current: float, target: float, delta: float, rate: float = 4.0) -> float:
	var w := 1.0 - exp(-rate * delta)
	return exp(lerpf(log(maxf(current, 20.0)), log(maxf(target, 20.0)), w))
