extends RefCounted
## Altitude snowfall: rain/snow split by ground height.
const SnowVfx = preload("res://scripts/client/snow_vfx.gd")


func run(t) -> void:
	t.current = "precipitation turns to snow above the snow line"
	t.eq(SnowVfx.snow_fraction(10.0), 0.0, "lowlands get rain")
	t.eq(SnowVfx.snow_fraction(120.0), 1.0, "peaks get snow")
	var mid := SnowVfx.snow_fraction(89.0)
	t.check(mid > 0.0 and mid < 1.0, "sleet band blends both")
	t.eq(SnowVfx.AMOUNTS[0], 0, "Performance draws no snow particles")
