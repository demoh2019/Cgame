extends RefCounted
## Scalable directional-light penumbrae and weather shadow contrast.
## Avoid expensive PCSS on the low-end tiers, and never select it on
## Compatibility/Mobile. The sun remains the existing single light.

## Godot's light_angular_distance > 0 activates directional PCSS on
## Forward+. Even a visually subtle 0.6 degrees costs noticeably more.
static func settings(level: int, rendering_method: String) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	var modern: bool = rendering_method == "forward_plus"
	var angle: float = 0.0
	if modern and tier == 2:
		angle = 0.35
	elif modern and tier == 3:
		angle = 0.53 # Earth's approximate solar angular diameter.
	return {"angular_distance": angle, "pcss": angle > 0.0}


## Directional shadow contrast follows actual direct illumination:
## low sun, moonlight and thick cloud cover all cast weaker shadows.
## This does not change shadow-map count, cascade distance or quality.
static func opacity(daylight: float, sun_height: float, storm: float) -> float:
	var day: float = clampf(daylight, 0.0, 1.0)
	var cloud: float = clampf(storm, 0.0, 1.0)
	var altitude: float = smoothstep(0.0, 0.55, clampf(sun_height, 0.0, 1.0))
	var night: float = 1.0 - smoothstep(0.08, 0.5, day)
	var sunlight: float = lerpf(0.58, 0.95, altitude)
	var clear: float = lerpf(sunlight, 0.24, night)
	return clampf(clear * (1.0 - cloud * 0.60), 0.08, 0.96)


## Configure PCSS only when the preset or renderer changes, not per frame.
## Existing cascades, blur, scene shadow masks and runtime enable flags stay put.
static func apply(sun: DirectionalLight3D, level: int, rendering_method: String,
		daylight: float, sun_height: float, storm: float) -> void:
	if sun == null:
		return
	var profile: Dictionary = settings(level, rendering_method)
	sun.light_angular_distance = float(profile["angular_distance"])
	update_opacity(sun, daylight, sun_height, storm)


## Weather changes slowly. Calling at 5 Hz avoids redundant RenderingServer
## property updates while retaining smooth fades across multiple seconds.
static func update_opacity(sun: DirectionalLight3D, daylight: float,
		sun_height: float, storm: float) -> void:
	if sun == null:
		return
	var target: float = opacity(daylight, sun_height, storm)
	if absf(sun.shadow_opacity - target) > 0.003:
		sun.shadow_opacity = target
