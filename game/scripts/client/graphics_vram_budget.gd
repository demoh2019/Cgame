extends RefCounted
## GPU memory budget (UE5 r.Streaming.PoolSize / texture budget, Unity
## memory budget): watches live video memory and, under sustained
## pressure, asks Auto quality to step down before the driver starts
## paging/evicting (the source of multi-second hitches on 8 GB machines).

const BUDGET_MB := [1536.0, 2560.0, 4096.0, 6144.0]
const PRESSURE := 0.92 # Share of the budget that counts as pressure.
const RELIEF := 0.75 # Upgrades are blocked above this share.
const SUSTAIN := 2.0
# Loading stalls and suspended windows do not represent sustained VRAM use.
# The same guard is applied before the optional native budget tracker.
const MAX_SAMPLE_DELTA := 0.2

var _pressure_seconds := 0.0


static func budget_bytes(level: int) -> float:
	return float(BUDGET_MB[clampi(level, 0, 3)]) * 1024.0 * 1024.0


static func used_bytes() -> float:
	return float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED))


static func upgrade_allowed(used: float, level: int) -> bool:
	return is_finite(used) and used > 0.0 and used <= budget_bytes(clampi(level, 0, 3) + 1) * RELIEF


## Unknown residency must not disable the FPS-based compatibility path.
## Measurable memory pressure, however, vetoes a speculative upgrade.
static func allows_auto_upgrade(used: float, level: int) -> bool:
	return not is_finite(used) or used <= 0.0 or upgrade_allowed(used, level)


## A zero byte reading means that the renderer could not report GPU
## residency (common in headless/Compatibility), not that memory is free.
static func valid_sample(used: float, delta: float) -> bool:
	return is_finite(used) and used > 0.0 and is_finite(delta) and \
		delta > 0.0 and delta <= MAX_SAMPLE_DELTA


## True once memory has stayed above the pressure line for SUSTAIN seconds.
func sample(used: float, level: int, delta: float) -> bool:
	if not valid_sample(used, delta):
		return false
	if used > budget_bytes(level) * PRESSURE:
		_pressure_seconds += delta
		if _pressure_seconds >= SUSTAIN:
			_pressure_seconds = 0.0
			return level > 0
	else:
		_pressure_seconds = 0.0
	return false


func reset() -> void:
	_pressure_seconds = 0.0
