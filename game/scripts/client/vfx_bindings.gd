extends RefCounted
## Data registry that maps gameplay event types ("hit", "lightning_struck", ...) to VFX
## presets / graph assets, with parameter mapping from the event payload, plus VFX sequence
## assets (timed lists of effects). Spawning is delegated to a Callable so this stays
## engine-light: spawn.call(effect: String, position: Vector3, params: Dictionary) -> Variant.
## Original design; no third-party code.

## Plays a timed list of {t, effect, offset, params}. advance(dt) fires entries whose time passed.
class VfxSequence extends RefCounted:
	var entries: Array = []
	var origin: Vector3 = Vector3.ZERO
	var base_params: Dictionary = {}
	var spawn: Callable
	var time: float = 0.0
	var duration: float = 0.0
	var fired: int = 0
	var _cursor: int = 0

	func _init(p_entries: Array = [], p_spawn: Callable = Callable(), p_origin: Vector3 = Vector3.ZERO, p_params: Dictionary = {}) -> void:
		entries = p_entries.duplicate(true)
		entries.sort_custom(func(a, b) -> bool: return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))
		spawn = p_spawn
		origin = p_origin
		base_params = p_params
		for e in entries:
			duration = maxf(duration, float((e as Dictionary).get("t", 0.0)))

	func advance(dt: float) -> int:
		time += maxf(dt, 0.0)
		var count := 0
		while _cursor < entries.size() and float((entries[_cursor] as Dictionary).get("t", 0.0)) <= time:
			var e: Dictionary = entries[_cursor]
			_cursor += 1
			var params: Dictionary = base_params.duplicate()
			params.merge(e.get("params", {}) as Dictionary, true)
			var offset: Vector3 = e.get("offset", Vector3.ZERO)
			if spawn.is_valid():
				spawn.call(str(e.get("effect", "")), origin + offset, params)
			fired += 1
			count += 1
		return count

	func is_finished() -> bool:
		return _cursor >= entries.size()


var _bindings: Dictionary = {}   ## event type -> Array of binding specs
var _sequences: Dictionary = {}  ## name -> Array of entries
var _active: Array = []          ## running VfxSequence
var _last_fire: Dictionary = {}  ## event type -> time
var clock: float = 0.0


## spec keys: effect (String), offset (Vector3), params {name: const | {from, scale, offset,
## default, min, max}}, min_interval (s), sequence (name of a registered sequence).
func register(event_type: String, spec: Dictionary) -> void:
	if not _bindings.has(event_type):
		_bindings[event_type] = []
	(_bindings[event_type] as Array).append(spec)


func register_sequence(sequence_name: String, entries: Array) -> void:
	_sequences[sequence_name] = entries


func has_binding(event_type: String) -> bool:
	return _bindings.has(event_type)


func binding_count() -> int:
	var n := 0
	for k in _bindings:
		n += (_bindings[k] as Array).size()
	return n


func make_sequence(sequence_name: String, spawn: Callable, origin: Vector3 = Vector3.ZERO, params: Dictionary = {}) -> VfxSequence:
	if not _sequences.has(sequence_name):
		return null
	return VfxSequence.new(_sequences[sequence_name] as Array, spawn, origin, params)


static func map_params(mapping: Dictionary, payload: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in mapping:
		var m: Variant = mapping[key]
		if m is Dictionary:
			var md: Dictionary = m
			if not md.has("from"):
				out[key] = md.get("value", md.get("default", 0.0))
				continue
			var src: String = md["from"]
			var raw: Variant = payload.get(src, md.get("default", 0.0))
			if raw is float or raw is int:
				var v: float = float(raw) * float(md.get("scale", 1.0)) + float(md.get("offset", 0.0))
				if md.has("min"):
					v = maxf(v, float(md["min"]))
				if md.has("max"):
					v = minf(v, float(md["max"]))
				out[key] = v
			else:
				out[key] = raw
		else:
			out[key] = m
	return out


## Dispatches an event; returns how many effects/sequences were started.
func handle(event: Dictionary, spawn: Callable) -> int:
	var etype: String = str(event.get("type", ""))
	if not _bindings.has(etype):
		return 0
	var payload: Dictionary = event.get("payload", event) as Dictionary
	var pos: Vector3 = event.get("position", payload.get("position", Vector3.ZERO))
	var started := 0
	for spec_v in _bindings[etype] as Array:
		var spec: Dictionary = spec_v
		var min_interval := float(spec.get("min_interval", 0.0))
		var key := etype + "/" + str(spec.get("effect", spec.get("sequence", "")))
		if min_interval > 0.0 and _last_fire.has(key) and clock - float(_last_fire[key]) < min_interval:
			continue
		_last_fire[key] = clock
		var params := map_params(spec.get("params", {}) as Dictionary, payload)
		var offset: Vector3 = spec.get("offset", Vector3.ZERO)
		if spec.has("sequence"):
			var seq := make_sequence(str(spec["sequence"]), spawn, pos + offset, params)
			if seq != null:
				seq.advance(0.0)
				_active.append(seq)
				started += 1
		if spec.has("effect") and spawn.is_valid():
			spawn.call(str(spec["effect"]), pos + offset, params)
			started += 1
	return started


## Advances the clock and all sequences started by handle().
func tick(dt: float) -> void:
	clock += dt
	for seq in _active:
		(seq as VfxSequence).advance(dt)
	_active = _active.filter(func(s) -> bool: return not (s as VfxSequence).is_finished())


func active_sequences() -> int:
	return _active.size()
