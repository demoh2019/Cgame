extends RefCounted
## MetaSounds-style procedural audio graph: node-based DSP rendered block-wise into
## sample buffers / AudioStreamWAV.
##
## Graph asset:
##   {"nodes": {id: {"type": ..., param: value, ...}},
##    "connections": [[from_id, to_id, input_name], ...],
##    "output": id}
## A connection to input "X" replaces the constant param X with the source signal;
## a connection to "X_mod" is added to it (e.g. envelope -> "cutoff_mod").
## Several connections to the same input are summed.
##
## Node types and params (defaults in DEFAULTS):
##   sine saw square triangle : freq amp phase pw          (saw/square use polyBLEP)
##   noise_white noise_pink noise_brown : amp
##   const : value
##   adsr : start gate attack decay sustain release         (linear segments)
##   ar   : start attack release
##   lowpass highpass bandpass : in cutoff q                (RBJ biquad)
##   smooth : in time                                       (one-pole)
##   delay : in time feedback                               (wet signal; may close a loop)
##   gain : in gain      mixer : in (sum) gain      multiply : a b (ring / AM)
##   clip : in drive     (tanh soft clip; alias "distortion")
##   random_pitch : min max rate   (log-uniform sample&hold in Hz, new value each 1/rate s)
##   random_trigger : rate decay min_amp   (Poisson triggers, exponentially decaying bursts)
##
## Cycles are rejected unless they pass through a delay node (delay time is clamped to at
## least one processing block, so a delay output never depends on the current block).
##
## Ported / referenced sources (all algorithms re-implemented here, no code copied):
##  - Biquad coefficients: "Audio EQ Cookbook" by Robert Bristow-Johnson,
##    https://www.w3.org/TR/audio-eq-cookbook/ (published freely; W3C Note, public use of formulas).
##  - polyBLEP band-limited step correction: Valimaki & Huovilainen, "Antialiasing Oscillators
##    in Subtractive Synthesis", IEEE Signal Processing Magazine 2007 (published technique, formula only).
##  - Pink noise: Voss-McCartney multi-row algorithm (Gardner 1978 / musicdsp.org description), own implementation.
##  - Block-based dataflow evaluation, topological order and per-node profiling follow the
##    general design of Unreal Engine MetaSounds (concept only; no Unreal code used).
## No GPL/LGPL code and no Apache-2.0 code is included.

const BLOCK := 64
const MAX_NODE_COUNT := 256

const DEFAULTS := {
	"sine": {"freq": 440.0, "amp": 1.0, "phase": 0.0, "pw": 0.5},
	"saw": {"freq": 440.0, "amp": 1.0, "phase": 0.0, "pw": 0.5},
	"square": {"freq": 440.0, "amp": 1.0, "phase": 0.0, "pw": 0.5},
	"triangle": {"freq": 440.0, "amp": 1.0, "phase": 0.0, "pw": 0.5},
	"noise_white": {"amp": 1.0},
	"noise_pink": {"amp": 1.0},
	"noise_brown": {"amp": 1.0},
	"const": {"value": 1.0},
	"adsr": {"start": 0.0, "gate": 0.3, "attack": 0.01, "decay": 0.1, "sustain": 0.6, "release": 0.2},
	"ar": {"start": 0.0, "attack": 0.01, "release": 0.2},
	"lowpass": {"cutoff": 1000.0, "q": 0.707},
	"highpass": {"cutoff": 1000.0, "q": 0.707},
	"bandpass": {"cutoff": 1000.0, "q": 1.0},
	"smooth": {"time": 0.05},
	"delay": {"time": 0.25, "feedback": 0.3},
	"gain": {"gain": 1.0},
	"mixer": {"gain": 1.0},
	"multiply": {"a": 1.0, "b": 1.0},
	"clip": {"drive": 1.0},
	"distortion": {"drive": 1.0},
	"random_pitch": {"min": 200.0, "max": 400.0, "rate": 4.0},
	"random_trigger": {"rate": 20.0, "decay": 0.02, "min_amp": 0.3},
}

## Filled by every render: node id -> {"type", "usec", "calls", "pct"}; see profile_report().
static var last_profile: Dictionary = {}
static var last_errors: Array[String] = []
static var last_total_usec: int = 0


class _N extends RefCounted:
	var id: String = ""
	var type: String = ""
	var params: Dictionary = {}
	var inputs: Dictionary = {}
	var out := PackedFloat32Array()
	var ph: float = 0.0
	var s1: float = 0.0
	var s2: float = 0.0
	var lvl: float = 0.0
	var rate: float = 0.0
	var stage: int = 0
	var counter: int = 0
	var held: float = 0.0
	var hist := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	var rows := PackedFloat32Array()
	var rows_sum: float = 0.0
	var usec: int = 0
	var calls: int = 0


## Returns a list of human readable problems; empty means the graph can be rendered.
static func validate(graph: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var nodes: Dictionary = graph.get("nodes", {}) as Dictionary
	if nodes.is_empty():
		errors.append("graph has no nodes")
		return errors
	if nodes.size() > MAX_NODE_COUNT:
		errors.append("too many nodes (%d > %d)" % [nodes.size(), MAX_NODE_COUNT])
	for id in nodes:
		var def: Dictionary = nodes[id] as Dictionary
		var type: String = str(def.get("type", ""))
		if not DEFAULTS.has(type):
			errors.append("node '%s' has unknown type '%s'" % [id, type])
	var output: String = str(graph.get("output", ""))
	if not nodes.has(output):
		errors.append("output node '%s' does not exist" % output)
	var order_edges: Array = []
	for c in graph.get("connections", []) as Array:
		var conn: Array = c as Array
		if conn.size() != 3:
			errors.append("connection %s must be [from, to, input]" % str(conn))
			continue
		var from_id: String = str(conn[0])
		var to_id: String = str(conn[1])
		if not nodes.has(from_id):
			errors.append("connection from unknown node '%s'" % from_id)
			continue
		if not nodes.has(to_id):
			errors.append("connection to unknown node '%s'" % to_id)
			continue
		if str(conn[2]) == "":
			errors.append("connection %s -> %s has an empty input name" % [from_id, to_id])
		order_edges.append([from_id, to_id])
	var cyc := _cycle_nodes(nodes, order_edges)
	if not cyc.is_empty():
		errors.append("cycle without a delay node through: %s" % ", ".join(cyc))
	return errors


## Nodes left over by Kahn's algorithm; edges out of delay nodes do not order evaluation.
static func _cycle_nodes(nodes: Dictionary, edges: Array) -> Array[String]:
	var indeg: Dictionary = {}
	for id in nodes:
		indeg[id] = 0
	var adj: Dictionary = {}
	for e in edges:
		var ea: Array = e as Array
		var from_id: String = str(ea[0])
		var to_id: String = str(ea[1])
		if str((nodes[from_id] as Dictionary).get("type", "")) == "delay":
			continue
		indeg[to_id] = int(indeg[to_id]) + 1
		if not adj.has(from_id):
			adj[from_id] = []
		(adj[from_id] as Array).append(to_id)
	var queue: Array = []
	for id in nodes:
		if int(indeg[id]) == 0:
			queue.append(id)
	var done := 0
	while not queue.is_empty():
		var cur: String = str(queue.pop_back())
		done += 1
		for nxt in adj.get(cur, []) as Array:
			var key: String = str(nxt)
			indeg[key] = int(indeg[key]) - 1
			if int(indeg[key]) == 0:
				queue.append(key)
	var left: Array[String] = []
	if done < nodes.size():
		for id in nodes:
			if int(indeg[id]) > 0:
				left.append(str(id))
		left.sort()
	return left


## Renders `seconds` of audio; returns an empty array and fills last_errors when invalid.
static func render(graph: Dictionary, seconds: float, sample_rate: int = 22050, seed: int = 0) -> PackedFloat32Array:
	var t_start := Time.get_ticks_usec()
	last_profile = {}
	last_errors = validate(graph)
	if not last_errors.is_empty() or seconds <= 0.0:
		return PackedFloat32Array()
	var nodes: Dictionary = graph["nodes"] as Dictionary
	var sr := float(sample_rate)
	var wanted := int(ceil(seconds * sr))
	var blocks := int(ceil(float(wanted) / float(BLOCK)))
	var total := blocks * BLOCK

	# Instantiate only nodes the output depends on.
	var order_ids := _evaluation_order(graph)
	var by_id: Dictionary = {}
	var ordered: Array[_N] = []
	for id in order_ids:
		var def: Dictionary = nodes[id] as Dictionary
		var nd := _N.new()
		nd.id = str(id)
		nd.type = str(def.get("type", ""))
		nd.params = (DEFAULTS[nd.type] as Dictionary).duplicate()
		for k in def:
			if k != "type":
				nd.params[k] = def[k]
		nd.out.resize(BLOCK)
		nd.rng.seed = hash("%d:%s" % [seed, nd.id])
		if nd.type == "delay":
			nd.hist.resize(total)
		if nd.type == "noise_pink":
			nd.rows.resize(8)
		by_id[nd.id] = nd
		ordered.append(nd)
	for c in graph.get("connections", []) as Array:
		var conn: Array = c as Array
		var src: _N = by_id.get(str(conn[0]), null) as _N
		var dst: _N = by_id.get(str(conn[1]), null) as _N
		if src == null or dst == null:
			continue
		var name := str(conn[2])
		if not dst.inputs.has(name):
			dst.inputs[name] = []
		(dst.inputs[name] as Array).append(src)

	var result := PackedFloat32Array()
	result.resize(wanted)
	var out_node: _N = by_id[str(graph["output"])] as _N
	for b in blocks:
		var t0 := b * BLOCK
		for nd in ordered:
			var t_node := Time.get_ticks_usec()
			_process(nd, BLOCK, t0, sr)
			nd.usec += Time.get_ticks_usec() - t_node
			nd.calls += 1
		for nd in ordered:
			if nd.type == "delay":
				var t_post := Time.get_ticks_usec()
				_delay_write(nd, t0, sr)
				nd.usec += Time.get_ticks_usec() - t_post
		var n := mini(BLOCK, wanted - t0)
		var buf := out_node.out
		for i in n:
			var v := buf[i]
			if is_nan(v) or is_inf(v):
				v = 0.0
			result[t0 + i] = clampf(v, -1.0, 1.0)

	last_total_usec = Time.get_ticks_usec() - t_start
	var sum_usec := 0
	for nd in ordered:
		sum_usec += nd.usec
	for nd in ordered:
		last_profile[nd.id] = {
			"type": nd.type,
			"usec": nd.usec,
			"calls": nd.calls,
			"pct": 100.0 * float(nd.usec) / float(maxi(sum_usec, 1)),
		}
	return result


## Profiler view: rows sorted by cost, most expensive first.
static func profile_report() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id in last_profile:
		var row: Dictionary = (last_profile[id] as Dictionary).duplicate()
		row["id"] = id
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["usec"]) > int(b["usec"]))
	return rows


## Topological order of nodes the output (transitively) depends on.
static func _evaluation_order(graph: Dictionary) -> Array[String]:
	var nodes: Dictionary = graph["nodes"] as Dictionary
	var incoming: Dictionary = {}
	for c in graph.get("connections", []) as Array:
		var conn: Array = c as Array
		var to_id := str(conn[1])
		if not incoming.has(to_id):
			incoming[to_id] = []
		(incoming[to_id] as Array).append(str(conn[0]))
	var needed: Dictionary = {}
	var stack: Array[String] = [str(graph["output"])]
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		if needed.has(cur):
			continue
		needed[cur] = true
		for s in incoming.get(cur, []) as Array:
			stack.append(str(s))
	# Depth-first post-order; edges out of delay nodes are not followed (delay output is block-latent).
	var visited: Dictionary = {}
	var order: Array[String] = []
	var ids: Array = needed.keys()
	ids.sort()
	for id in ids:
		_visit(str(id), incoming, nodes, visited, order)
	return order


static func _visit(id: String, incoming: Dictionary, nodes: Dictionary, visited: Dictionary, order: Array[String]) -> void:
	if visited.has(id):
		return
	visited[id] = true
	# A delay's own inputs are ordered separately (its output only needs history).
	if str((nodes[id] as Dictionary).get("type", "")) != "delay":
		for s in incoming.get(id, []) as Array:
			_visit(str(s), incoming, nodes, visited, order)
	order.append(id)


static func to_wav(samples: PackedFloat32Array, sample_rate: int = 22050) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	wav.data = bytes
	return wav


# --- block processing ---------------------------------------------------------------------

## Signal for input `name`: connected sources summed (or constant param) plus any "<name>_mod" sources.
static func _sig(nd: _N, name: String, n: int) -> PackedFloat32Array:
	var srcs: Array = nd.inputs.get(name, []) as Array
	var mods: Array = nd.inputs.get(name + "_mod", []) as Array
	if srcs.size() == 1 and mods.is_empty():
		return (srcs[0] as _N).out
	var buf := PackedFloat32Array()
	buf.resize(n)
	if srcs.is_empty():
		var base: float = 0.0 if name == "in" else float(nd.params.get(name, 0.0))
		if base != 0.0:
			buf.fill(base)
	else:
		for s in srcs:
			var so := (s as _N).out
			for i in n:
				buf[i] += so[i]
	for m in mods:
		var mo := (m as _N).out
		for i in n:
			buf[i] += mo[i]
	return buf


static func _process(nd: _N, n: int, t0: int, sr: float) -> void:
	var out := nd.out
	match nd.type:
		"sine", "saw", "square", "triangle":
			_osc(nd, out, n, sr)
		"noise_white":
			var amp := _sig(nd, "amp", n)
			for i in n:
				out[i] = nd.rng.randf_range(-1.0, 1.0) * amp[i]
		"noise_pink":
			var amp := _sig(nd, "amp", n)
			for i in n:
				nd.counter += 1
				# Voss-McCartney: row k refreshes every 2^k samples.
				var c := nd.counter
				var row := 0
				while row < 7 and (c & 1) == 0:
					c >>= 1
					row += 1
				nd.rows_sum -= nd.rows[row]
				nd.rows[row] = nd.rng.randf_range(-1.0, 1.0)
				nd.rows_sum += nd.rows[row]
				out[i] = (nd.rows_sum + nd.rng.randf_range(-1.0, 1.0)) * 0.25 * amp[i]
		"noise_brown":
			var amp := _sig(nd, "amp", n)
			var b := nd.s1
			for i in n:
				b = (b + 0.02 * nd.rng.randf_range(-1.0, 1.0)) / 1.02
				out[i] = b * 3.5 * amp[i]
			nd.s1 = b
		"const":
			out.fill(float(nd.params["value"]))
		"adsr", "ar":
			_envelope(nd, out, n, t0, sr)
		"lowpass", "highpass", "bandpass":
			_biquad(nd, out, n, sr)
		"smooth":
			var x := _sig(nd, "in", n)
			var k := 1.0 - exp(-1.0 / (maxf(float(nd.params["time"]), 1e-5) * sr))
			var y := nd.s1
			for i in n:
				y += k * (x[i] - y)
				out[i] = y
			nd.s1 = y
		"delay":
			var d := _delay_samples(nd, sr)
			for i in n:
				var idx := t0 + i - d
				out[i] = nd.hist[idx] if idx >= 0 else 0.0
		"gain":
			var x := _sig(nd, "in", n)
			var g := _sig(nd, "gain", n)
			for i in n:
				out[i] = x[i] * g[i]
		"mixer":
			var x := _sig(nd, "in", n)
			var g := _sig(nd, "gain", n)
			for i in n:
				out[i] = x[i] * g[i]
		"multiply":
			var a := _sig(nd, "a", n)
			var b := _sig(nd, "b", n)
			for i in n:
				out[i] = a[i] * b[i]
		"clip", "distortion":
			var x := _sig(nd, "in", n)
			var drive := _sig(nd, "drive", n)
			for i in n:
				out[i] = tanh(x[i] * drive[i])
		"random_pitch":
			var lo := maxf(float(nd.params["min"]), 1.0)
			var hi := maxf(float(nd.params["max"]), lo)
			var interval := int(sr / maxf(float(nd.params["rate"]), 0.01))
			for i in n:
				if nd.counter <= 0:
					nd.held = exp(nd.rng.randf_range(log(lo), log(hi)))
					nd.counter = interval
				nd.counter -= 1
				out[i] = nd.held
		"random_trigger":
			var p := float(nd.params["rate"]) / sr
			var k := exp(-1.0 / (maxf(float(nd.params["decay"]), 1e-4) * sr))
			var min_amp := float(nd.params["min_amp"])
			var e := nd.lvl
			for i in n:
				if nd.rng.randf() < p:
					e = nd.rng.randf_range(min_amp, 1.0)
				out[i] = e
				e *= k
			nd.lvl = e


static func _osc(nd: _N, out: PackedFloat32Array, n: int, sr: float) -> void:
	var freq := _sig(nd, "freq", n)
	var amp := _sig(nd, "amp", n)
	var phase_off := float(nd.params["phase"])
	var pw := clampf(float(nd.params["pw"]), 0.01, 0.99)
	var ph := nd.ph
	var type := nd.type
	for i in n:
		var dt := clampf(freq[i] / sr, 0.0, 0.49)
		var t := ph + phase_off
		t -= floorf(t)
		var v := 0.0
		match type:
			"sine":
				v = sin(TAU * t)
			"saw":
				v = 2.0 * t - 1.0 - _poly_blep(t, dt)
			"square":
				v = 1.0 if t < pw else -1.0
				v += _poly_blep(t, dt)
				var t2 := t + 1.0 - pw
				t2 -= floorf(t2)
				v -= _poly_blep(t2, dt)
			"triangle":
				v = 4.0 * absf(t - 0.5) - 1.0
		out[i] = v * amp[i]
		ph += dt
		ph -= floorf(ph)
	nd.ph = ph


## Band-limited step residual (Valimaki & Huovilainen 2007).
static func _poly_blep(t: float, dt: float) -> float:
	if dt <= 0.0:
		return 0.0
	if t < dt:
		var x := t / dt
		return x + x - x * x - 1.0
	if t > 1.0 - dt:
		var x := (t - 1.0) / dt
		return x * x + x + x + 1.0
	return 0.0


## Stages: 0 waiting, 1 attack, 2 decay, 3 sustain, 4 release, 5 finished.
static func _envelope(nd: _N, out: PackedFloat32Array, n: int, t0: int, sr: float) -> void:
	var is_adsr := nd.type == "adsr"
	var start := float(nd.params["start"])
	var gate_end := start + float(nd.params["gate"]) if is_adsr else INF
	var atk := 1.0 / (maxf(float(nd.params["attack"]), 1e-4) * sr)
	var dec := 0.0
	var sus := 1.0
	var rel := maxf(float(nd.params["release"]), 1e-4) * sr
	if is_adsr:
		sus = clampf(float(nd.params["sustain"]), 0.0, 1.0)
		dec = (1.0 - sus) / (maxf(float(nd.params["decay"]), 1e-4) * sr)
	var lvl := nd.lvl
	var stage := nd.stage
	var rate := nd.rate
	for i in n:
		var t := float(t0 + i) / sr
		if stage == 0 and t >= start:
			stage = 1
		if is_adsr and t >= gate_end and stage >= 1 and stage <= 3:
			stage = 4
			rate = lvl / rel
		match stage:
			1:
				lvl += atk
				if lvl >= 1.0:
					lvl = 1.0
					if is_adsr:
						stage = 2
					else:
						stage = 4
						rate = 1.0 / rel
			2:
				lvl -= dec
				if lvl <= sus:
					lvl = sus
					stage = 3
			4:
				lvl -= rate
				if lvl <= 0.0:
					lvl = 0.0
					stage = 5
		out[i] = lvl
	nd.lvl = lvl
	nd.stage = stage
	nd.rate = rate


## RBJ cookbook biquad, transposed direct form II. Coefficients refresh per sample only when
## cutoff or q are modulated, otherwise once per block.
static func _biquad(nd: _N, out: PackedFloat32Array, n: int, sr: float) -> void:
	var x := _sig(nd, "in", n)
	var cutoff := _sig(nd, "cutoff", n)
	var q := _sig(nd, "q", n)
	var modulated := nd.inputs.has("cutoff") or nd.inputs.has("cutoff_mod") or nd.inputs.has("q") or nd.inputs.has("q_mod")
	var s1 := nd.s1
	var s2 := nd.s2
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	for i in n:
		if i == 0 or modulated:
			var f := clampf(cutoff[i], 10.0, sr * 0.45)
			var w0 := TAU * f / sr
			var cs := cos(w0)
			var alpha := sin(w0) / (2.0 * maxf(q[i], 0.05))
			var a0 := 1.0 + alpha
			a1 = -2.0 * cs / a0
			a2 = (1.0 - alpha) / a0
			match nd.type:
				"lowpass":
					b0 = (1.0 - cs) * 0.5 / a0
					b1 = (1.0 - cs) / a0
					b2 = b0
				"highpass":
					b0 = (1.0 + cs) * 0.5 / a0
					b1 = -(1.0 + cs) / a0
					b2 = b0
				_:
					b0 = alpha / a0
					b1 = 0.0
					b2 = -b0
		var v := x[i]
		var y := b0 * v + s1
		s1 = b1 * v - a1 * y + s2
		s2 = b2 * v - a2 * y
		out[i] = y
	nd.s1 = s1
	nd.s2 = s2


static func _delay_samples(nd: _N, sr: float) -> int:
	return maxi(BLOCK, int(float(nd.params["time"]) * sr))


## Second pass of a block: record input (plus internal feedback of the wet signal) into history.
static func _delay_write(nd: _N, t0: int, sr: float) -> void:
	var x := _sig(nd, "in", BLOCK)
	var fb := clampf(float(nd.params["feedback"]), 0.0, 0.98)
	var d := _delay_samples(nd, sr)
	for i in BLOCK:
		var idx := t0 + i
		var wet := nd.hist[idx - d] if idx - d >= 0 else 0.0
		nd.hist[idx] = x[i] + fb * wet
