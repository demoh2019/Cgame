extends RefCounted
## Portable fallback for Cgame's AudioMixSnapshotController.
## Profile stage dB values are independent of user volume and temporary ducking.
const MAX_MIXES := 16
const MAX_BUSES := 8
const MAX_STAGE_DB := 30.0
const MAX_FADE_SECONDS := 15.0
const MAX_HOLD_SECONDS := 120.0


static func activate_mix(mixes: Dictionary, source: String, offsets: Dictionary,
		fade_seconds: float = 1.0) -> bool:
	if source.is_empty() or source.length() > 128 or offsets.is_empty() \
			or offsets.size() > MAX_BUSES or not is_finite(fade_seconds) \
			or fade_seconds < 0.0 or fade_seconds > MAX_FADE_SECONDS:
		return false
	var parsed: Dictionary = {}
	for key in offsets:
		if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
			return false
		var bus: String = str(key)
		if bus.is_empty() or bus.length() > 128 or parsed.has(bus):
			return false
		var raw = offsets[key]
		if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
			return false
		var db: float = float(raw)
		if not is_finite(db) or db > 0.0 or db < -MAX_STAGE_DB:
			return false
		parsed[bus] = db
	if not mixes.has(source) and mixes.size() >= MAX_MIXES:
		return false
	var weight: float = float(mixes[source]["weight"]) if mixes.has(source) else 0.0
	mixes[source] = {"offsets": parsed, "weight": 1.0 if fade_seconds == 0.0 else weight,
		"target": 1.0, "fade": fade_seconds,
		"remaining": -1.0, "release": 1.0}
	return true


## A repeat re-arms the expiry timer without resetting a partially faded
## weight. Equivalent to Cgame's bounded timed Control Bus Mix.
static func activate_timed_mix(mixes: Dictionary, source: String, offsets: Dictionary,
		attack_seconds: float = 0.2, hold_seconds: float = 3.0,
		release_seconds: float = 1.0) -> bool:
	# Validate the full duration policy before changing any live mix.
	if not is_finite(hold_seconds) or hold_seconds < 0.0 or \
			hold_seconds > MAX_HOLD_SECONDS or not is_finite(release_seconds) or \
			release_seconds < 0.0 or release_seconds > MAX_FADE_SECONDS:
		return false
	if not activate_mix(mixes, source, offsets, attack_seconds):
		return false
	var state: Dictionary = mixes[source]
	state["remaining"] = hold_seconds
	state["release"] = release_seconds
	return true


static func deactivate_mix(mixes: Dictionary, source: String, fade_seconds: float = 1.0) -> bool:
	if not is_finite(fade_seconds) or fade_seconds < 0.0 or fade_seconds > MAX_FADE_SECONDS \
			or not mixes.has(source):
		return false
	if fade_seconds == 0.0:
		mixes.erase(source)
		return true
	var profile: Dictionary = mixes[source]
	profile["target"] = 0.0
	profile["fade"] = fade_seconds
	profile["remaining"] = -1.0
	return true


static func _advance_weight(profile: Dictionary, seconds: float) -> void:
	var target: float = float(profile["target"])
	var weight: float = float(profile["weight"])
	var fade: float = float(profile["fade"])
	if fade == 0.0:
		weight = target
	elif seconds > 0.0:
		if target > weight:
			weight = minf(target, weight + seconds / fade)
		else:
			weight = maxf(target, weight - seconds / fade)
	profile["weight"] = weight


static func tick(mixes: Dictionary, delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	for source in mixes.keys():
		var profile: Dictionary = mixes[source]
		var step_seconds: float = delta
		var remaining: float = float(profile.get("remaining", -1.0))
		if remaining >= 0.0:
			if step_seconds >= remaining:
				_advance_weight(profile, remaining)
				step_seconds -= remaining
				profile["remaining"] = -1.0
				profile["target"] = 0.0
				profile["fade"] = float(profile["release"])
			else:
				profile["remaining"] = remaining - step_seconds
		_advance_weight(profile, step_seconds)
		if float(profile["target"]) == 0.0 and float(profile["weight"]) <= 0.0:
			mixes.erase(source)


static func bus_offset_db(mixes: Dictionary, bus: String) -> float:
	if bus.is_empty() or bus.length() > 128:
		return 0.0
	var sum_db := 0.0
	for profile in mixes.values():
		var offsets: Dictionary = profile["offsets"]
		if offsets.has(bus):
			sum_db += float(offsets[bus]) * float(profile["weight"])
	return maxf(-60.0, sum_db)


static func mix_weight(mixes: Dictionary, source: String) -> float:
	return float(mixes[source]["weight"]) if mixes.has(source) else 0.0


static func mix_remaining_seconds(mixes: Dictionary, source: String) -> float:
	return float(mixes[source].get("remaining", -1.0)) if mixes.has(source) else -1.0
