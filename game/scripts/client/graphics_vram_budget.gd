extends RefCounted
## GPU memory budget (UE5 r.Streaming.PoolSize / texture budget, Unity
## memory budget): watches live video memory and, under sustained
## pressure, asks Auto quality to step down before the driver starts
## paging/evicting (the source of multi-second hitches on 8 GB machines).

const BUDGET_MB := [1536.0, 2560.0, 4096.0, 6144.0]
const PRESSURE := 0.92 # Share of the budget that counts as pressure.
const RELIEF := 0.75 # Upgrades are blocked above this share.
const SUSTAIN := 2.0

var _pressure_seconds := 0.0


static func budget_bytes(level: int) -> float:
	return float(BUDGET_MB[clampi(level, 0, 3)]) * 1024.0 * 1024.0


static func used_bytes() -> float:
	return float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED))


static func upgrade_allowed(used: float, level: int) -> bool:
	return used <= budget_bytes(level + 1) * RELIEF


## True once memory has stayed above the pressure line for SUSTAIN seconds.
func sample(used: float, level: int, delta: float) -> bool:
	if not is_finite(delta) or delta <= 0.0:
		return false
	if used > budget_bytes(level) * PRESSURE:
		_pressure_seconds += delta
		if _pressure_seconds >= SUSTAIN:
			_pressure_seconds = 0.0
			return level > 0
	else:
		_pressure_seconds = 0.0
	return false
