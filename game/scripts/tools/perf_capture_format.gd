extends RefCounted
## Unified performance capture (.cgperf): one file bundling frame timings, trace
## events, counters, memory samples, streaming events, network packets and
## environment info. Stored as var_to_bytes (default) or JSON (path ends in .json
## or json=true); reading sniffs the format.
## Original code (MIT-compatible). Design inspired by the general idea of
## Chrome trace / Unreal Insights bundles; no third-party code copied.

const VERSION: int = 1
const MAGIC: String = "cgperf"
const ARRAY_SECTIONS: Array[String] = [
	"frames", "trace_events", "counters", "memory_samples", "streaming_events", "network_packets",
]


static func new_capture(label: String = "") -> Dictionary:
	var cap: Dictionary = {
		"magic": MAGIC,
		"version": VERSION,
		"label": label,
		"created_unix": Time.get_unix_time_from_system(),
		"environment": capture_environment(),
		"scenario": {},
	}
	for s in ARRAY_SECTIONS:
		cap[s] = []
	return cap


static func capture_environment() -> Dictionary:
	return {
		"engine": Engine.get_version_info().get("string", "unknown"),
		"os": OS.get_name(),
		"processor": OS.get_processor_name(),
		"cores": OS.get_processor_count(),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"rendering_method": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown")),
		"debug_build": OS.is_debug_build(),
	}


## frame: {"index": int, "ms": float, "scopes": {name: usec}, "counters": {name: value}}
static func add_frame(cap: Dictionary, index: int, ms: float, scopes: Dictionary = {}, counters: Dictionary = {}) -> void:
	var frames: Array = cap["frames"]
	frames.append({"index": index, "ms": ms, "scopes": scopes, "counters": counters})


static func add_event(cap: Dictionary, section: String, ev: Dictionary) -> void:
	if not ARRAY_SECTIONS.has(section):
		return
	var arr: Array = cap[section]
	arr.append(ev)


## Returns a list of human-readable problems; empty means valid.
static func validate(cap: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	if str(cap.get("magic", "")) != MAGIC:
		errs.append("bad magic")
	if not cap.has("version") or typeof(cap["version"]) not in [TYPE_INT, TYPE_FLOAT]:
		errs.append("missing version")
	elif int(cap["version"]) > VERSION:
		errs.append("version %d is newer than supported %d" % [int(cap["version"]), VERSION])
	elif int(cap["version"]) < 1:
		errs.append("invalid version")
	for s in ARRAY_SECTIONS:
		if not cap.has(s):
			errs.append("missing section " + s)
		elif typeof(cap[s]) != TYPE_ARRAY:
			errs.append("section %s is not an array" % s)
	if not cap.has("environment") or typeof(cap["environment"]) != TYPE_DICTIONARY:
		errs.append("missing environment")
	if typeof(cap.get("frames")) == TYPE_ARRAY:
		var frames: Array = cap["frames"]
		for i in frames.size():
			var f: Variant = frames[i]
			if typeof(f) != TYPE_DICTIONARY:
				errs.append("frame %d is not a dictionary" % i)
				break
			var fd: Dictionary = f
			if not fd.has("ms") or typeof(fd["ms"]) not in [TYPE_INT, TYPE_FLOAT]:
				errs.append("frame %d has no numeric ms" % i)
				break
			if fd.has("scopes") and typeof(fd["scopes"]) != TYPE_DICTIONARY:
				errs.append("frame %d scopes is not a dictionary" % i)
				break
	return errs


static func write(path: String, cap: Dictionary, as_json: bool = false) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	if as_json or path.ends_with(".json"):
		f.store_string(JSON.stringify(cap))
	else:
		f.store_buffer(var_to_bytes(cap))
	f.close()
	return true


## Returns {} when the file is missing, unreadable or not a capture.
static func read(path: String) -> Dictionary:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return {}
	var parsed: Variant
	if bytes[0] == 0x7B:  # '{'
		parsed = JSON.parse_string(bytes.get_string_from_utf8())
	else:
		parsed = bytes_to_var(bytes)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var cap: Dictionary = parsed
	if str(cap.get("magic", "")) != MAGIC:
		return {}
	return cap


## Merge `extra` into `base` (returns a new capture). Array sections are
## concatenated; frames are re-sorted by index; environment keys of `base` win;
## scenario of `base` wins unless empty.
static func merge(base: Dictionary, extra: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for s in ARRAY_SECTIONS:
		var a: Array = out.get(s, [])
		var b: Array = extra.get(s, [])
		a.append_array(b.duplicate(true))
		out[s] = a
	var frames: Array = out["frames"]
	frames.sort_custom(func(x: Variant, y: Variant) -> bool:
		var xd: Dictionary = x
		var yd: Dictionary = y
		return int(xd.get("index", 0)) < int(yd.get("index", 0)))
	var env: Dictionary = out.get("environment", {})
	var env_extra: Dictionary = extra.get("environment", {})
	for k in env_extra:
		if not env.has(k):
			env[k] = env_extra[k]
	out["environment"] = env
	var sc: Dictionary = out.get("scenario", {})
	if sc.is_empty():
		out["scenario"] = extra.get("scenario", {}).duplicate(true)
	return out


## Per-frame ms values as a float array.
static func frame_times(cap: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var frames: Array = cap.get("frames", [])
	for f in frames:
		var fd: Dictionary = f
		out.append(float(fd.get("ms", 0.0)))
	return out
