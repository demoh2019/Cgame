extends RefCounted
## Shooting stars: when and how bright.
const ShootingStars = preload("res://scripts/client/shooting_stars.gd")


func run(t) -> void:
	t.current = "shooting stars on clear High/Ultra nights"
	t.check(ShootingStars.allowed(3, 0.0, 0.0), "clear Ultra night")
	t.check(not ShootingStars.allowed(1, 0.0, 0.0), "Balanced pays nothing")
	t.check(not ShootingStars.allowed(3, 0.5, 0.0), "never by day")
	t.check(not ShootingStars.allowed(3, 0.0, 0.5), "clouds hide them")
	t.eq(ShootingStars.envelope(0.0), 0.0, "starts dark")
	t.check(ShootingStars.envelope(0.3) > 0.9, "flares quickly")
	t.eq(ShootingStars.envelope(1.0), 0.0, "and is gone")
