extends RefCounted
## Vehicle config presets and an editor-style validator for vehicle_dynamics.gd.
##
## Numbers are plausible engineering magnitudes tuned for gameplay (not from any licensed
## dataset). Tire coefficients follow typical magic-formula magnitudes from Pacejka's
## public literature; structure follows Marco Monster's "Car Physics for Games".

const DIFF_TYPES: Array[String] = ["open", "locked", "limited_slip"]


static func _wheel(x: float, y: float, z: float, radius: float, rest: float, travel: float,
		k: float, c: float, steer: float, drive: float, brake: float, handbrake: float) -> Dictionary:
	return {
		"position": Vector3(x, y, z), "radius": radius, "rest": rest, "max_travel": travel,
		"stiffness": k, "damping": c, "steer": steer, "drive": drive, "brake": brake,
		"handbrake": handbrake, "inertia": 1.2 + radius * 4.0,
	}


## Light salvage motorcycle: two wheels, self-balancing torque, leans into corners.
static func salvage_bike() -> Dictionary:
	return {
		"name": "salvage_bike",
		"mass": 200.0,
		"inertia": Vector3(35.0, 25.0, 12.0),
		"wheels": [
			_wheel(0.0, 0.0, -0.65, 0.30, 0.25, 0.12, 16000.0, 1300.0, 0.4, 0.0, 450.0, 0.0),
			_wheel(0.0, 0.0, 0.65, 0.30, 0.25, 0.12, 16000.0, 1300.0, 0.0, 1.0, 250.0, 400.0),
		],
		"engine": {
			"torque_curve": [Vector2(1000.0, 30.0), Vector2(2000.0, 38.0), Vector2(4000.0, 52.0),
				Vector2(7000.0, 65.0), Vector2(9500.0, 60.0), Vector2(11500.0, 40.0)],
			"idle_rpm": 1400.0, "redline_rpm": 11000.0, "engine_brake": 12.0,
		},
		"gearbox": {
			"gear_ratios": [2.6, 1.9, 1.5, 1.25, 1.1, 0.97], "reverse_ratio": 2.6,
			"final_drive": 3.0, "shift_up_rpm": 9500.0, "shift_down_rpm": 4000.0, "shift_time": 0.18,
		},
		"differential": {"type": "open"},
		"anti_roll": 0.0,
		"drag": 0.25,
		"rolling_resistance": 0.02,
		"upright_stiffness": 3500.0,
		"upright_damping": 350.0,
		"lean_gain": 0.5,
	}


## Heavy rear-drive pickup: open diff, anti-roll bars, long gearing.
static func pickup_truck() -> Dictionary:
	return {
		"name": "pickup_truck",
		"mass": 2000.0,
		"inertia": Vector3(3600.0, 4000.0, 1200.0),
		"wheels": [
			_wheel(-0.85, -0.1, -1.5, 0.38, 0.35, 0.2, 49000.0, 4500.0, 0.5, 0.0, 2500.0, 0.0),
			_wheel(0.85, -0.1, -1.5, 0.38, 0.35, 0.2, 49000.0, 4500.0, 0.5, 0.0, 2500.0, 0.0),
			_wheel(-0.85, -0.1, 1.5, 0.38, 0.35, 0.2, 49000.0, 4500.0, 0.0, 1.0, 1800.0, 3000.0),
			_wheel(0.85, -0.1, 1.5, 0.38, 0.35, 0.2, 49000.0, 4500.0, 0.0, 1.0, 1800.0, 3000.0),
		],
		"engine": {
			"torque_curve": [Vector2(1000.0, 200.0), Vector2(2000.0, 300.0), Vector2(3500.0, 350.0),
				Vector2(4500.0, 330.0), Vector2(5500.0, 250.0), Vector2(6000.0, 180.0)],
			"idle_rpm": 800.0, "redline_rpm": 5800.0, "engine_brake": 50.0,
		},
		"gearbox": {
			"gear_ratios": [3.5, 2.1, 1.4, 1.0, 0.8], "reverse_ratio": 3.3,
			"final_drive": 3.7, "shift_up_rpm": 5200.0, "shift_down_rpm": 2200.0, "shift_time": 0.3,
		},
		"differential": {"type": "open"},
		"anti_roll": 12000.0,
		"drag": 0.6,
		"rolling_resistance": 0.015,
	}


## Light long-travel dune buggy: limited-slip rear diff, soft suspension.
static func dune_buggy() -> Dictionary:
	return {
		"name": "dune_buggy",
		"mass": 900.0,
		"inertia": Vector3(900.0, 1000.0, 450.0),
		"wheels": [
			_wheel(-0.75, 0.0, -1.1, 0.35, 0.4, 0.28, 18400.0, 1500.0, 0.55, 0.0, 1400.0, 0.0),
			_wheel(0.75, 0.0, -1.1, 0.35, 0.4, 0.28, 18400.0, 1500.0, 0.55, 0.0, 1400.0, 0.0),
			_wheel(-0.75, 0.0, 1.1, 0.35, 0.4, 0.28, 18400.0, 1500.0, 0.0, 1.0, 1100.0, 1800.0),
			_wheel(0.75, 0.0, 1.1, 0.35, 0.4, 0.28, 18400.0, 1500.0, 0.0, 1.0, 1100.0, 1800.0),
		],
		"engine": {
			"torque_curve": [Vector2(1500.0, 110.0), Vector2(3000.0, 180.0), Vector2(4500.0, 230.0),
				Vector2(6000.0, 250.0), Vector2(7000.0, 220.0), Vector2(7800.0, 160.0)],
			"idle_rpm": 1000.0, "redline_rpm": 7500.0, "engine_brake": 30.0,
		},
		"gearbox": {
			"gear_ratios": [2.9, 1.8, 1.25, 0.9], "reverse_ratio": 2.8,
			"final_drive": 4.1, "shift_up_rpm": 6800.0, "shift_down_rpm": 3000.0, "shift_time": 0.2,
		},
		"differential": {"type": "limited_slip", "preload": 80.0, "stiffness": 150.0},
		"anti_roll": 6000.0,
		"drag": 0.45,
		"rolling_resistance": 0.025,
		"tire": {"mu": 1.0},
	}


## Editor-style checker: returns human-readable problems, empty when the config is sound.
static func validate(config: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	if float(config.get("mass", 0.0)) <= 0.0:
		errs.append("mass must be > 0")
	var inertia_v: Variant = config.get("inertia", null)
	if not (inertia_v is Vector3):
		errs.append("inertia must be a Vector3")
	else:
		var iv: Vector3 = inertia_v
		if iv.x <= 0.0 or iv.y <= 0.0 or iv.z <= 0.0:
			errs.append("inertia components must be > 0")

	var wheels: Array = config.get("wheels", [])
	if wheels.size() < 2:
		errs.append("need at least 2 wheels")
	var drive_n: int = 0
	var steer_n: int = 0
	var brake_n: int = 0
	var sum_k: float = 0.0
	var min_travel: float = INF
	for i in wheels.size():
		var w: Dictionary = wheels[i]
		var tag: String = "wheel %d" % i
		var p: Vector3 = w.get("position", Vector3.INF)
		if not p.is_finite() or absf(p.x) > 3.0 or absf(p.y) > 2.0 or absf(p.z) > 5.0:
			errs.append("%s position out of sane range" % tag)
		var radius: float = float(w.get("radius", 0.0))
		if radius < 0.05 or radius > 1.0:
			errs.append("%s radius must be in 0.05..1.0" % tag)
		var rest: float = float(w.get("rest", 0.0))
		var travel: float = float(w.get("max_travel", 0.0))
		if rest <= 0.0:
			errs.append("%s suspension rest must be > 0" % tag)
		if travel <= 0.0 or travel > rest:
			errs.append("%s max_travel must be in (0, rest]" % tag)
		var k: float = float(w.get("stiffness", 0.0))
		if k <= 0.0:
			errs.append("%s stiffness must be > 0" % tag)
		if float(w.get("damping", -1.0)) < 0.0:
			errs.append("%s damping must be >= 0" % tag)
		sum_k += k
		min_travel = minf(min_travel, travel)
		if float(w.get("drive", 0.0)) > 0.0:
			drive_n += 1
		if absf(float(w.get("steer", 0.0))) > 0.0:
			steer_n += 1
		if float(w.get("brake", 0.0)) > 0.0:
			brake_n += 1
	if not wheels.is_empty():
		if drive_n == 0:
			errs.append("no driven wheel")
		if steer_n == 0:
			errs.append("no steered wheel")
		if brake_n == 0:
			errs.append("no braked wheel")
		if sum_k > 0.0 and min_travel < INF:
			var static_comp: float = float(config.get("mass", 0.0)) * 9.81 / sum_k
			if static_comp > min_travel:
				errs.append("static load (%.2f m) exceeds suspension max_travel" % static_comp)

	var engine: Dictionary = config.get("engine", {})
	var curve: Array = engine.get("torque_curve", [])
	if curve.size() < 2:
		errs.append("torque curve needs >= 2 points")
	var last_rpm: float = -INF
	for pt in curve:
		var v: Vector2 = pt
		if v.x <= last_rpm:
			errs.append("torque curve rpm must be strictly increasing")
			break
		if v.y < 0.0:
			errs.append("torque curve has negative torque")
			break
		last_rpm = v.x
	var idle: float = float(engine.get("idle_rpm", 0.0))
	var redline: float = float(engine.get("redline_rpm", 0.0))
	if idle <= 0.0 or redline <= idle:
		errs.append("need 0 < idle_rpm < redline_rpm")

	var gb: Dictionary = config.get("gearbox", {})
	var ratios: Array = gb.get("gear_ratios", [])
	if ratios.is_empty():
		errs.append("gear_ratios must not be empty")
	for i in ratios.size():
		if float(ratios[i]) <= 0.0:
			errs.append("gear ratio %d must be > 0" % i)
		if i > 0 and float(ratios[i]) >= float(ratios[i - 1]):
			errs.append("gear ratios must be strictly descending")
			break
	if float(gb.get("final_drive", 0.0)) <= 0.0:
		errs.append("final_drive must be > 0")
	if float(gb.get("reverse_ratio", 0.0)) <= 0.0:
		errs.append("reverse_ratio must be > 0")
	var up: float = float(gb.get("shift_up_rpm", 0.0))
	var down: float = float(gb.get("shift_down_rpm", 0.0))
	if up <= down:
		errs.append("shift_up_rpm must be > shift_down_rpm")
	if redline > 0.0 and up > redline:
		errs.append("shift_up_rpm above redline")
	if idle > 0.0 and down < idle:
		errs.append("shift_down_rpm below idle")
	# Hysteresis: after an upshift the rpm must stay above the downshift threshold.
	for i in range(1, ratios.size()):
		var prev: float = float(ratios[i - 1])
		var cur: float = float(ratios[i])
		if prev > 0.0 and cur > 0.0 and up * cur / prev <= down:
			errs.append("upshift %d->%d would immediately downshift (hunting)" % [i, i + 1])

	var diff: Dictionary = config.get("differential", {})
	if not DIFF_TYPES.has(str(diff.get("type", ""))):
		errs.append("differential type must be open, locked or limited_slip")
	if float(config.get("anti_roll", 0.0)) < 0.0:
		errs.append("anti_roll must be >= 0")
	if float(config.get("drag", 0.0)) < 0.0 or float(config.get("rolling_resistance", 0.0)) < 0.0:
		errs.append("drag and rolling_resistance must be >= 0")
	return errs
