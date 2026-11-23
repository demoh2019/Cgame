extends RefCounted
## Bus layout and persisted volume sliders (Unity AudioMixer groups / Unreal Sound Classes).
## Buses: Master, Music, SFX (reverb + low-pass, see reverb_zones.gd), UI, Ambience.

const PATH := "user://albion_after_audio.cfg"
static var path := PATH # Tests may redirect persistence without editing player settings.
const BUSES := ["Music", "UI", "Ambience"] # SFX is created by ReverbZones.
const SLIDERS := ["Master", "Music", "SFX", "UI", "Ambience"]
static var volumes := {"Master": 1.0, "Music": 1.0, "SFX": 1.0, "UI": 1.0, "Ambience": 1.0}


static func linear_to_db(v: float) -> float:
	return -80.0 if v <= 0.0001 else 20.0 * log(v) / log(10.0)


static func ensure_buses() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")


## Adds a low-pass filter as the last effect of `bus` once; returns its effect index (or -1).
static func ensure_lowpass(bus: String) -> int:
	var i := AudioServer.get_bus_index(bus)
	if i == -1:
		return -1
	for e in AudioServer.get_bus_effect_count(i):
		if AudioServer.get_bus_effect(i, e) is AudioEffectLowPassFilter:
			return e
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 20500.0
	AudioServer.add_bus_effect(i, lp)
	return AudioServer.get_bus_effect_count(i) - 1


static func set_volume(bus: String, linear: float, persist: bool = true) -> void:
	if not SLIDERS.has(bus):
		return
	linear = clampf(linear if is_finite(linear) else 1.0, 0.0, 1.0)
	volumes[bus] = linear
	var i := AudioServer.get_bus_index(bus)
	if i != -1:
		AudioServer.set_bus_volume_db(i, linear_to_db(linear))
	if persist:
		save()


static func save() -> void:
	var config := ConfigFile.new()
	config.load(path) # Preserve other audio preferences in the same file.
	for bus in SLIDERS:
		config.set_value("volume", bus, volumes[bus])
	var error: int = config.save(path)
	if error != OK:
		push_warning("Could not save audio settings: %d" % error)


static func load_all() -> void:
	var config := ConfigFile.new()
	# A missing or deleted config must restore the live buses to unity;
	# retaining an older session's static volumes would be surprising.
	var loaded: bool = config.load(path) == OK
	for bus in SLIDERS:
		var stored: Variant = config.get_value("volume", bus, 1.0) if loaded else 1.0
		var normalized: float = float(stored) if stored is float or stored is int else 1.0
		set_volume(bus, normalized, false)


## Reset every sound bus and persist once, instead of rewriting per slider.
static func reset_volumes(persist: bool = true) -> void:
	for bus in SLIDERS:
		set_volume(bus, 1.0, false)
	if persist:
		save()


## Moves the slider by `step` (0..1), snapped to 5 %; returns the new value.
static func nudge(bus: String, step: float) -> float:
	set_volume(bus, snappedf(float(volumes.get(bus, 1.0)) + step, 0.05))
	return float(volumes[bus])
