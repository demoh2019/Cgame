extends RefCounted
## Thermal / battery governor for phones and laptops. Feed it frame times (and optionally battery
## readings); it outputs an FPS cap and how many quality levels to step down, with hysteresis:
## stepping down needs sustained slow frames, stepping back up needs a longer run of headroom.
## Godot 4 has no battery API (OS.get_power_state was removed), so battery percent is an input;
## read_system_battery() probes for a platform method and reports unavailable otherwise.
## Original code (MIT-compatible).

const EVAL_INTERVAL_S: float = 1.0
const WINDOW_FRAMES: int = 180
const SLOW_RATIO: float = 1.15
const FAST_RATIO: float = 0.70
const STEP_DOWN_AFTER_S: float = 3.0
const STEP_UP_AFTER_S: float = 12.0
const MAX_STEPS: int = 3
const LOW_BATTERY_PCT: float = 20.0

var target_fps: int = 60
var step: int = 0
var _frames: PackedFloat32Array = PackedFloat32Array()
var _last_eval_s: float = -1.0
var _slow_s: float = 0.0
var _fast_s: float = 0.0
var _battery_samples: Array[Vector2] = []  # (time_s, percent) while discharging
var _on_battery: bool = false
var _battery_pct: float = -1.0


func configure(p_target_fps: int) -> void:
	target_fps = maxi(p_target_fps, 1)


## Optional platform probe; returns {available, percent, charging}.
static func read_system_battery() -> Dictionary:
	if OS.has_method("get_power_percent_left") and OS.has_method("get_power_state"):
		var pct: int = int(OS.call("get_power_percent_left"))
		return {"available": pct >= 0, "percent": float(pct), "charging": false}
	return {"available": false, "percent": -1.0, "charging": false}


func budget_ms() -> float:
	return 1000.0 / float(target_fps)


## Call once per frame. Returns true when the step changed on this call.
func sample_frame(frame_ms: float, now_s: float) -> bool:
	_frames.append(frame_ms)
	if _frames.size() > WINDOW_FRAMES:
		_frames = _frames.slice(_frames.size() - WINDOW_FRAMES)
	if _last_eval_s < 0.0:
		_last_eval_s = now_s
		return false
	var elapsed: float = now_s - _last_eval_s
	if elapsed < EVAL_INTERVAL_S:
		return false
	_last_eval_s = now_s
	return _evaluate(elapsed)


func _evaluate(elapsed: float) -> bool:
	var avg: float = _mean(_frames, 0, _frames.size())
	var half: int = _frames.size() / 2
	var rising: bool = false
	if half >= 8:
		var first: float = _mean(_frames, 0, half)
		var second: float = _mean(_frames, half, _frames.size())
		rising = second > first * 1.2
	var budget: float = budget_ms()
	var slow_limit: float = budget * (SLOW_RATIO - (0.08 if rising else 0.0))
	var before: int = step
	if avg > slow_limit:
		_slow_s += elapsed
		_fast_s = 0.0
		if _slow_s >= STEP_DOWN_AFTER_S and step < MAX_STEPS:
			step += 1
			_slow_s = 0.0
	elif avg < budget * FAST_RATIO:
		_fast_s += elapsed
		_slow_s = 0.0
		if _fast_s >= STEP_UP_AFTER_S and step > 0:
			step -= 1
			_fast_s = 0.0
	else:
		# Dead band: neither slow nor clearly fast, hold the current step.
		_slow_s = maxf(_slow_s - elapsed, 0.0)
		_fast_s = maxf(_fast_s - elapsed, 0.0)
	return step != before


## Record a battery reading. Only discharging samples feed the drain estimate.
func record_battery(now_s: float, percent: float, charging: bool) -> void:
	_battery_pct = percent
	_on_battery = not charging
	if charging:
		_battery_samples.clear()
		return
	_battery_samples.append(Vector2(now_s, percent))
	if _battery_samples.size() > 600:
		_battery_samples.remove_at(0)


## Percent per hour from a least-squares fit; -1.0 when there is not enough data.
func drain_per_hour() -> float:
	var n: int = _battery_samples.size()
	if n < 2:
		return -1.0
	var span: float = _battery_samples[n - 1].x - _battery_samples[0].x
	if span < 1.0:
		return -1.0
	var mx: float = 0.0
	var my: float = 0.0
	for p in _battery_samples:
		mx += p.x
		my += p.y
	mx /= float(n)
	my /= float(n)
	var num: float = 0.0
	var den: float = 0.0
	for p in _battery_samples:
		num += (p.x - mx) * (p.y - my)
		den += (p.x - mx) * (p.x - mx)
	if den <= 0.0:
		return -1.0
	return maxf(-num / den * 3600.0, 0.0)


## Estimated hours of battery left, -1.0 when unknown.
func hours_remaining() -> float:
	var drain: float = drain_per_hour()
	if drain <= 0.0 or _battery_pct < 0.0:
		return -1.0
	return _battery_pct / drain


func fps_cap() -> int:
	var cap: int = target_fps
	if step >= MAX_STEPS:
		cap = mini(cap, 30)
	if _on_battery and _battery_pct >= 0.0 and _battery_pct < LOW_BATTERY_PCT:
		cap = mini(cap, 30)
	return cap


func quality_step() -> int:
	return step


## Applies the step-down to a base quality level (0..3).
func apply_to(base_level: int) -> int:
	var lv: int = base_level - step
	if _on_battery and _battery_pct >= 0.0 and _battery_pct < LOW_BATTERY_PCT:
		lv -= 1
	return clampi(lv, 0, 3)


static func _mean(v: PackedFloat32Array, from: int, to: int) -> float:
	if to <= from:
		return 0.0
	var s: float = 0.0
	for i in range(from, to):
		s += v[i]
	return s / float(to - from)
