extends RefCounted
## Pure-math vehicle dynamics: raycast suspension, Pacejka "magic formula" tires with a
## friction circle, engine torque curve, auto gearbox, differential, brakes and anti-roll bars.
## No scene-tree or physics-server dependency; the world is queried through a ground Callable
## so the whole model runs headless and deterministically.
##
## Conventions: body-local forward is -Z, right is +X, up is +Y (Godot). Steer input +1 turns
## LEFT (positive yaw about +Y). Wheel positions are relative to the centre of mass.
##
## Credits (concepts and public data only; no third-party code copied):
##  - Marco Monster, "Car Physics for Games" (2003): slip ratio / slip angle, traction curve,
##    weight transfer, drivetrain torque chain, friction ellipse. Public-domain style article.
##  - Hans B. Pacejka, "Tyre and Vehicle Dynamics": the magic formula
##    F = D sin(C atan(Bx - E(Bx - atan(Bx)))); B/C/E values here are typical published
##    magnitudes (B~10-12, C~1.4-1.65), not copied from a licensed dataset.
##  - Racer (Ruud van Gaal) docs: wheel spin integration with an implicit tire term.
##  - Ideas for raycast suspension and anti-roll bars follow the common spring/damper model
##    (e.g. MIT-licensed Godot/Bullet raycast-vehicle write-ups); implemented from scratch.

const GRAVITY: float = 9.81
const RAD_S_TO_RPM: float = 9.549296585513721
const DRIVE_EFFICIENCY: float = 0.9


class WheelState extends RefCounted:
	var position: Vector3 = Vector3.ZERO
	var radius: float = 0.35
	var rest: float = 0.3
	var stiffness: float = 30000.0
	var damping: float = 2500.0
	var max_travel: float = 0.2
	var steer: float = 0.0
	var drive: float = 0.0
	var brake: float = 0.0
	var handbrake: float = 0.0
	var inertia: float = 2.0
	var tire: Dictionary = {}
	# Runtime state.
	var omega: float = 0.0
	var compression: float = 0.0
	var prev_compression: float = 0.0
	var grounded: bool = false
	var load: float = 0.0
	var slip_ratio: float = 0.0
	var slip_angle: float = 0.0
	var steer_angle: float = 0.0
	var force_x: float = 0.0
	var force_y: float = 0.0
	var contact: Vector3 = Vector3.ZERO
	var pair: int = -1


# Public body state.
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var basis: Basis = Basis.IDENTITY
var angular_velocity: Vector3 = Vector3.ZERO

# Public tuning (filled by setup).
var mass: float = 1000.0
var inertia: Vector3 = Vector3(1000.0, 1000.0, 400.0)
var gear: int = 1
var engine_rpm: float = 1000.0
var max_substep: float = 1.0 / 200.0

var _wheels: Array[WheelState] = []
var _curve: PackedVector2Array = PackedVector2Array()
var _idle_rpm: float = 900.0
var _redline_rpm: float = 6500.0
var _engine_brake: float = 40.0
var _gear_ratios: PackedFloat32Array = PackedFloat32Array()
var _reverse_ratio: float = 3.0
var _final_drive: float = 3.5
var _shift_up_rpm: float = 5500.0
var _shift_down_rpm: float = 2500.0
var _shift_time: float = 0.25
var _diff: String = "open"
var _lsd_preload: float = 60.0
var _lsd_stiffness: float = 120.0
var _anti_roll: float = 0.0
var _drag: float = 0.4
var _rolling: float = 0.015
var _upright_k: float = 0.0
var _upright_c: float = 0.0
var _lean_gain: float = 0.0
var _shift_timer: float = 0.0
var _cooldown: float = 0.0
var _reverse_timer: float = 0.0
var _coupled_rpm: float = 0.0
var _last_steer: float = 0.0
var _last_throttle: float = 0.0
var _last_brake: float = 0.0
var _speed_fwd: float = 0.0


## Pacejka magic formula. x is slip (ratio or radians), d the peak force, returns force.
static func pacejka(x: float, b: float, c: float, d: float, e: float) -> float:
	var bx: float = b * x
	return d * sin(c * atan(bx - e * (bx - atan(bx))))


## Combined-slip tire force. Returns Vector2(longitudinal, lateral); the lateral component
## has the sign of the slip angle (caller applies it against the side velocity). The force
## vector is limited by a friction circle of radius mu * load.
static func tire_force(kappa: float, alpha: float, load: float, tire: Dictionary, mu_scale: float = 1.0) -> Vector2:
	if load <= 0.0:
		return Vector2.ZERO
	var mu: float = float(tire.get("mu", 1.1)) * mu_scale
	var limit: float = mu * load
	var fx: float = pacejka(kappa, float(tire.get("long_b", 12.0)), float(tire.get("long_c", 1.65)), limit, float(tire.get("long_e", 0.2)))
	var fy: float = pacejka(alpha, float(tire.get("lat_b", 10.0)), float(tire.get("lat_c", 1.4)), limit, float(tire.get("lat_e", -0.5)))
	# Friction ellipse (Monster): longitudinal demand shrinks the lateral budget.
	var used: float = clampf(absf(fx) / limit, 0.0, 1.0)
	fy *= sqrt(maxf(0.0, 1.0 - used * used))
	var mag: float = sqrt(fx * fx + fy * fy)
	if mag > limit:
		var s: float = limit / mag
		fx *= s
		fy *= s
	return Vector2(fx, fy)


func setup(config: Dictionary) -> void:
	mass = float(config.get("mass", 1000.0))
	var inertia_v: Vector3 = config.get("inertia", Vector3(1000.0, 1000.0, 400.0))
	inertia = inertia_v
	var engine: Dictionary = config.get("engine", {})
	_curve = PackedVector2Array()
	var pts: Array = engine.get("torque_curve", [])
	for p in pts:
		var v: Vector2 = p
		_curve.append(v)
	_idle_rpm = float(engine.get("idle_rpm", 900.0))
	_redline_rpm = float(engine.get("redline_rpm", 6500.0))
	_engine_brake = float(engine.get("engine_brake", 40.0))
	var gb: Dictionary = config.get("gearbox", {})
	_gear_ratios = PackedFloat32Array()
	var ratios: Array = gb.get("gear_ratios", [])
	for r in ratios:
		_gear_ratios.append(float(r))
	_reverse_ratio = float(gb.get("reverse_ratio", 3.0))
	_final_drive = float(gb.get("final_drive", 3.5))
	_shift_up_rpm = float(gb.get("shift_up_rpm", 5500.0))
	_shift_down_rpm = float(gb.get("shift_down_rpm", 2500.0))
	_shift_time = float(gb.get("shift_time", 0.25))
	var diff: Dictionary = config.get("differential", {})
	_diff = str(diff.get("type", "open"))
	_lsd_preload = float(diff.get("preload", 60.0))
	_lsd_stiffness = float(diff.get("stiffness", 120.0))
	_anti_roll = float(config.get("anti_roll", 0.0))
	_drag = float(config.get("drag", 0.4))
	_rolling = float(config.get("rolling_resistance", 0.015))
	_upright_k = float(config.get("upright_stiffness", 0.0))
	_upright_c = float(config.get("upright_damping", 0.0))
	_lean_gain = float(config.get("lean_gain", 0.0))
	var tire_default: Dictionary = config.get("tire", {})
	_wheels.clear()
	var wl: Array = config.get("wheels", [])
	for item in wl:
		var wd: Dictionary = item
		var w := WheelState.new()
		var wp: Vector3 = wd.get("position", Vector3.ZERO)
		w.position = wp
		w.radius = float(wd.get("radius", 0.35))
		w.rest = float(wd.get("rest", 0.3))
		w.stiffness = float(wd.get("stiffness", 30000.0))
		w.damping = float(wd.get("damping", 2500.0))
		w.max_travel = float(wd.get("max_travel", 0.2))
		w.steer = float(wd.get("steer", 0.0))
		w.drive = float(wd.get("drive", 0.0))
		w.brake = float(wd.get("brake", 0.0))
		w.handbrake = float(wd.get("handbrake", 0.0))
		w.inertia = float(wd.get("inertia", 2.0))
		w.tire = tire_default.duplicate()
		var own: Dictionary = wd.get("tire", {})
		w.tire.merge(own, true)
		_wheels.append(w)
	# Pair mirrored wheels on an axle for the anti-roll bar.
	for i in _wheels.size():
		for j in range(i + 1, _wheels.size()):
			var a: WheelState = _wheels[i]
			var b: WheelState = _wheels[j]
			if a.pair == -1 and b.pair == -1 and absf(a.position.z - b.position.z) < 0.05 \
					and a.position.x * b.position.x < 0.0:
				a.pair = j
				b.pair = i
	gear = 1
	_shift_timer = 0.0
	_cooldown = 0.0
	_reverse_timer = 0.0
	engine_rpm = _idle_rpm
	_coupled_rpm = 0.0


## Places the vehicle at `pos` with zero motion and parked wheels.
func reset(pos: Vector3, bas: Basis = Basis.IDENTITY) -> void:
	position = pos
	basis = bas
	velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	gear = 1
	engine_rpm = _idle_rpm
	_shift_timer = 0.0
	_cooldown = 0.0
	_reverse_timer = 0.0
	for w in _wheels:
		w.omega = 0.0
		w.compression = 0.0
		w.prev_compression = 0.0
		w.grounded = false


## Approximate body-origin height above flat ground at static equilibrium.
func static_ride_height() -> float:
	if _wheels.is_empty():
		return 0.0
	var sum_k: float = 0.0
	for w in _wheels:
		sum_k += w.stiffness
	var comp: float = mass * GRAVITY / sum_k
	var acc: float = 0.0
	for w in _wheels:
		acc += -w.position.y + w.radius + w.rest - comp
	return acc / float(_wheels.size())


func wheel_count() -> int:
	return _wheels.size()


func torque_at(rpm: float) -> float:
	var n: int = _curve.size()
	if n == 0:
		return 0.0
	if rpm <= _curve[0].x:
		return _curve[0].y
	for i in range(1, n):
		if rpm <= _curve[i].x:
			var a: Vector2 = _curve[i - 1]
			var b: Vector2 = _curve[i]
			var span: float = maxf(b.x - a.x, 0.0001)
			return lerpf(a.y, b.y, (rpm - a.x) / span)
	return _curve[n - 1].y


func step(dt: float, inputs: Dictionary, ground: Callable) -> void:
	if dt <= 0.0 or _wheels.is_empty():
		return
	var thr: float = clampf(float(inputs.get("throttle", 0.0)), 0.0, 1.0)
	var brk: float = clampf(float(inputs.get("brake", 0.0)), 0.0, 1.0)
	var st: float = clampf(float(inputs.get("steer", 0.0)), -1.0, 1.0)
	var hb: float = clampf(float(inputs.get("handbrake", 0.0)), 0.0, 1.0)
	var cl: float = clampf(float(inputs.get("clutch", 0.0)), 0.0, 1.0)
	_last_steer = st
	_last_throttle = thr
	_last_brake = brk
	var n: int = maxi(1, ceili(dt / max_substep))
	var h: float = dt / float(n)
	for i in n:
		_substep(h, thr, brk, st, hb, cl, ground)


func _total_ratio() -> float:
	if gear >= 1 and gear <= _gear_ratios.size():
		return _gear_ratios[gear - 1] * _final_drive
	if gear == -1:
		return -_reverse_ratio * _final_drive
	return 0.0


func _update_gearbox(h: float, thr: float, brk: float) -> void:
	_shift_timer = maxf(0.0, _shift_timer - h)
	_cooldown -= h
	if gear == -1:
		if thr > 0.1 and _speed_fwd > -0.5:
			gear = 1
			_cooldown = _shift_time
		return
	if brk > 0.1 and thr < 0.05 and _speed_fwd < 0.3:
		_reverse_timer += h
		if _reverse_timer > 0.6:
			gear = -1
			_reverse_timer = 0.0
			return
	else:
		_reverse_timer = 0.0
	if gear < 1 or _cooldown > 0.0:
		return
	var top: int = _gear_ratios.size()
	if engine_rpm > _shift_up_rpm and gear < top:
		gear += 1
		_shift_timer = _shift_time
		_cooldown = _shift_time + 0.3
	elif _coupled_rpm < _shift_down_rpm and gear > 1:
		var predicted: float = _coupled_rpm * _gear_ratios[gear - 2] / maxf(_gear_ratios[gear - 1], 0.0001)
		if predicted < _redline_rpm * 0.95:
			gear -= 1
			_shift_timer = _shift_time * 0.5
			_cooldown = _shift_time + 0.3


func _substep(h: float, thr: float, brk: float, st: float, hb: float, cl: float, ground: Callable) -> void:
	_speed_fwd = velocity.dot(-basis.z)
	_update_gearbox(h, thr, brk)
	var up: Vector3 = basis.y
	var down: Vector3 = -up
	var force: Vector3 = Vector3(0.0, -GRAVITY * mass, 0.0)
	var torque: Vector3 = Vector3.ZERO
	var count: int = _wheels.size()

	# Pass 1: raycast suspension.
	var origins: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var frictions: PackedFloat32Array = PackedFloat32Array()
	for w in _wheels:
		var origin: Vector3 = position + basis * w.position
		origins.append(origin)
		var res: Dictionary = ground.call(origin, down, w.rest + w.radius)
		var hit: bool = bool(res.get("hit", false))
		var nrm: Vector3 = res.get("normal", Vector3.UP)
		normals.append(nrm)
		frictions.append(float(res.get("friction", 1.0)))
		w.prev_compression = w.compression if w.grounded else -1.0
		if hit:
			var dist: float = float(res.get("distance", w.rest + w.radius))
			w.compression = maxf(0.0, w.rest - (dist - w.radius))
			if w.prev_compression < 0.0:
				w.prev_compression = w.compression
			w.grounded = true
			w.contact = origin + down * dist
		else:
			w.grounded = false
			w.compression = 0.0
			w.load = 0.0

	# Pass 2: spring, damper, bump stop, anti-roll.
	var loads: PackedFloat32Array = PackedFloat32Array()
	for i in count:
		var w: WheelState = _wheels[i]
		var f: float = 0.0
		if w.grounded:
			var comp_v: float = (w.compression - w.prev_compression) / h
			var c: float = minf(w.compression, w.max_travel)
			f = w.stiffness * c + w.damping * comp_v
			f += w.stiffness * 8.0 * maxf(0.0, w.compression - w.max_travel)
			if w.pair >= 0 and _anti_roll > 0.0:
				var other: WheelState = _wheels[w.pair]
				if other.grounded:
					f += _anti_roll * (w.compression - other.compression)
			f = maxf(f, 0.0)
		loads.append(f)

	# Drivetrain.
	var ratio: float = _total_ratio()
	var drive_sum: float = 0.0
	var omega_mean: float = 0.0
	for w in _wheels:
		drive_sum += w.drive
		omega_mean += w.omega * w.drive
	if drive_sum > 0.0:
		omega_mean /= drive_sum
	var sign_r: float = signf(ratio)
	_coupled_rpm = maxf(0.0, omega_mean * sign_r) * RAD_S_TO_RPM * absf(ratio)
	var thr_eff: float = brk if gear == -1 else thr
	var engaged: bool = ratio != 0.0 and _shift_timer <= 0.0
	var wheel_torque: float = 0.0
	if engaged:
		var floor_rpm: float = _idle_rpm + thr_eff * 0.35 * (_redline_rpm - _idle_rpm)
		engine_rpm = maxf(_coupled_rpm, floor_rpm)
		var tq: float = 0.0
		if engine_rpm < _redline_rpm:
			tq = torque_at(engine_rpm) * thr_eff
		if _coupled_rpm > _idle_rpm:
			tq -= _engine_brake * (engine_rpm / _redline_rpm) * (1.0 - thr_eff)
		wheel_torque = tq * ratio * DRIVE_EFFICIENCY * (1.0 - cl)
	else:
		var target: float = _idle_rpm + thr_eff * (_redline_rpm - _idle_rpm) * 0.8
		engine_rpm += (target - engine_rpm) * minf(1.0, h * 8.0)

	# Pass 3: tires, wheel spin, force accumulation.
	for i in count:
		var w: WheelState = _wheels[i]
		var fz: float = loads[i]
		w.load = fz
		var drive_t: float = 0.0
		if drive_sum > 0.0 and w.drive > 0.0:
			drive_t = wheel_torque * w.drive / drive_sum
			if _diff != "open":
				var diff_w: float = omega_mean - w.omega
				var couple: float = _lsd_stiffness * diff_w
				var cap: float = 1.0e9
				if _diff == "limited_slip":
					cap = _lsd_preload + 0.5 * absf(drive_t)
				else:
					couple = 4000.0 * diff_w
				couple = clampf(couple, -cap, cap)
				var stable: float = 0.5 * w.inertia * absf(diff_w) / h
				drive_t += clampf(couple, -stable, stable)
		var brake_t: float = brk * w.brake + hb * w.handbrake
		if gear == -1:
			# In reverse the throttle pedal acts as the brake.
			brake_t = thr * w.brake + hb * w.handbrake
		var fx_car: float = 0.0
		var d_fx_d_omega: float = 0.0
		w.force_x = 0.0
		w.force_y = 0.0
		w.slip_ratio = 0.0
		w.slip_angle = 0.0
		var f_plane: Vector3 = Vector3.ZERO
		var steer_ang: float = st * w.steer
		w.steer_angle = steer_ang
		if w.grounded and fz > 0.0:
			var nrm: Vector3 = normals[i]
			var fwd: Vector3 = (Basis(up, steer_ang) * (-basis.z)).slide(nrm).normalized()
			var right: Vector3 = fwd.cross(nrm).normalized()
			var cp: Vector3 = w.contact
			var vel: Vector3 = velocity + angular_velocity.cross(cp - position)
			var v_long: float = vel.dot(fwd)
			var v_lat: float = vel.dot(right)
			var den: float = maxf(absf(v_long), 1.5)
			var kappa: float = (w.omega * w.radius - v_long) / den
			var alpha: float = atan2(v_lat, maxf(absf(v_long), 1.0))
			w.slip_ratio = kappa
			w.slip_angle = alpha
			var tf: Vector2 = tire_force(kappa, alpha, fz, w.tire, frictions[i])
			var m_eff: float = mass / float(count)
			fx_car = tf.x
			var fy_car: float = -tf.y
			# Never let a tire force reverse the contact velocity within one step.
			if fx_car * v_long < 0.0:
				fx_car = signf(fx_car) * minf(absf(fx_car), m_eff * absf(v_long) / h)
			if fy_car * v_lat < 0.0:
				fy_car = signf(fy_car) * minf(absf(fy_car), m_eff * absf(v_lat) / h)
			fx_car -= _rolling * fz * tanh(v_long * 2.0)
			w.force_x = fx_car
			w.force_y = fy_car
			f_plane = fwd * fx_car + right * fy_car
			var dk: float = 0.01
			var tf2: Vector2 = tire_force(kappa + dk, alpha, fz, w.tire, frictions[i])
			d_fx_d_omega = (tf2.x - tf.x) / dk * w.radius / den
		var f_susp: Vector3 = up * fz
		var f_wheel: Vector3 = f_plane + f_susp
		force += f_wheel
		if w.grounded:
			torque += (w.contact - position).cross(f_wheel)
		# Wheel spin: implicit in the tire term for stability, then brakes clamp at zero.
		var net: float = drive_t - fx_car * w.radius
		var denom: float = 1.0 + h * w.radius * maxf(d_fx_d_omega, 0.0) / w.inertia
		var omega_new: float = w.omega + h * net / w.inertia / denom
		var b: float = brake_t * h / w.inertia
		if absf(omega_new) <= b:
			omega_new = 0.0
		else:
			omega_new -= signf(omega_new) * b
		w.omega = omega_new

	# Aerodynamic drag.
	var speed: float = velocity.length()
	force -= velocity * (_drag * speed)

	# Two-wheeler self-balance torque about the forward axis.
	if _upright_k > 0.0:
		var fwd_b: Vector3 = -basis.z
		var right_flat: Vector3 = fwd_b.cross(Vector3.UP)
		if right_flat.length_squared() > 0.0001:
			right_flat = right_flat.normalized()
			var lean: float = _lean_gain * st * clampf(speed / 12.0, 0.0, 1.0)
			var target: Vector3 = (Vector3.UP * cos(lean) - right_flat * sin(lean)).normalized()
			var err: Vector3 = up.cross(target)
			torque += fwd_b * (fwd_b.dot(err) * _upright_k - angular_velocity.dot(fwd_b) * _upright_c)

	# Integrate the rigid body (semi-implicit Euler).
	velocity += force / mass * h
	var inv_i: Vector3 = Vector3(1.0 / inertia.x, 1.0 / inertia.y, 1.0 / inertia.z)
	var inv_world: Basis = basis * Basis.from_scale(inv_i) * basis.transposed()
	angular_velocity += inv_world * torque * h
	position += velocity * h
	var wl: float = angular_velocity.length()
	if wl > 0.000001:
		basis = (Basis(angular_velocity / wl, wl * h) * basis).orthonormalized()


## UI telemetry snapshot.
func telemetry() -> Dictionary:
	var ws: Array = []
	for w in _wheels:
		ws.append({
			"slip_ratio": w.slip_ratio,
			"slip_angle": w.slip_angle,
			"compression": w.compression,
			"load": w.load,
			"grounded": w.grounded,
			"omega": w.omega,
			"force_x": w.force_x,
			"force_y": w.force_y,
			"steer_angle": w.steer_angle,
		})
	var spd: float = velocity.dot(-basis.z)
	return {
		"speed": spd,
		"speed_kmh": spd * 3.6,
		"rpm": engine_rpm,
		"gear": gear,
		"throttle": _last_throttle,
		"brake": _last_brake,
		"steer": _last_steer,
		"shifting": _shift_timer > 0.0,
		"yaw_rate": angular_velocity.y,
		"wheels": ws,
	}
