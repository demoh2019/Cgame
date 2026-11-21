extends RefCounted
## Vehicle dynamics: tires, suspension, drivetrain, presets and determinism.

const VehicleDynamics = preload("res://scripts/shared/vehicle_dynamics.gd")
const VehiclePresets = preload("res://scripts/shared/vehicle_presets.gd")

const DT: float = 1.0 / 60.0


func _flat(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	if dir.y >= -0.0001:
		return {"hit": false}
	var d: float = origin.y / -dir.y
	if d < 0.0 or d > max_dist:
		return {"hit": false}
	return {"hit": true, "distance": d, "normal": Vector3.UP, "friction": 1.0}


func _split_mu(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var r: Dictionary = _flat(origin, dir, max_dist)
	if bool(r.get("hit", false)):
		var p: Vector3 = origin + dir * float(r["distance"])
		r["friction"] = 0.15 if p.x < 0.0 else 1.0
	return r


func _make(cfg: Dictionary, y_offset: float = 0.3) -> VehicleDynamics:
	var v := VehicleDynamics.new()
	v.setup(cfg)
	v.reset(Vector3(0.0, v.static_ride_height() + y_offset, 0.0))
	return v


func _run(v: VehicleDynamics, seconds: float, inputs: Dictionary, ground: Callable) -> void:
	var n: int = roundi(seconds / DT)
	for i in n:
		v.step(DT, inputs, ground)


func _scenario(cfg: Dictionary) -> VehicleDynamics:
	var v: VehicleDynamics = _make(cfg)
	var g := Callable(self, "_flat")
	_run(v, 1.5, {}, g)
	_run(v, 3.0, {"throttle": 1.0, "steer": 0.0}, g)
	_run(v, 1.5, {"throttle": 0.6, "steer": 0.4}, g)
	return v


func run(t) -> void:
	var g := Callable(self, "_flat")

	t.current = "pacejka"
	var peak: float = 0.0
	var peak_x: float = 0.0
	var x: float = 0.0
	while x <= 1.0:
		var f: float = VehicleDynamics.pacejka(x, 12.0, 1.65, 1.0, 0.2)
		if f > peak:
			peak = f
			peak_x = x
		x += 0.005
	var tail: float = VehicleDynamics.pacejka(1.0, 12.0, 1.65, 1.0, 0.2)
	t.check(peak_x > 0.05 and peak_x < 0.5, "force peaks at moderate slip")
	t.check(tail < peak * 0.98, "force falls after the peak")
	t.near(VehicleDynamics.pacejka(0.0, 12.0, 1.65, 1.0, 0.2), 0.0, 0.0001, "no slip no force")
	t.near(VehicleDynamics.pacejka(-0.1, 12.0, 1.65, 1.0, 0.2), -VehicleDynamics.pacejka(0.1, 12.0, 1.65, 1.0, 0.2), 0.0001, "odd symmetry")

	t.current = "friction circle"
	var tire: Dictionary = {"mu": 1.1}
	var load: float = 4000.0
	var pure_lat: Vector2 = VehicleDynamics.tire_force(0.0, 0.2, load, tire)
	var combined: Vector2 = VehicleDynamics.tire_force(0.15, 0.2, load, tire)
	t.check(combined.length() <= 1.1 * load * 1.0001, "combined force within friction circle")
	t.check(absf(combined.y) < absf(pure_lat.y), "braking/drive demand reduces lateral grip")
	t.eq(VehicleDynamics.tire_force(0.1, 0.1, 0.0, tire), Vector2.ZERO, "no load no force")
	t.check(VehicleDynamics.tire_force(0.1, 0.1, load, tire, 0.2).length() < combined.length(), "slippery ground scales grip")

	t.current = "presets"
	for cfg in [VehiclePresets.salvage_bike(), VehiclePresets.pickup_truck(), VehiclePresets.dune_buggy()]:
		var c: Dictionary = cfg
		var errs: Array[String] = VehiclePresets.validate(c)
		t.eq(errs.size(), 0, "preset %s validates clean %s" % [c["name"], errs])
	var broken: Dictionary = VehiclePresets.pickup_truck()
	broken["gearbox"] = {"gear_ratios": [1.0, 2.0], "final_drive": 3.0, "reverse_ratio": 3.0,
		"shift_up_rpm": 3000.0, "shift_down_rpm": 4000.0}
	broken["differential"] = {"type": "spool"}
	broken["mass"] = 0.0
	var berrs: Array[String] = VehiclePresets.validate(broken)
	t.check(berrs.size() >= 4, "broken config reports errors (%d)" % berrs.size())
	var empty_errs: Array[String] = VehiclePresets.validate({})
	t.check(empty_errs.size() > 5, "empty config reports many errors")

	t.current = "settle"
	var truck_cfg: Dictionary = VehiclePresets.pickup_truck()
	var truck: VehicleDynamics = _make(truck_cfg)
	_run(truck, 4.0, {}, g)
	t.near(truck.position.y, truck.static_ride_height(), 0.04, "settles at rest height")
	t.check(truck.velocity.length() < 0.05, "at rest after settling")
	var tel: Dictionary = truck.telemetry()
	var wheels: Array = tel["wheels"]
	var sum_force: float = 0.0
	for wd in wheels:
		var d: Dictionary = wd
		sum_force += float(d["load"])
	t.near(sum_force, truck_cfg["mass"] * 9.81, truck_cfg["mass"] * 9.81 * 0.05, "suspension carries the weight")
	t.check(truck.basis.y.dot(Vector3.UP) > 0.999, "stays level")
	for cfg in [VehiclePresets.salvage_bike(), VehiclePresets.dune_buggy()]:
		var c2: Dictionary = cfg
		var veh: VehicleDynamics = _make(c2)
		_run(veh, 4.0, {}, g)
		t.check(absf(veh.position.y - veh.static_ride_height()) < 0.05 and veh.basis.y.dot(Vector3.UP) > 0.995,
			"%s rests upright" % c2["name"])

	t.current = "load compression"
	var heavy_cfg: Dictionary = VehiclePresets.pickup_truck()
	heavy_cfg["mass"] = 2800.0
	var heavy: VehicleDynamics = _make(heavy_cfg)
	_run(heavy, 4.0, {}, g)
	var comp_light: float = float((truck.telemetry()["wheels"][0] as Dictionary)["compression"])
	var comp_heavy: float = float((heavy.telemetry()["wheels"][0] as Dictionary)["compression"])
	t.check(comp_heavy > comp_light * 1.2, "heavier vehicle compresses more (%.3f vs %.3f)" % [comp_heavy, comp_light])

	t.current = "throttle and gearbox"
	var car: VehicleDynamics = _make(VehiclePresets.pickup_truck())
	_run(car, 1.0, {}, g)
	_run(car, 7.0, {"throttle": 1.0}, g)
	var ct: Dictionary = car.telemetry()
	t.check(float(ct["speed"]) > 12.0, "throttle accelerates (%.1f m/s)" % float(ct["speed"]))
	t.check(int(ct["gear"]) >= 2, "auto gearbox upshifted (gear %d)" % int(ct["gear"]))
	t.check(float(ct["rpm"]) <= 5800.0 + 1.0, "rpm stays at or below redline")
	t.check(car.velocity.dot(-car.basis.z) > 0.0, "moves forward (-Z)")
	t.check(absf(car.position.x) < 0.5, "tracks straight")

	t.current = "braking"
	var min_speed: float = 1000.0
	var brake_n: int = roundi(6.0 / DT)
	for i in brake_n:
		car.step(DT, {"throttle": 0.0, "brake": 1.0}, g)
		if i < roundi(5.0 / DT):
			min_speed = minf(min_speed, absf(car.velocity.dot(-car.basis.z)))
	t.check(min_speed < 0.5, "brakes bring the vehicle to a stop (min %.2f m/s)" % min_speed)

	t.current = "steering"
	var left: VehicleDynamics = _make(VehiclePresets.dune_buggy())
	var right: VehicleDynamics = _make(VehiclePresets.dune_buggy())
	_run(left, 1.0, {}, g)
	_run(right, 1.0, {}, g)
	_run(left, 3.0, {"throttle": 0.8}, g)
	_run(right, 3.0, {"throttle": 0.8}, g)
	_run(left, 1.5, {"throttle": 0.5, "steer": 0.5}, g)
	_run(right, 1.5, {"throttle": 0.5, "steer": -0.5}, g)
	t.check(left.angular_velocity.y > 0.1, "positive steer yaws left (%.2f)" % left.angular_velocity.y)
	t.check(right.angular_velocity.y < -0.1, "negative steer yaws right (%.2f)" % right.angular_velocity.y)
	t.check(left.position.x < -0.3 and right.position.x > 0.3, "vehicle moves toward the steered side")

	t.current = "handbrake"
	var hb_free: VehicleDynamics = _make(VehiclePresets.dune_buggy())
	var hb_pull: VehicleDynamics = _make(VehiclePresets.dune_buggy())
	for veh in [hb_free, hb_pull]:
		var vv: VehicleDynamics = veh
		_run(vv, 1.0, {}, g)
		_run(vv, 4.0, {"throttle": 1.0}, g)
	_run(hb_free, 0.5, {"throttle": 0.0}, g)
	_run(hb_pull, 0.5, {"throttle": 0.0, "handbrake": 1.0}, g)
	var rear_free: float = absf(float((hb_free.telemetry()["wheels"][2] as Dictionary)["slip_ratio"]))
	var rear_pull: float = absf(float((hb_pull.telemetry()["wheels"][2] as Dictionary)["slip_ratio"]))
	t.check(rear_pull > 0.5 and rear_pull > rear_free * 3.0, "handbrake locks the rear wheels (%.2f vs %.2f)" % [rear_pull, rear_free])
	var front_pull: float = absf(float((hb_pull.telemetry()["wheels"][0] as Dictionary)["slip_ratio"]))
	t.check(front_pull < rear_pull, "front wheels keep rolling")

	t.current = "differential"
	var open_cfg: Dictionary = VehiclePresets.pickup_truck()
	var locked_cfg: Dictionary = VehiclePresets.pickup_truck()
	locked_cfg["differential"] = {"type": "locked"}
	var sm := Callable(self, "_split_mu")
	var spreads: Array[float] = []
	for cfg in [open_cfg, locked_cfg]:
		var dv: VehicleDynamics = _make(cfg)
		_run(dv, 1.0, {}, sm)
		_run(dv, 2.0, {"throttle": 1.0}, sm)
		var dw: Array = dv.telemetry()["wheels"]
		spreads.append(absf(float((dw[2] as Dictionary)["omega"]) - float((dw[3] as Dictionary)["omega"])))
	t.check(spreads[1] < spreads[0] * 0.5, "locked diff equalises wheel speeds (%.1f vs open %.1f)" % [spreads[1], spreads[0]])

	t.current = "determinism"
	var a: VehicleDynamics = _scenario(VehiclePresets.pickup_truck())
	var b: VehicleDynamics = _scenario(VehiclePresets.pickup_truck())
	t.eq(a.position, b.position, "same inputs give identical position")
	t.eq(a.velocity, b.velocity, "same inputs give identical velocity")
	t.eq(a.gear, b.gear, "same inputs give identical gear")
