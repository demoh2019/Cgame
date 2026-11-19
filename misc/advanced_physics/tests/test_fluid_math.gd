extends SceneTree
## Run: godot --headless --path misc/advanced_physics --script res://tests/test_fluid_math.gd

const FluidMath = preload("res://addons/advanced_physics/fluid_math.gd")

var failures: int = 0
var checks: int = 0


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("Fluid math failed: " + description)


func _close(actual: float, expected: float, tolerance: float = 0.00001) -> bool:
	return absf(actual - expected) <= tolerance


func _initialize() -> void:
	_test_submersion()
	_test_buoyancy()
	_test_drag()
	_test_magnus_and_angular_drag()
	_test_explicit_step_limiter()
	if failures > 0:
		push_error("%d of %d fluid tests failed" % [failures, checks])
		quit(1)
	else:
		print("PASS: %d fluid physics checks" % checks)
		quit(0)


func _test_submersion() -> void:
	var dry: Vector2 = FluidMath.sphere_submersion(-2.0, 0.0, 1.0)
	var full: Vector2 = FluidMath.sphere_submersion(2.0, 0.0, 1.0)
	var half: Vector2 = FluidMath.sphere_submersion(0.0, 0.0, 1.0)
	var quarter_cut: Vector2 = FluidMath.sphere_submersion(0.5, 0.0, 1.0)
	_check(_close(dry.x, 0.0), "sphere above water is dry")
	_check(_close(full.x, 1.0), "sphere under water is fully submerged")
	_check(_close(full.y, 0.0), "full sphere centroid stays at center")
	_check(_close(half.x, 0.5), "half sphere displaces half its volume")
	_check(_close(half.y, -0.375), "half sphere centroid is -3r/8")
	_check(_close(quarter_cut.x, 0.84375), "sphere cap displaced fraction")
	_check(_close(quarter_cut.y, -0.125), "sphere cap centroid")
	_check(FluidMath.sphere_submersion(0.0, 0.0, 0.0) == Vector2.ZERO, "invalid radius is ignored")
	var previous_fraction: float = 0.0
	for step in range(101):
		var level: float = -1.0 + 2.0 * float(step) / 100.0
		var sample: Vector2 = FluidMath.sphere_submersion(level, 0.0, 1.0)
		_check(sample.x >= previous_fraction - 0.000001, "submersion is monotone at step %d" % step)
		_check(sample.x >= 0.0 and sample.x <= 1.0, "submersion is bounded at step %d" % step)
		_check(sample.y >= -1.0 and sample.y <= 0.0, "centroid stays inside sphere at step %d" % step)
		previous_fraction = sample.x


func _test_buoyancy() -> void:
	var gravity: Vector3 = Vector3(0.0, -9.81, 0.0)
	var force: Vector3 = FluidMath.buoyancy_force(1000.0, 1.0, 1.0, gravity)
	_check((force - Vector3(0.0, 9810.0, 0.0)).length() < 0.001, "Archimedes law in SI units")
	_check((FluidMath.buoyancy_force(1000.0, 1.0, 0.5, gravity) - force * 0.5).length() < 0.001, "partial immersion buoyancy")
	_check(FluidMath.buoyancy_force(1000.0, 1.0, 0.0, gravity) == Vector3.ZERO, "dry body has no buoyancy")
	_check(FluidMath.buoyancy_force(-1.0, 1.0, 1.0, gravity) == Vector3.ZERO, "invalid density")
	var lever_a: Vector3 = Vector3(-1.0, 0.0, 0.0)
	var lever_b: Vector3 = Vector3(1.0, 0.0, 0.0)
	_check((lever_a.cross(force * 0.5) + lever_b.cross(force * 0.5)).length() < 0.001, "symmetric lift has zero torque")


func _test_drag() -> void:
	var slow: Vector3 = FluidMath.quadratic_drag(1.0, 1.0, 1.0, Vector3.RIGHT)
	var fast: Vector3 = FluidMath.quadratic_drag(1.0, 1.0, 1.0, Vector3.RIGHT * 2.0)
	_check(_close(slow.x, -0.5), "quadratic drag coefficient")
	_check(_close(fast.x, -2.0), "doubling speed quadruples drag")
	_check(FluidMath.quadratic_drag(1.0, 1.0, 1.0, Vector3.ZERO) == Vector3.ZERO, "zero relative flow produces no drag")
	_check(FluidMath.quadratic_drag(0.0, 1.0, 1.0, Vector3.RIGHT) == Vector3.ZERO, "zero-density flow")
	_check(_close(FluidMath.stokes_drag(1.0, 1.0, Vector3.RIGHT).x, -6.0 * PI), "low-Reynolds Stokes drag")
	_check(FluidMath.stokes_drag(0.0, 1.0, Vector3.RIGHT) == Vector3.ZERO, "zero viscosity")


func _test_magnus_and_angular_drag() -> void:
	var lift: Vector3 = FluidMath.magnus_force(1.0, 1.0, 1.0, Vector3.BACK, Vector3.RIGHT)
	_check((lift - Vector3.UP).length() < 0.00001, "spin and flow produce perpendicular Magnus lift")
	_check(FluidMath.magnus_force(1.0, 1.0, 0.0, Vector3.BACK, Vector3.RIGHT) == Vector3.ZERO, "disabled Magnus force")
	var torque: Vector3 = FluidMath.angular_drag(1.0, 1.0, 1.0, Vector3(0.0, 2.0, 0.0))
	_check(torque.y < 0.0 and _close(torque.y, -2.0), "angular drag opposes spin")
	_check(FluidMath.angular_drag(1.0, 1.0, 1.0, Vector3.ZERO) == Vector3.ZERO, "no angular damping at rest")


func _test_explicit_step_limiter() -> void:
	var capped: Vector3 = FluidMath.limit_opposing_force(Vector3(-200.0, 0.0, 0.0), Vector3(10.0, 0.0, 0.0), 1.0, 0.1, 2)
	_check(_close(capped.x, -50.0), "drag cannot overshoot sample velocity in a step")
	_check(FluidMath.limit_opposing_force(Vector3.UP, Vector3.RIGHT, 1.0, 0.1, 1) == Vector3.UP, "perpendicular forces not clamped")
	_check(FluidMath.limit_opposing_force(Vector3.ZERO, Vector3.ZERO, 1.0, 0.1, 1) == Vector3.ZERO, "zero-velocity limiter finite")
