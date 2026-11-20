extends RefCounted
## Time-of-day white balance through the engine fork's native
## Environment.lens_white_temperature/tint (UE5 White Temp/Tint): warm golden
## hour, cool blue moonlight, slightly green-grey storm light. Pushed only when
## the value moves (>0.01), so ordinary frames make no RenderingServer call.


## Returns Vector2(temperature, tint), both -1..1.
static func target(daylight: float, sun_height: float, storm: float) -> Vector2:
	# Golden hour: sun just above the horizon in daylight.
	var golden: float = clampf(1.0 - absf(sun_height - 0.08) / 0.22, 0.0, 1.0) * clampf(daylight * 2.0, 0.0, 1.0)
	var night: float = clampf(1.0 - daylight * 2.5, 0.0, 1.0)
	var temperature: float = golden * 0.32 - night * 0.28
	temperature = lerpf(temperature, -0.08, storm * 0.7)
	var tint: float = -0.06 * storm + 0.04 * golden
	return Vector2(clampf(temperature, -1.0, 1.0), clampf(tint, -1.0, 1.0))


static func apply(env: Environment, daylight: float, sun_height: float, storm: float, neutral: bool = false) -> void:
	if env == null or not ("lens_white_temperature" in env):
		return # Stock Godot or an engine build without native white balance.
	# Underground the torches set the mood: no moonlight cast, keep neutral.
	var wb: Vector2 = Vector2.ZERO if neutral else target(daylight, sun_height, storm)
	if absf(float(env.get("lens_white_temperature")) - wb.x) > 0.01:
		env.set("lens_white_temperature", wb.x)
	if absf(float(env.get("lens_white_tint")) - wb.y) > 0.01:
		env.set("lens_white_tint", wb.y)
