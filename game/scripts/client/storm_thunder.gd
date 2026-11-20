extends Node3D
## World-space, speed-of-sound thunder for authoritative lightning_struck
## events. The flash remains immediate; the sound wave arrives later.
## Unreal-style distance delay + 3D sound emitter, procedural/no asset pack.
const SAMPLE_RATE := 22050
const SAMPLE_SECONDS := 3.0
const MAX_DISTANCE := 2400.0
const MAX_PENDING := 4
const MAX_VOICES := 2
const REFERENCE_TEMPERATURE_C := 20.0

static var _native: Object = null
static var _native_checked: bool = false
static var _cached_wave: AudioStreamWAV = null

var _pending: Array[Dictionary] = []
var _active: Array[AudioStreamPlayer3D] = []


## Audio travels around 343 m/s at 20 C; 343 m => ~1 second delay.
## The native module validates range and temperature. Exactly the same
## bounded fallback works in stock Godot and on dedicated test runners.
static func propagation_delay(distance_m: float, temperature_c: float = 20.0) -> float:
	if not is_finite(distance_m) or not is_finite(temperature_c) \
			or distance_m < 0.0 or distance_m > MAX_DISTANCE \
			or temperature_c < -40.0 or temperature_c > 60.0:
		return -1.0
	if not _native_checked:
		_native_checked = true
		if ClassDB.class_exists("SoundPropagation"):
			_native = ClassDB.instantiate("SoundPropagation")
	if _native != null and _native.has_method("travel_delay_seconds"):
		var native_result: float = float(_native.call(
			"travel_delay_seconds", distance_m, temperature_c))
		if is_finite(native_result) and native_result >= 0.0 and native_result <= 8.0:
			return native_result
	return distance_m / (331.3 + 0.606 * temperature_c)


## A one-time three-second mono pulse: sub-bass turbulence, rolling rumble,
## and a brief noisy crack. It is deterministic, non-looping and reused by
## every thunder voice. No licensed audio asset or real-time DSP allocation.
static func thunder_wave() -> AudioStreamWAV:
	if _cached_wave != null:
		return _cached_wave
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x54A7B022
	var count: int = int(SAMPLE_SECONDS * SAMPLE_RATE)
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	var low := 0.0
	var mid := 0.0
	for i in count:
		var seconds: float = float(i) / SAMPLE_RATE
		var white: float = rng.randf_range(-1.0, 1.0)
		low += (white - low) * 0.036
		mid += (white - mid) * 0.18
		var crack: float = exp(-seconds * 17.0)
		var rolling: float = exp(-seconds * 1.05) * (
			0.74 + 0.15 * sin(seconds * 17.0) + 0.10 * sin(seconds * 39.0))
		var attack: float = clampf(seconds * 140.0, 0.0, 1.0)
		var release: float = clampf((SAMPLE_SECONDS - seconds) * 8.0, 0.0, 1.0)
		var sample: float = (low * 2.4 * rolling +
			mid * 0.58 * (crack + rolling * 0.40) + white * crack * 0.11)
		pcm.encode_s16(i * 2, int(roundf(clampf(
			sample * attack * release, -1.0, 1.0) * 28000.0)))
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = SAMPLE_RATE
	wave.stereo = false
	wave.data = pcm
	wave.loop_mode = AudioStreamWAV.LOOP_DISABLED
	_cached_wave = wave
	return wave


## Only a genuine server-confirmed strike schedules thunder. A warning
## never creates thunder and underground players hear no outdoor bolt.
func on_strike(event: Dictionary, listener: Vector3, height_at: Callable,
		underground: bool) -> bool:
	if underground or not listener.is_finite() \
			or str(event.get("type", "")) != "lightning_struck" \
			or not event.has("x") or not event.has("z") \
			or not height_at.is_valid():
		return false
	var x: float = float(event["x"])
	var z: float = float(event["z"])
	if not is_finite(x) or not is_finite(z):
		return false
	var ground: float = float(height_at.call(x, z))
	if not is_finite(ground):
		return false
	var at := Vector3(x, ground + 1.5, z)
	var distance_m: float = at.distance_to(listener)
	var delay: float = propagation_delay(distance_m)
	if delay < 0.0:
		return false
	# A bounded priority queue: close, soon-to-arrive strikes may replace
	# distant pending thunder, but cannot allocate unbounded audio voices.
	var entry := {"at": at, "remaining": delay, "distance": distance_m}
	if _pending.size() >= MAX_PENDING:
		var furthest := 0
		for i in range(1, _pending.size()):
			if float(_pending[i]["remaining"]) > float(_pending[furthest]["remaining"]):
				furthest = i
		if delay >= float(_pending[furthest]["remaining"]):
			return false
		_pending.remove_at(furthest)
	_pending.append(entry)
	return true


func queued_count() -> int:
	return _pending.size()


func _process(delta: float) -> void:
	if _pending.is_empty() or not is_finite(delta) or delta <= 0.0:
		return
	for i in range(_pending.size() - 1, -1, -1):
		var item: Dictionary = _pending[i]
		var remaining: float = float(item["remaining"]) - delta
		if remaining > 0.0:
			item["remaining"] = remaining
			_pending[i] = item
			continue
		_pending.remove_at(i)
		_play_thunder(item["at"], float(item["distance"]))


func _play_thunder(at: Vector3, distance_m: float) -> void:
	if _active.size() >= MAX_VOICES:
		var oldest: AudioStreamPlayer3D = _active.pop_front()
		if is_instance_valid(oldest):
			oldest.stop()
			oldest.queue_free()
	var player := AudioStreamPlayer3D.new()
	player.stream = thunder_wave()
	player.unit_size = 350.0
	player.max_distance = MAX_DISTANCE
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.attenuation_filter_cutoff_hz = lerpf(
		6000.0, 2200.0, clampf(distance_m / MAX_DISTANCE, 0.0, 1.0))
	player.attenuation_filter_db = -24.0
	player.volume_db = -3.0
	player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(player)
	player.global_position = at
	_active.append(player)
	player.finished.connect(func() -> void:
		_active.erase(player)
		player.queue_free())
	player.play()
