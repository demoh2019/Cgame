extends RefCounted
## Time-of-day white balance targets.
const WB = preload("res://scripts/client/graphics_white_balance.gd")


func run(t) -> void:
	t.current = "white balance follows the time of day"
	var noon := WB.target(1.0, 0.9, 0.0)
	var golden := WB.target(0.6, 0.08, 0.0)
	var night := WB.target(0.0, -0.5, 0.0)
	t.check(absf(noon.x) < 0.05, "midday stays neutral")
	t.check(golden.x > 0.2, "golden hour is warm")
	t.check(night.x < -0.2, "moonlight is cool")
	t.check(WB.target(1.0, 0.9, 1.0).y < 0.0, "storm light leans green-grey")
	var env := Environment.new()
	WB.apply(env, 0.6, 0.08, 0.0) # Must not error on builds without the property.
