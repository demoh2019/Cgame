extends RefCounted
## Procedural game sounds built on audio_graph.gd. Each preset returns a graph asset
## (with an extra "duration" key in seconds); bake() renders and caches the AudioStreamWAV.
## All graphs are original designs; DSP primitives are documented in audio_graph.gd.

const AudioGraph = preload("res://scripts/client/audio_graph.gd")

const SAMPLE_RATE := 22050
const CACHE_LIMIT := 24

static var _cache: Dictionary = {}
static var cache_hits: int = 0
static var cache_misses: int = 0


static func footstep(surface: String) -> Dictionary:
	var nodes: Dictionary = {
		"noise": {"type": "noise_white", "amp": 1.0},
		"env": {"type": "ar", "attack": 0.002, "release": 0.07},
		"filt": {"type": "bandpass", "cutoff": 1800.0, "q": 0.7},
		"vca": {"type": "multiply"},
		"out": {"type": "gain", "gain": 0.8},
	}
	var conns: Array = [
		["noise", "filt", "in"], ["filt", "vca", "a"], ["env", "vca", "b"], ["vca", "out", "in"],
	]
	match surface:
		"gravel":
			nodes["noise"]["type"] = "noise_white"
			nodes["env"]["release"] = 0.16
			nodes["filt"]["cutoff"] = 3200.0
			nodes["grain"] = {"type": "random_trigger", "rate": 160.0, "decay": 0.006, "min_amp": 0.4}
			nodes["grit"] = {"type": "multiply"}
			conns = [
				["noise", "filt", "in"], ["filt", "grit", "a"], ["grain", "grit", "b"],
				["grit", "vca", "a"], ["env", "vca", "b"], ["vca", "out", "in"],
			]
			nodes["out"]["gain"] = 2.0
		"grass":
			nodes["noise"]["type"] = "noise_pink"
			nodes["env"]["attack"] = 0.015
			nodes["env"]["release"] = 0.11
			nodes["filt"] = {"type": "lowpass", "cutoff": 1400.0, "q": 0.6}
			nodes["out"]["gain"] = 1.1
		"wood":
			nodes["env"]["release"] = 0.05
			nodes["filt"]["cutoff"] = 700.0
			nodes["filt"]["q"] = 1.2
			nodes["thump"] = {"type": "sine", "freq": 150.0, "amp": 0.9}
			nodes["tenv"] = {"type": "ar", "attack": 0.001, "release": 0.08}
			nodes["tvca"] = {"type": "multiply"}
			nodes["mix"] = {"type": "mixer"}
			conns = [
				["noise", "filt", "in"], ["filt", "vca", "a"], ["env", "vca", "b"],
				["thump", "tvca", "a"], ["tenv", "tvca", "b"],
				["vca", "mix", "in"], ["tvca", "mix", "in"], ["mix", "out", "in"],
			]
			nodes["out"]["gain"] = 1.4
		"metal":
			nodes["env"]["release"] = 0.04
			nodes["filt"]["cutoff"] = 4200.0
			nodes["filt"]["q"] = 2.0
			nodes["ring1"] = {"type": "sine", "freq": 930.0, "amp": 0.4}
			nodes["ring2"] = {"type": "sine", "freq": 1410.0, "amp": 0.3}
			nodes["renv"] = {"type": "ar", "attack": 0.001, "release": 0.2}
			nodes["rsum"] = {"type": "mixer"}
			nodes["rvca"] = {"type": "multiply"}
			nodes["mix"] = {"type": "mixer"}
			conns = [
				["noise", "filt", "in"], ["filt", "vca", "a"], ["env", "vca", "b"],
				["ring1", "rsum", "in"], ["ring2", "rsum", "in"], ["rsum", "rvca", "a"], ["renv", "rvca", "b"],
				["vca", "mix", "in"], ["rvca", "mix", "in"], ["mix", "out", "in"],
			]
		_:
			pass
	return {"nodes": nodes, "connections": conns, "output": "out", "duration": 0.3}


## Low saw voice with vibrato and random pitch wander, formant-ish lowpass sweep, breathy noise.
static func zombie_groan(seed: int = 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var lo := rng.randf_range(65.0, 85.0)
	var hi := lo + rng.randf_range(20.0, 40.0)
	var nodes: Dictionary = {
		"wander": {"type": "random_pitch", "min": lo, "max": hi, "rate": 3.0},
		"glide": {"type": "smooth", "time": 0.18},
		"vib": {"type": "sine", "freq": rng.randf_range(4.0, 6.5), "amp": 4.0},
		"voice": {"type": "saw", "amp": 0.9},
		"sweep": {"type": "adsr", "attack": 0.3, "decay": 0.5, "sustain": 0.4, "gate": 0.9, "release": 0.4},
		"sweep_amt": {"type": "gain", "gain": 900.0},
		"formant": {"type": "lowpass", "cutoff": 350.0, "q": 2.5},
		"breath": {"type": "noise_brown", "amp": 0.8},
		"breath_bp": {"type": "bandpass", "cutoff": 500.0, "q": 1.2},
		"breath_amt": {"type": "gain", "gain": 0.35},
		"mix": {"type": "mixer"},
		"amp_env": {"type": "adsr", "attack": 0.25, "decay": 0.3, "sustain": 0.65, "gate": 0.95, "release": 0.45},
		"vca": {"type": "multiply"},
		"drive": {"type": "clip", "drive": 2.2},
		"out": {"type": "gain", "gain": 0.8},
	}
	var conns: Array = [
		["wander", "glide", "in"], ["glide", "voice", "freq"], ["vib", "voice", "freq_mod"],
		["voice", "formant", "in"], ["sweep", "sweep_amt", "in"], ["sweep_amt", "formant", "cutoff_mod"],
		["breath", "breath_bp", "in"], ["breath_bp", "breath_amt", "in"],
		["formant", "mix", "in"], ["breath_amt", "mix", "in"],
		["mix", "vca", "a"], ["amp_env", "vca", "b"], ["vca", "drive", "in"], ["drive", "out", "in"],
	]
	return {"nodes": nodes, "connections": conns, "output": "out", "duration": 1.6}


## intensity in [0, 1]: louder, brighter and more gusty.
static func wind(intensity: float = 0.5) -> Dictionary:
	var k := clampf(intensity, 0.0, 1.0)
	var nodes: Dictionary = {
		"air": {"type": "noise_pink", "amp": 1.0},
		"gust_lfo": {"type": "sine", "freq": 0.35, "amp": 300.0 + 500.0 * k},
		"band": {"type": "bandpass", "cutoff": 450.0 + 450.0 * k, "q": 1.6},
		"gust_noise": {"type": "noise_brown", "amp": 1.0},
		"gust_smooth": {"type": "smooth", "time": 0.25},
		"gust_amt": {"type": "gain", "gain": 0.6 + 0.8 * k},
		"level": {"type": "const", "value": 0.35 + 0.35 * k},
		"depth": {"type": "mixer"},
		"vca": {"type": "multiply"},
		"out": {"type": "gain", "gain": 1.2},
	}
	var conns: Array = [
		["air", "band", "in"], ["gust_lfo", "band", "cutoff_mod"],
		["gust_noise", "gust_smooth", "in"], ["gust_smooth", "gust_amt", "in"],
		["level", "depth", "in"], ["gust_amt", "depth", "in"],
		["band", "vca", "a"], ["depth", "vca", "b"], ["vca", "out", "in"],
	]
	return {"nodes": nodes, "connections": conns, "output": "out", "duration": 2.0}


## Random Poisson snaps and pops on top of a dull low roar.
static func fire_crackle() -> Dictionary:
	var nodes: Dictionary = {
		"snap_noise": {"type": "noise_white", "amp": 1.0},
		"snap_trig": {"type": "random_trigger", "rate": 22.0, "decay": 0.012, "min_amp": 0.3},
		"snap_vca": {"type": "multiply"},
		"snap_hp": {"type": "highpass", "cutoff": 1500.0, "q": 0.8},
		"pop_trig": {"type": "random_trigger", "rate": 6.0, "decay": 0.03, "min_amp": 0.5},
		"pop_osc": {"type": "triangle", "freq": 420.0, "amp": 0.6},
		"pop_vca": {"type": "multiply"},
		"roar": {"type": "noise_brown", "amp": 1.0},
		"roar_lp": {"type": "lowpass", "cutoff": 350.0, "q": 0.7},
		"roar_amt": {"type": "gain", "gain": 0.25},
		"mix": {"type": "mixer"},
		"out": {"type": "gain", "gain": 0.9},
	}
	var conns: Array = [
		["snap_noise", "snap_vca", "a"], ["snap_trig", "snap_vca", "b"], ["snap_vca", "snap_hp", "in"],
		["pop_osc", "pop_vca", "a"], ["pop_trig", "pop_vca", "b"],
		["roar", "roar_lp", "in"], ["roar_lp", "roar_amt", "in"],
		["snap_hp", "mix", "in"], ["pop_vca", "mix", "in"], ["roar_amt", "mix", "in"], ["mix", "out", "in"],
	]
	return {"nodes": nodes, "connections": conns, "output": "out", "duration": 1.2}


## caliber: "9mm" (default), "5.56", "7.62", "12ga". Noise crack through an env-swept
## lowpass, pitch-dropping thump and a short slap-back echo.
static func gunshot(caliber: String = "9mm") -> Dictionary:
	var crack_release := 0.09
	var thump_hz := 110.0
	var thump_len := 0.16
	var cutoff := 2500.0
	var echo := 0.045
	match caliber:
		"5.56":
			crack_release = 0.13
			thump_hz = 90.0
			cutoff = 3800.0
			echo = 0.07
		"7.62":
			crack_release = 0.17
			thump_hz = 75.0
			thump_len = 0.22
			cutoff = 3200.0
			echo = 0.09
		"12ga":
			crack_release = 0.24
			thump_hz = 60.0
			thump_len = 0.3
			cutoff = 2200.0
			echo = 0.06
		_:
			pass
	var nodes: Dictionary = {
		"noise": {"type": "noise_white", "amp": 1.0},
		"env": {"type": "ar", "attack": 0.0008, "release": crack_release},
		"sweep": {"type": "gain", "gain": cutoff},
		"lp": {"type": "lowpass", "cutoff": 500.0, "q": 0.8},
		"crack": {"type": "multiply"},
		"tenv": {"type": "ar", "attack": 0.001, "release": thump_len},
		"drop": {"type": "gain", "gain": thump_hz * 0.6},
		"thump": {"type": "sine", "freq": thump_hz * 0.5, "amp": 1.0},
		"tvca": {"type": "multiply"},
		"mix": {"type": "mixer"},
		"slap": {"type": "delay", "time": echo, "feedback": 0.25},
		"slap_amt": {"type": "gain", "gain": 0.3},
		"sum": {"type": "mixer"},
		"drive": {"type": "clip", "drive": 1.6},
		"out": {"type": "gain", "gain": 0.9},
	}
	var conns: Array = [
		["env", "sweep", "in"], ["sweep", "lp", "cutoff_mod"], ["noise", "lp", "in"],
		["lp", "crack", "a"], ["env", "crack", "b"],
		["tenv", "drop", "in"], ["drop", "thump", "freq_mod"], ["thump", "tvca", "a"], ["tenv", "tvca", "b"],
		["crack", "mix", "in"], ["tvca", "mix", "in"],
		["mix", "slap", "in"], ["slap", "slap_amt", "in"],
		["mix", "sum", "in"], ["slap_amt", "sum", "in"], ["sum", "drive", "in"], ["drive", "out", "in"],
	]
	return {"nodes": nodes, "connections": conns, "output": "out", "duration": 0.5}


static func ui_click() -> Dictionary:
	var nodes: Dictionary = {
		"tone": {"type": "sine", "freq": 1800.0, "amp": 0.7},
		"body": {"type": "triangle", "freq": 900.0, "amp": 0.4},
		"env": {"type": "ar", "attack": 0.001, "release": 0.03},
		"mix": {"type": "mixer"},
		"vca": {"type": "multiply"},
		"out": {"type": "gain", "gain": 0.6},
	}
	var conns: Array = [
		["tone", "mix", "in"], ["body", "mix", "in"], ["mix", "vca", "a"], ["env", "vca", "b"], ["vca", "out", "in"],
	]
	return {"nodes": nodes, "connections": conns, "output": "out", "duration": 0.08}


static func preset_names() -> PackedStringArray:
	return PackedStringArray(["footstep", "zombie_groan", "wind", "fire_crackle", "gunshot", "ui_click"])


static func graph_for(sound: String, args: Array = [], seed: int = 0) -> Dictionary:
	match sound:
		"footstep":
			return footstep(str(args[0]) if args.size() > 0 else "gravel")
		"zombie_groan":
			return zombie_groan(seed)
		"wind":
			return wind(float(args[0]) if args.size() > 0 else 0.5)
		"fire_crackle":
			return fire_crackle()
		"gunshot":
			return gunshot(str(args[0]) if args.size() > 0 else "9mm")
		"ui_click":
			return ui_click()
	return {}


## Renders a preset to a WAV, memoised in a small LRU cache keyed on name + args + seed.
static func bake(sound: String, args: Array = [], seed: int = 0) -> AudioStreamWAV:
	var key := "%s|%s|%d" % [sound, str(args), seed]
	if _cache.has(key):
		var hit: AudioStreamWAV = _cache[key] as AudioStreamWAV
		_cache.erase(key)
		_cache[key] = hit
		cache_hits += 1
		return hit
	cache_misses += 1
	var graph := graph_for(sound, args, seed)
	if graph.is_empty():
		return null
	var seconds := float(graph.get("duration", 1.0))
	var wav := AudioGraph.to_wav(AudioGraph.render(graph, seconds, SAMPLE_RATE, seed), SAMPLE_RATE)
	_cache[key] = wav
	while _cache.size() > CACHE_LIMIT:
		_cache.erase(_cache.keys()[0])
	return wav


static func cache_size() -> int:
	return _cache.size()


static func clear_cache() -> void:
	_cache.clear()
	cache_hits = 0
	cache_misses = 0
