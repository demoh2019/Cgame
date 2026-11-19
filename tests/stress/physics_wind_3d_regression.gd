# Run with the built-in GodotPhysics3D backend:
# godot --headless --path tests/stress --script res://physics_wind_3d_regression.gd
#
# Wind areas push rigid bodies that opt in with wind_drag_coefficient. The body must
#  * accelerate toward the air speed and never exceed it (drag vanishes at the air speed),
#  * ignore the wind when the coefficient is 0,
#  * feel less wind farther from an attenuating source,
#  * be pushed harder when it is bigger (area) or has a larger drag coefficient.
extends SceneTree

const AIR_DENSITY := 1.225
const PRESSURE := 100.0 # Pa; air speed = sqrt(2 * 100 / 1.225) = 12.78 m/s.


func _initialize() -> void:
	_run.call_deferred()


func _make_space() -> RID:
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 0.0)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_LINEAR_DAMP, 0.0)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_ANGULAR_DAMP, 0.0)
	return space


# A big box area filled with wind blowing toward +x.
func _make_wind(space: RID, pressure: float, attenuation: float, source: Vector3) -> Array:
	var shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape, Vector3(500, 500, 500))
	var area := PhysicsServer3D.area_create()
	PhysicsServer3D.area_add_shape(area, shape)
	PhysicsServer3D.area_set_space(area, space)
	PhysicsServer3D.area_set_param(area, PhysicsServer3D.AREA_PARAM_WIND_FORCE_MAGNITUDE, pressure)
	PhysicsServer3D.area_set_param(area, PhysicsServer3D.AREA_PARAM_WIND_ATTENUATION_FACTOR, attenuation)
	PhysicsServer3D.area_set_param(area, PhysicsServer3D.AREA_PARAM_WIND_SOURCE, source)
	PhysicsServer3D.area_set_param(area, PhysicsServer3D.AREA_PARAM_WIND_DIRECTION, Vector3(1, 0, 0))
	return [area, shape]


func _make_body(space: RID, position: Vector3, half: Vector3, mass: float, drag: float, area_override: float = 0.0) -> Array:
	var shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape, half)
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_MASS, mass)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 0.0)
	PhysicsServer3D.body_set_wind_drag_coefficient(body, drag)
	PhysicsServer3D.body_set_wind_area(body, area_override)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), position))
	PhysicsServer3D.body_set_space(body, space)
	return [body, shape]


func _vx(body: RID) -> float:
	return (PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY) as Vector3).x


func _run() -> void:
	var ok := true
	var space := _make_space()
	var wind := _make_wind(space, PRESSURE, 0.0, Vector3.ZERO)
	var air_speed := sqrt(2.0 * PRESSURE / AIR_DENSITY)

	# 1. A free body approaches the air speed from below, never beyond.
	var light: Array = _make_body(space, Vector3(0, 0, 0), Vector3(0.5, 0.5, 0.5), 1.0, 1.0)
	# 2. Same body with drag 0 stays put.
	var deaf: Array = _make_body(space, Vector3(0, 20, 0), Vector3(0.5, 0.5, 0.5), 1.0, 0.0)
	# 3. A heavy body accelerates more slowly than a light one.
	var heavy: Array = _make_body(space, Vector3(0, 40, 0), Vector3(0.5, 0.5, 0.5), 20.0, 1.0)
	# 4. A bigger reference area is pushed harder than a smaller one with the same mass.
	var small: Array = _make_body(space, Vector3(0, 60, 0), Vector3(0.5, 0.5, 0.5), 1.0, 1.0, 0.1)
	var large: Array = _make_body(space, Vector3(0, 80, 0), Vector3(0.5, 0.5, 0.5), 1.0, 1.0, 2.0)

	var peak := 0.0
	var early_light := 0.0
	var early_heavy := 0.0
	var early_small := 0.0
	var early_large := 0.0
	for frame in 600:
		await physics_frame
		peak = maxf(peak, _vx(light[0]))
		if frame == 5:
			early_light = _vx(light[0])
			early_heavy = _vx(heavy[0])
			early_small = _vx(small[0])
			early_large = _vx(large[0])
	var final_light := _vx(light[0])
	print("WIND_TERMINAL:" + JSON.stringify({"air_speed": air_speed, "final": final_light, "peak": peak}))
	ok = ok and final_light > air_speed * 0.97 and peak <= air_speed * 1.001
	var deaf_v := _vx(deaf[0])
	print("WIND_DEAF:" + JSON.stringify({"vx": deaf_v}))
	ok = ok and absf(deaf_v) < 1e-4
	print("WIND_RESPONSE:" + JSON.stringify({"light": early_light, "heavy": early_heavy, "small": early_small, "large": early_large}))
	ok = ok and early_light > early_heavy * 5.0
	ok = ok and early_large > early_small * 5.0

	# 5. With attenuation the wind weakens with the distance from its source.
	var space2 := _make_space()
	var wind2 := _make_wind(space2, PRESSURE, 1.0, Vector3.ZERO)
	var near_body: Array = _make_body(space2, Vector3(2, 0, 0), Vector3(0.5, 0.5, 0.5), 1.0, 1.0)
	var far_body: Array = _make_body(space2, Vector3(0, 0, 100), Vector3(0.5, 0.5, 0.5), 1.0, 1.0)
	for frame in 120:
		await physics_frame
	var near_v := _vx(near_body[0])
	var far_v := _vx(far_body[0])
	print("WIND_ATTENUATION:" + JSON.stringify({"near": near_v, "far": far_v}))
	ok = ok and near_v > far_v * 5.0 and far_v > 0.0

	# 6. Leaving the wind area stops the push (the area is only attached while inside).
	var space3 := _make_space()
	var wind3 := _make_wind(space3, PRESSURE, 0.0, Vector3.ZERO)
	var outside: Array = _make_body(space3, Vector3(0, 2000, 0), Vector3(0.5, 0.5, 0.5), 1.0, 1.0)
	for frame in 60:
		await physics_frame
	var outside_v := _vx(outside[0])
	print("WIND_OUTSIDE:" + JSON.stringify({"vx": outside_v}))
	ok = ok and absf(outside_v) < 1e-4

	for s in [space, space2, space3]:
		PhysicsServer3D.space_set_active(s, false)
	var all_objects: Array = []
	for group in [wind, wind2, wind3, light, deaf, heavy, small, large, near_body, far_body, outside]:
		all_objects.append_array(group)
	all_objects.append_array([space, space2, space3])
	for rid in all_objects:
		PhysicsServer3D.free_rid(rid)
	if ok:
		print("3D wind regression passed.")
		quit(0)
	else:
		printerr("FAIL: 3D wind regression")
		quit(1)
