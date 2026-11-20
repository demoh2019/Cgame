extends RefCounted
## Damage direction indicator angle maths.
const DamageDirection = preload("res://scripts/client/damage_direction.gd")


func run(t) -> void:
	t.current = "damage arcs point at the attacker relative to the camera"
	var cam := Basis() # Looking down -Z, right = +X.
	t.near(DamageDirection.screen_angle(Vector3.ZERO, Vector3(0, 0, -5), cam), 0.0, 0.001, "ahead is up")
	t.near(DamageDirection.screen_angle(Vector3.ZERO, Vector3(5, 0, 0), cam), PI * 0.5, 0.001, "right is right")
	t.near(absf(DamageDirection.screen_angle(Vector3.ZERO, Vector3(0, 0, 5), cam)), PI, 0.001, "behind is down")
	var tilted := Basis(Vector3.RIGHT, -0.9) # Isometric pitch keeps the same yaw mapping.
	t.near(DamageDirection.screen_angle(Vector3.ZERO, Vector3(5, 0, 0), tilted), PI * 0.5, 0.001, "pitch does not matter")
