extends RefCounted
## Facade over the native `cgame_audio` module (modules/cgame_audio).
##
## Every entry point prefers the native C++ class when the engine was built with the module
## and otherwise falls back to the GDScript reference implementation of the Cgame game
## project (res://scripts/client/*.gd), so game code can call this facade unconditionally.
## GDScript fallbacks are loaded lazily; a missing script only matters when it is needed.

const NATIVE_REVERB := "AudioEffectConvolutionReverb"
const NATIVE_REFLECTIONS := "CgameEarlyReflections"
const NATIVE_PROCEDURAL := "AudioStreamProcedural"

const FALLBACK_REFLECTIONS := "res://scripts/client/early_reflections.gd"
const FALLBACK_GRAPH := "res://scripts/client/audio_graph.gd"
const FALLBACK_CONVOLVER := "res://scripts/client/partitioned_convolver.gd"

static var _fallback_cache: Dictionary = {}


## Which native audio classes this engine build provides.
static func native_status() -> Dictionary:
	return {
		"convolution_reverb": ClassDB.class_exists(NATIVE_REVERB),
		"early_reflections": ClassDB.class_exists(NATIVE_REFLECTIONS),
		"procedural_stream": ClassDB.class_exists(NATIVE_PROCEDURAL),
	}


static func has_native_reverb() -> bool:
	return ClassDB.class_exists(NATIVE_REVERB)


static func has_native_procedural() -> bool:
	return ClassDB.class_exists(NATIVE_PROCEDURAL)


## Real-time convolution reverb effect for an AudioServer bus, or null when the native
## module is unavailable (the GDScript convolver is block-pull based and cannot be an
## AudioEffect; use partitioned_convolver.gd directly in that case).
## `block_size` is the wet-signal latency in frames (power of two).
static func make_convolution_reverb(impulse: PackedFloat32Array, block_size: int = 256, wet: float = 0.5, dry: float = 1.0, impulse_sample_rate: float = 0.0) -> AudioEffect:
	if not ClassDB.class_exists(NATIVE_REVERB):
		push_warning("cgame_audio facade: native AudioEffectConvolutionReverb not available; no AudioEffect fallback.")
		return null
	var fx: AudioEffect = ClassDB.instantiate(NATIVE_REVERB)
	fx.set("block_size", block_size)
	fx.set("wet", wet)
	fx.set("dry", dry)
	fx.set("impulse_sample_rate", impulse_sample_rate)
	fx.set("impulse", impulse)
	return fx


## Convolution reverb from a 16-bit PCM AudioStreamWAV impulse response (native only).
static func make_convolution_reverb_from_wav(wav: AudioStreamWAV, block_size: int = 256, wet: float = 0.5, dry: float = 1.0) -> AudioEffect:
	if not ClassDB.class_exists(NATIVE_REVERB):
		push_warning("cgame_audio facade: native AudioEffectConvolutionReverb not available.")
		return null
	var fx: AudioEffect = ClassDB.instantiate(NATIVE_REVERB)
	fx.set("block_size", block_size)
	fx.set("wet", wet)
	fx.set("dry", dry)
	fx.set("impulse_stream", wav)
	return fx


## Image-source early reflections of a shoebox room; same result format as
## early_reflections.gd: Array of {delay_s, gain, direction, order, distance}.
static func image_sources_box(room_size: Vector3, source: Vector3, listener: Vector3, order: int, absorption: float, speed: float = 343.0) -> Array:
	if ClassDB.class_exists(NATIVE_REFLECTIONS):
		var native: Object = ClassDB.instantiate(NATIVE_REFLECTIONS)
		return native.image_sources_box(room_size, source, listener, order, absorption, speed)
	var script: Object = _fallback(FALLBACK_REFLECTIONS)
	if script == null:
		return []
	return script.image_sources_box(room_size, source, listener, order, absorption, speed)


## Mono impulse response from a reflection list plus a synthetic diffuse tail.
static func to_ir(reflections: Array, sample_rate: int, length_s: float, rt60: Vector3 = Vector3(0.7, 0.6, 0.4), late_start_s: float = 0.04, late_gain: float = 0.25, seed_value: int = 1) -> PackedFloat32Array:
	if ClassDB.class_exists(NATIVE_REFLECTIONS):
		var native: Object = ClassDB.instantiate(NATIVE_REFLECTIONS)
		return native.to_ir(reflections, sample_rate, length_s, rt60, late_start_s, late_gain, seed_value)
	var script: Object = _fallback(FALLBACK_REFLECTIONS)
	if script == null:
		return PackedFloat32Array()
	return script.to_ir(reflections, sample_rate, length_s, rt60, late_start_s, late_gain, seed_value)


## Convenience: shoebox room -> ready-to-use IR for make_convolution_reverb().
static func room_impulse(room_size: Vector3, source: Vector3, listener: Vector3, sample_rate: int = 48000, length_s: float = 1.0, order: int = 3, absorption: float = 0.3, rt60: Vector3 = Vector3(0.7, 0.6, 0.4), seed_value: int = 1) -> PackedFloat32Array:
	var reflections: Array = image_sources_box(room_size, source, listener, order, absorption)
	return to_ir(reflections, sample_rate, length_s, rt60, 0.04, 0.25, seed_value)


## Playable stream for an audio graph asset (same dictionary format as audio_graph.gd).
## Native: AudioStreamProcedural evaluated live in the audio thread. Fallback: the graph is
## rendered once with audio_graph.gd and wrapped in an AudioStreamWAV (`length` seconds,
## defaulting to the graph's optional "duration" key or 1 second).
static func make_procedural_stream(graph: Dictionary, seed_value: int = 0, mix_rate: int = 22050, length: float = 0.0) -> AudioStream:
	if ClassDB.class_exists(NATIVE_PROCEDURAL):
		var stream: AudioStream = ClassDB.instantiate(NATIVE_PROCEDURAL)
		stream.set("graph", graph)
		stream.set("seed", seed_value)
		stream.set("mix_rate", float(mix_rate))
		stream.set("length", length)
		return stream
	var script: Object = _fallback(FALLBACK_GRAPH)
	if script == null:
		return null
	var seconds: float = length if length > 0.0 else float(graph.get("duration", 1.0))
	var samples: PackedFloat32Array = script.render(graph, seconds, mix_rate, seed_value)
	if samples.is_empty():
		return null
	return script.to_wav(samples, mix_rate)


## Offline render of a graph to mono float samples, native when available.
static func render_graph(graph: Dictionary, seconds: float, sample_rate: int = 22050, seed_value: int = 0) -> PackedFloat32Array:
	if ClassDB.class_exists(NATIVE_PROCEDURAL):
		var stream: AudioStream = ClassDB.instantiate(NATIVE_PROCEDURAL)
		stream.set("graph", graph)
		stream.set("seed", seed_value)
		stream.set("mix_rate", float(sample_rate))
		return stream.call("render", seconds, float(sample_rate))
	var script: Object = _fallback(FALLBACK_GRAPH)
	if script == null:
		return PackedFloat32Array()
	return script.render(graph, seconds, sample_rate, seed_value)


## Human readable graph problems (empty = valid). Uses the native validator when present.
static func validate_graph(graph: Dictionary) -> PackedStringArray:
	if ClassDB.class_exists(NATIVE_PROCEDURAL):
		var stream: AudioStream = ClassDB.instantiate(NATIVE_PROCEDURAL)
		stream.set("graph", graph)
		return stream.call("validate")
	var script: Object = _fallback(FALLBACK_GRAPH)
	if script == null:
		return PackedStringArray(["audio graph implementation unavailable"])
	return PackedStringArray(script.validate(graph))


static func _fallback(path: String) -> Object:
	if _fallback_cache.has(path):
		return _fallback_cache[path]
	var loaded: Object = null
	if ResourceLoader.exists(path):
		loaded = load(path)
	if loaded == null:
		push_warning("cgame_audio facade: fallback script missing: %s" % path)
	_fallback_cache[path] = loaded
	return loaded
