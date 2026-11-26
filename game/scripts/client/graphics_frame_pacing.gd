extends RefCounted
## Frame pacing like UE5 r.VSync / t.MaxFPS and Unity's targetFrameRate:
## steady frame delivery beats a higher but jittery average in an action RPG.
## Performance caps to the display refresh to save battery; Ultra uses
## mailbox (low-latency, tear-free) where the driver supports it.

const FALLBACK_REFRESH := 60.0


static func display_refresh() -> float:
	var hz: float = DisplayServer.screen_get_refresh_rate()
	return _valid_refresh(hz)


static func _valid_refresh(hz: float) -> float:
	return hz if is_finite(hz) and hz >= 30.0 and hz <= 1000.0 else FALLBACK_REFRESH


static func settings(level: int, refresh_hz: float) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	var hz: float = _valid_refresh(refresh_hz)
	match tier:
		0:
			# Half-rate on high-refresh panels keeps laptops cool and frame time even.
			return {"vsync": DisplayServer.VSYNC_ENABLED, "max_fps": int(round(hz / 2.0)) if hz > 90.0 else int(round(hz))}
		1:
			return {"vsync": DisplayServer.VSYNC_ENABLED, "max_fps": int(round(hz))}
		2:
			return {"vsync": DisplayServer.VSYNC_ADAPTIVE, "max_fps": int(round(hz))}
		_:
			# Mailbox: newest frame wins, no tearing, lowest input latency.
			return {"vsync": DisplayServer.VSYNC_MAILBOX, "max_fps": 0}


static func apply(level: int) -> Dictionary:
	var profile: Dictionary = settings(level, display_refresh())
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(int(profile["vsync"]))
	Engine.max_fps = int(profile["max_fps"])
	return profile
