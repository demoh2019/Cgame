extends RefCounted
## GPU compute backend for the VFX graph (scripts/client/vfx_graph.gd) update stage.
##
## Compiles a GPU-able subset of update modules (gravity, drag, curl_noise "lite", vortex,
## collide_plane, kill_below_plane, color_over_life, size_over_life) into a GLSL compute shader
## (SSBO particle buffer + atomic-append event buffer for death/collision routing). When no local
## RenderingDevice exists (headless/dummy renderer, compatibility renderer) or compilation fails,
## an exact CPU implementation of the same kernel runs instead. The CPU kernel is the reference
## and is what the tests verify; the GPU path is UNVERIFIED until run on real hardware.
##
## Usage: var b := GpuParticleBackendScript.new(); b.create(system_asset, seed); b.tick(dt)
## (system_asset = {"emitters": {...}} or a single emitter asset). Spawn modules are executed on the
## CPU (spawn_rate, spawn_burst, lifetime_random, initial_color, initial_size, initial_velocity
## without spread/radial); emission positions other than the emitter origin are not supported.
##
## curl_noise here is "lite": an analytic sine/cosine vector potential (divergence-free curl), not
## FastNoiseLite, so it is cheap and identical on CPU and GPU (it will not match VfxGraph noise).
##
## Credit: compute pipeline pattern from the public Godot 4 RenderingDevice compute tutorial and
## godot-demo-projects "compute_texture" (MIT, concepts only). Event append buffer idea follows
## Niagara GPU event routing (concepts only). Original implementation, project license.

const TEMPLATE_PATH: String = "res://shaders/compute/particles_update.glsl.template"
const SUPPORTED_UPDATE: PackedStringArray = ["gravity", "drag", "curl_noise", "vortex", "collide_plane", "kill_below_plane", "color_over_life", "size_over_life"]
const SUPPORTED_SPAWN: PackedStringArray = ["spawn_rate", "spawn_burst", "lifetime_random", "initial_color", "initial_size", "initial_velocity"]
const POST_MODULES: PackedStringArray = ["collide_plane", "kill_below_plane"]
const EMISSION_MODULES: PackedStringArray = ["spawn_rate", "spawn_burst"]
const LOCAL_SIZE: int = 64
const FLOATS_PER_PARTICLE: int = 20
const BYTES_PER_PARTICLE: int = 80
const EVENT_HEADER_BYTES: int = 16
const EVENT_BYTES: int = 32
const CURL_EPS: float = 0.05


class Em extends RefCounted:
	var ename: String = ""
	var cap: int = 0
	var count: int = 0
	var pos: PackedVector3Array = PackedVector3Array()
	var vel: PackedVector3Array = PackedVector3Array()
	var col: PackedColorArray = PackedColorArray()
	var base_col: PackedColorArray = PackedColorArray()
	var size: PackedFloat32Array = PackedFloat32Array()
	var base_size: PackedFloat32Array = PackedFloat32Array()
	var age: PackedFloat32Array = PackedFloat32Array()
	var life: PackedFloat32Array = PackedFloat32Array()
	var plan: Dictionary = {}
	var spawn_mods: Array = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var time: float = 0.0
	var accum: float = 0.0
	var duration: float = 0.0
	var fired: Dictionary = {}
	var pending: Array = []
	var events: Array = []
	var total_spawned: int = 0
	# device resources (all RID.new() / invalid until built)
	var gpu_failed: bool = false
	var shader: RID = RID()
	var pipeline: RID = RID()
	var particle_buf: RID = RID()
	var event_buf: RID = RID()
	var uniform_set: RID = RID()


var supported_emitters: Array[String] = []
var unsupported: Array[String] = []
var last_path: String = "none"
var force_cpu: bool = false

var _ems: Dictionary = {}
var _order: Array[String] = []
var _rd: RenderingDevice = null
var _gpu_ready: bool = false


# ---- support / planning ---------------------------------------------------

static func _as_emitter(asset: Dictionary) -> Dictionary:
	if asset.has("emitters"):
		return {}
	return asset


## True when every update/spawn module of the emitter asset can run in the GPU kernel.
static func supports(emitter_asset: Dictionary) -> bool:
	return unsupported_modules(emitter_asset).is_empty()


## Human-readable reasons an emitter asset is not GPU-able (empty = supported).
static func unsupported_modules(emitter_asset: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var attrs: Dictionary = emitter_asset.get("attributes", {})
	if not attrs.is_empty():
		out.append("custom attributes")
	var update_list: Array = emitter_asset.get("update", [])
	for m_v in update_list:
		var m: Dictionary = m_v
		var kind: String = str(m.get("type", "?"))
		if not SUPPORTED_UPDATE.has(kind):
			out.append(kind)
			continue
		if kind == "color_over_life" or kind == "size_over_life":
			if m.get("gradient", null) != null or not _valid_stops(m.get("stops", []), kind == "color_over_life"):
				out.append(kind + " (needs stops)")
	var spawn_list: Array = emitter_asset.get("spawn", [])
	for m_v in spawn_list:
		var m: Dictionary = m_v
		var kind: String = str(m.get("type", "?"))
		if not SUPPORTED_SPAWN.has(kind):
			out.append(kind)
		elif kind == "initial_velocity" and (float(m.get("spread", 0.0)) > 0.0 or float(m.get("radial", 0.0)) != 0.0):
			out.append("initial_velocity spread/radial")
	return out


static func supports_system(system_asset: Dictionary) -> bool:
	var defs: Dictionary = system_asset.get("emitters", {})
	for key in defs.keys():
		if not supports(defs[key]):
			return false
	return not defs.is_empty()


static func _valid_stops(stops: Variant, is_color: bool) -> bool:
	if not (stops is Array):
		return false
	var arr: Array = stops
	if arr.is_empty():
		return false
	for s in arr:
		if not (s is Array) or (s as Array).size() != 2:
			return false
		if is_color and not ((s as Array)[1] is Color):
			return false
	return true


static func _normalize_spec(spec: Variant) -> Array:
	var out: Array = []
	if spec is Dictionary:
		out.append(spec)
	elif spec is Array:
		for s in spec:
			if s is Dictionary:
				out.append(s)
	return out


## Splits update modules into update/post lists and assigns event slots
## (slot 0 = death spec, 1.. = collide_plane modules that route an event).
static func plan_emitter(emitter_asset: Dictionary) -> Dictionary:
	var events: Dictionary = emitter_asset.get("events", {})
	var specs: Array = [_normalize_spec(events.get("death", null))]
	var update_mods: Array = []
	var post_mods: Array = []
	var update_list: Array = emitter_asset.get("update", [])
	for i in update_list.size():
		var m: Dictionary = (update_list[i] as Dictionary).duplicate()
		m["_idx"] = i
		m["_slot"] = -1
		if str(m.get("type", "")) == "collide_plane":
			var spec: Array = _normalize_spec(m.get("on_event", events.get("collision", null)))
			if not spec.is_empty():
				specs.append(spec)
				m["_slot"] = specs.size() - 1
		if POST_MODULES.has(str(m.get("type", ""))):
			post_mods.append(m)
		else:
			update_mods.append(m)
	return {"update": update_mods, "post": post_mods, "specs": specs, "route_death": not (specs[0] as Array).is_empty()}


# ---- GLSL generation -----------------------------------------------------

static func _f(x: float) -> String:
	return "%.8f" % x


static func _v3(v: Vector3) -> String:
	return "vec3(%s, %s, %s)" % [_f(v.x), _f(v.y), _f(v.z)]


static func _v4(c: Color) -> String:
	return "vec4(%s, %s, %s, %s)" % [_f(c.r), _f(c.g), _f(c.b), _f(c.a)]


static func _stop_fn(fname: String, stops: Array, is_color: bool) -> String:
	var rt: String = "vec4" if is_color else "float"
	var s: String = "%s %s(float u) {\n" % [rt, fname]
	for i in stops.size():
		var cur: Array = stops[i]
		var off: String = _f(float(cur[0]))
		var val: String = _v4(cur[1]) if is_color else _f(float(cur[1]))
		if i == 0:
			s += "\tif (u <= %s) { return %s; }\n" % [off, val]
		else:
			var prev: Array = stops[i - 1]
			var pval: String = _v4(prev[1]) if is_color else _f(float(prev[1]))
			s += "\tif (u <= %s) { return mix(%s, %s, (u - %s) / max(%s - %s, 0.00001)); }\n" % [off, pval, val, _f(float(prev[0])), off, _f(float(prev[0]))]
	var tail: Array = stops[stops.size() - 1]
	s += "\treturn %s;\n}\n" % (_v4(tail[1]) if is_color else _f(float(tail[1])))
	return s


static func _module_glsl(m: Dictionary, helpers: Array) -> String:
	var idx: int = int(m["_idx"])
	match str(m["type"]):
		"gravity":
			return "\t{ v += %s * dt; }\n" % _v3(m.get("gravity", Vector3(0.0, -9.81, 0.0)))
		"drag":
			return "\t{ v *= exp(-%s * dt); }\n" % _f(float(m.get("drag", 1.0)))
		"curl_noise":
			return "\t{ v += cn_curl(p + %s * params.time, %s) * (%s * dt); }\n" % [_v3(m.get("scroll", Vector3.ZERO)), _f(float(m.get("frequency", 0.5))), _f(float(m.get("strength", 1.0)))]
		"vortex":
			var axis: Vector3 = (m.get("axis", Vector3.UP) as Vector3).normalized()
			var s: String = "\t{\n\t\tvec3 r = p - %s;\n\t\tvec3 tg = cross(%s, r);\n\t\tfloat tl = length(tg);\n" % [_v3(m.get("center", Vector3.ZERO)), _v3(axis)]
			s += "\t\tif (tl > 0.0001) { v += tg / tl * (%s * dt); }\n" % _f(float(m.get("strength", 1.0)))
			var pull: float = float(m.get("pull", 0.0))
			if pull != 0.0:
				s += "\t\tvec3 rr = r - %s * dot(r, %s);\n\t\tfloat rl = length(rr);\n\t\tif (rl > 0.0) { v -= rr / rl * (%s * dt); }\n" % [_v3(axis), _v3(axis), _f(pull)]
			return s + "\t}\n"
		"color_over_life":
			helpers.append(_stop_fn("color_curve_%d" % idx, m["stops"], true))
			return "\t{ float u = clamp(age / max(life, 0.0001), 0.0, 1.0); col = base_col * color_curve_%d(u); }\n" % idx
		"size_over_life":
			helpers.append(_stop_fn("size_curve_%d" % idx, m["stops"], false))
			return "\t{ float u = clamp(age / max(life, 0.0001), 0.0, 1.0); size = base_size * size_curve_%d(u); }\n" % idx
		"collide_plane":
			var n: Vector3 = (m.get("normal", Vector3.UP) as Vector3).normalized()
			var s2: String = "\t{\n\t\tvec3 n = %s;\n\t\tfloat d = dot(n, p) - %s;\n\t\tfloat vn = dot(n, v);\n" % [_v3(n), _f(float(m.get("offset", 0.0)))]
			s2 += "\t\tif (d < 0.0 && vn < 0.0) {\n\t\t\tp -= n * d;\n\t\t\tvec3 nv = n * vn;\n"
			s2 += "\t\t\tvec3 tv = (v - nv) * (1.0 - %s);\n\t\t\tv = tv - nv * %s;\n" % [_f(float(m.get("friction", 0.0))), _f(float(m.get("restitution", 0.5)))]
			if int(m["_slot"]) >= 0:
				s2 += "\t\t\temit_event(%du, p, v);\n" % int(m["_slot"])
			return s2 + "\t\t}\n\t}\n"
		"kill_below_plane":
			var kn: Vector3 = (m.get("normal", Vector3.UP) as Vector3).normalized()
			return "\t{ if (dot(%s, p) - %s < 0.0) { age = life + 1.0; } }\n" % [_v3(kn), _f(float(m.get("offset", 0.0)))]
	return ""


const CURL_HELPER: String = """vec3 cn_potential(vec3 q, float f) {
	return vec3(sin(q.y * f + 1.3) * cos(q.z * f + 0.7),
			sin(q.z * f + 2.1) * cos(q.x * f + 4.2),
			sin(q.x * f + 3.3) * cos(q.y * f + 5.1));
}

vec3 cn_curl(vec3 q, float f) {
	const float e = 0.05;
	vec3 ex = vec3(e, 0.0, 0.0);
	vec3 ey = vec3(0.0, e, 0.0);
	vec3 ez = vec3(0.0, 0.0, e);
	vec3 dx = cn_potential(q + ex, f) - cn_potential(q - ex, f);
	vec3 dy = cn_potential(q + ey, f) - cn_potential(q - ey, f);
	vec3 dz = cn_potential(q + ez, f) - cn_potential(q - ez, f);
	return vec3(dy.z - dz.y, dz.x - dx.z, dx.y - dy.x) / (2.0 * e);
}
"""


static func _load_template() -> String:
	if not FileAccess.file_exists(TEMPLATE_PATH):
		return ""
	var f: FileAccess = FileAccess.open(TEMPLATE_PATH, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


## Full compute shader source (starts with "#[compute]") for an emitter asset, or "" if the asset
## is not GPU-able or the template is missing.
static func generate_compute_source(emitter_asset: Dictionary) -> String:
	if not supports(emitter_asset):
		return ""
	var tpl: String = _load_template()
	if tpl.is_empty():
		return ""
	var plan: Dictionary = plan_emitter(emitter_asset)
	var helpers: Array = []
	var update_code: String = ""
	var post_code: String = ""
	var needs_curl: bool = false
	for m_v in plan["update"]:
		var m: Dictionary = m_v
		if str(m["type"]) == "curl_noise":
			needs_curl = true
		update_code += _module_glsl(m, helpers)
	for m_v in plan["post"]:
		post_code += _module_glsl(m_v, helpers)
	var helper_text: String = CURL_HELPER if needs_curl else ""
	for h in helpers:
		helper_text += "\n" + str(h)
	var cap: int = maxi(int(emitter_asset.get("max_particles", 1000)), 1)
	var out: String = tpl
	out = out.replace("{{LOCAL_SIZE}}", str(LOCAL_SIZE))
	out = out.replace("{{MAX_PARTICLES}}", str(cap))
	out = out.replace("{{ROUTE_DEATH}}", "true" if bool(plan["route_death"]) else "false")
	out = out.replace("{{HELPERS}}", helper_text)
	out = out.replace("{{UPDATE_CODE}}", update_code)
	out = out.replace("{{POST_CODE}}", post_code)
	return out


# ---- lifecycle -------------------------------------------------------------

## Builds emitter state from a system asset ({"emitters": {...}}) or one emitter asset.
## Returns true when every emitter is GPU-able. Unsupported emitters are skipped (see `unsupported`).
func create(system_asset: Dictionary, seed_value: int = 1) -> bool:
	shutdown()
	_ems.clear()
	_order.clear()
	supported_emitters.clear()
	unsupported.clear()
	var defs: Dictionary = {}
	if system_asset.has("emitters"):
		defs = system_asset["emitters"]
	else:
		defs = {"main": system_asset}
	var idx: int = 0
	for key in defs.keys():
		var emitter_name: String = str(key)
		var def: Dictionary = defs[key]
		if not supports(def):
			unsupported.append(emitter_name)
			continue
		_ems[emitter_name] = _make_em(emitter_name, def, seed_value * 1000003 + idx * 7919 + 17)
		_order.append(emitter_name)
		supported_emitters.append(emitter_name)
		idx += 1
	_open_device()
	if _gpu_ready:
		_remember_sources(system_asset)
	return unsupported.is_empty()


func _make_em(emitter_name: String, def: Dictionary, seed_value: int) -> Em:
	var em: Em = Em.new()
	em.ename = emitter_name
	em.cap = maxi(int(def.get("max_particles", 1000)), 1)
	em.duration = float(def.get("duration", 0.0))
	em.pos.resize(em.cap)
	em.vel.resize(em.cap)
	em.col.resize(em.cap)
	em.base_col.resize(em.cap)
	em.size.resize(em.cap)
	em.base_size.resize(em.cap)
	em.age.resize(em.cap)
	em.life.resize(em.cap)
	em.rng.seed = seed_value
	em.plan = plan_emitter(def)
	var spawn_list: Array = def.get("spawn", [])
	for i in spawn_list.size():
		var m: Dictionary = (spawn_list[i] as Dictionary).duplicate()
		m["_idx"] = i
		em.spawn_mods.append(m)
	return em


func _open_device() -> void:
	_gpu_ready = false
	if force_cpu:
		return
	if _rd == null:
		_rd = RenderingServer.create_local_rendering_device()
	_gpu_ready = _rd != null


## True when a local RenderingDevice exists and the GPU path will be attempted.
func device_available() -> bool:
	return _gpu_ready


func emitter_names() -> Array[String]:
	return supported_emitters


func get_emitter(emitter_name: String) -> Em:
	return _ems.get(emitter_name, null) as Em


func count(emitter_name: String) -> int:
	var em: Em = get_emitter(emitter_name)
	return 0 if em == null else em.count


## Spawns n particles directly (applies the emitter's spawn init modules at `origin`).
func spawn(emitter_name: String, n: int, origin: Vector3 = Vector3.ZERO, inherit: Vector3 = Vector3.ZERO) -> int:
	var em: Em = get_emitter(emitter_name)
	if em == null:
		return 0
	return _spawn(em, n, origin, inherit)


func _spawn(em: Em, requested: int, origin: Vector3, inherit: Vector3) -> int:
	var n: int = mini(requested, em.cap - em.count)
	if n <= 0:
		return 0
	var start: int = em.count
	em.count += n
	em.total_spawned += n
	for i in range(start, em.count):
		em.pos[i] = origin
		em.vel[i] = inherit
		em.col[i] = Color.WHITE
		em.size[i] = 1.0
		em.age[i] = 0.0
		em.life[i] = 1.0
	for m_v in em.spawn_mods:
		var m: Dictionary = m_v
		match str(m["type"]):
			"lifetime_random":
				var lmin: float = float(m.get("min", 1.0))
				var lmax: float = float(m.get("max", 1.0))
				for i in range(start, em.count):
					em.life[i] = em.rng.randf_range(lmin, lmax)
			"initial_color":
				var c0: Color = m.get("color", Color.WHITE)
				var c1: Color = m.get("color_b", c0)
				for i in range(start, em.count):
					em.col[i] = c0.lerp(c1, em.rng.randf())
			"initial_size":
				var s0: float = float(m.get("min", 1.0))
				var s1: float = float(m.get("max", s0))
				for i in range(start, em.count):
					em.size[i] = em.rng.randf_range(s0, s1)
			"initial_velocity":
				var dir: Vector3 = (m.get("direction", Vector3.UP) as Vector3).normalized()
				var smin: float = float(m.get("speed_min", m.get("speed", 1.0)))
				var smax: float = float(m.get("speed_max", m.get("speed", 1.0)))
				for i in range(start, em.count):
					em.vel[i] += dir * em.rng.randf_range(smin, smax)
	for i in range(start, em.count):
		em.base_col[i] = em.col[i]
		em.base_size[i] = em.size[i]
	return n


## Advances every emitter by dt (update kernel, death compaction, event routing, spawning).
## Returns the number of routed events that were delivered to target emitters.
func tick(dt: float) -> int:
	var routed: int = 0
	var gpu_used: bool = false
	var cpu_used: bool = false
	for emitter_name in _order:
		var em: Em = _ems[emitter_name]
		em.time += dt
		if em.count > 0:
			if _gpu_ready and _step_gpu(em, dt):
				gpu_used = true
			else:
				kernel_cpu(em, dt)
				cpu_used = true
			_compact(em)
		routed += _route_events(em)
		var pending: Array = em.pending
		em.pending = []
		for ev_v in pending:
			var ev: Dictionary = ev_v
			_spawn(em, int(ev["count"]), ev["pos"], ev["vel"])
		_run_emission(em, dt)
	if gpu_used:
		last_path = "gpu"
	elif cpu_used:
		last_path = "cpu"
	return routed


func _run_emission(em: Em, dt: float) -> void:
	for m_v in em.spawn_mods:
		var m: Dictionary = m_v
		var kind: String = str(m["type"])
		if kind == "spawn_rate":
			if em.duration <= 0.0 or em.time <= em.duration:
				em.accum += float(m.get("rate", 10.0)) * dt
				var n: int = int(floor(em.accum))
				em.accum -= float(n)
				_spawn(em, n, Vector3.ZERO, Vector3.ZERO)
		elif kind == "spawn_burst":
			var idx: int = int(m["_idx"])
			if not em.fired.has(idx) and em.time >= float(m.get("time", 0.0)):
				em.fired[idx] = true
				_spawn(em, int(m.get("count", 10)), Vector3.ZERO, Vector3.ZERO)


func _route_events(em: Em) -> int:
	var delivered: int = 0
	var specs: Array = em.plan["specs"]
	for ev_v in em.events:
		var ev: Dictionary = ev_v
		var slot: int = int(ev["slot"])
		if slot < 0 or slot >= specs.size():
			continue
		for spec_v in (specs[slot] as Array):
			var spec: Dictionary = spec_v
			var target: Em = get_emitter(str(spec.get("emitter", "")))
			if target == null:
				continue
			var inherit: float = float(spec.get("inherit_velocity", 0.0))
			var ev_vel: Vector3 = ev["vel"]
			target.pending.append({"count": int(spec.get("count", 1)), "pos": ev["pos"], "vel": ev_vel * inherit})
			delivered += 1
	em.events.clear()
	return delivered


## Removes particles with age >= life (swap-remove from the end, like VfxGraph).
func _compact(em: Em) -> void:
	var i: int = em.count - 1
	while i >= 0:
		if em.age[i] >= em.life[i]:
			var last: int = em.count - 1
			if i != last:
				em.pos[i] = em.pos[last]
				em.vel[i] = em.vel[last]
				em.col[i] = em.col[last]
				em.base_col[i] = em.base_col[last]
				em.size[i] = em.size[last]
				em.base_size[i] = em.base_size[last]
				em.age[i] = em.age[last]
				em.life[i] = em.life[last]
			em.count -= 1
		i -= 1


# ---- exact CPU kernel (mirrors the GLSL one invocation per particle) -----------

static func curl_potential(q: Vector3, f: float) -> Vector3:
	return Vector3(
		sin(q.y * f + 1.3) * cos(q.z * f + 0.7),
		sin(q.z * f + 2.1) * cos(q.x * f + 4.2),
		sin(q.x * f + 3.3) * cos(q.y * f + 5.1))


static func curl_lite(q: Vector3, f: float) -> Vector3:
	var e: float = CURL_EPS
	var dx: Vector3 = curl_potential(q + Vector3(e, 0.0, 0.0), f) - curl_potential(q - Vector3(e, 0.0, 0.0), f)
	var dy: Vector3 = curl_potential(q + Vector3(0.0, e, 0.0), f) - curl_potential(q - Vector3(0.0, e, 0.0), f)
	var dz: Vector3 = curl_potential(q + Vector3(0.0, 0.0, e), f) - curl_potential(q - Vector3(0.0, 0.0, e), f)
	return Vector3(dy.z - dz.y, dz.x - dx.z, dx.y - dy.x) / (2.0 * e)


static func _curve_float(stops: Array, u: float) -> float:
	var first: Array = stops[0]
	if u <= float(first[0]):
		return float(first[1])
	for i in range(1, stops.size()):
		var b: Array = stops[i]
		if u <= float(b[0]):
			var a: Array = stops[i - 1]
			var span: float = maxf(float(b[0]) - float(a[0]), 0.00001)
			return lerpf(float(a[1]), float(b[1]), (u - float(a[0])) / span)
	var tail: Array = stops[stops.size() - 1]
	return float(tail[1])


static func _curve_color(stops: Array, u: float) -> Color:
	var first: Array = stops[0]
	if u <= float(first[0]):
		return first[1]
	for i in range(1, stops.size()):
		var b: Array = stops[i]
		if u <= float(b[0]):
			var a: Array = stops[i - 1]
			var span: float = maxf(float(b[0]) - float(a[0]), 0.00001)
			var ca: Color = a[1]
			var cb: Color = b[1]
			return ca.lerp(cb, (u - float(a[0])) / span)
	var tail: Array = stops[stops.size() - 1]
	return tail[1]


func _apply_module(em: Em, m: Dictionary, i: int, dt: float) -> void:
	match str(m["type"]):
		"gravity":
			var g: Vector3 = m.get("gravity", Vector3(0.0, -9.81, 0.0))
			em.vel[i] += g * dt
		"drag":
			em.vel[i] *= exp(-float(m.get("drag", 1.0)) * dt)
		"curl_noise":
			var scroll: Vector3 = m.get("scroll", Vector3.ZERO)
			em.vel[i] += curl_lite(em.pos[i] + scroll * em.time, float(m.get("frequency", 0.5))) * (float(m.get("strength", 1.0)) * dt)
		"vortex":
			var center: Vector3 = m.get("center", Vector3.ZERO)
			var axis: Vector3 = (m.get("axis", Vector3.UP) as Vector3).normalized()
			var r: Vector3 = em.pos[i] - center
			var tg: Vector3 = axis.cross(r)
			var tl: float = tg.length()
			if tl > 0.0001:
				em.vel[i] += tg / tl * (float(m.get("strength", 1.0)) * dt)
			var pull: float = float(m.get("pull", 0.0))
			if pull != 0.0:
				var rr: Vector3 = r - axis * r.dot(axis)
				var rl: float = rr.length()
				if rl > 0.0:
					em.vel[i] -= rr / rl * (pull * dt)
		"color_over_life":
			var u: float = clampf(em.age[i] / maxf(em.life[i], 0.0001), 0.0, 1.0)
			em.col[i] = em.base_col[i] * _curve_color(m["stops"], u)
		"size_over_life":
			var us: float = clampf(em.age[i] / maxf(em.life[i], 0.0001), 0.0, 1.0)
			em.size[i] = em.base_size[i] * _curve_float(m["stops"], us)
		"collide_plane":
			var n: Vector3 = (m.get("normal", Vector3.UP) as Vector3).normalized()
			var d: float = n.dot(em.pos[i]) - float(m.get("offset", 0.0))
			var vn: float = n.dot(em.vel[i])
			if d < 0.0 and vn < 0.0:
				em.pos[i] -= n * d
				var nv: Vector3 = n * vn
				var tv: Vector3 = (em.vel[i] - nv) * (1.0 - float(m.get("friction", 0.0)))
				em.vel[i] = tv - nv * float(m.get("restitution", 0.5))
				if int(m["_slot"]) >= 0:
					em.events.append({"slot": int(m["_slot"]), "pos": em.pos[i], "vel": em.vel[i]})
		"kill_below_plane":
			var kn: Vector3 = (m.get("normal", Vector3.UP) as Vector3).normalized()
			if kn.dot(em.pos[i]) - float(m.get("offset", 0.0)) < 0.0:
				em.age[i] = em.life[i] + 1.0


## Reference kernel: one pass per particle, same order as the compute shader main().
func kernel_cpu(em: Em, dt: float) -> void:
	var update_mods: Array = em.plan["update"]
	var post_mods: Array = em.plan["post"]
	var route_death: bool = bool(em.plan["route_death"])
	for i in em.count:
		em.age[i] += dt
		for m_v in update_mods:
			_apply_module(em, m_v, i, dt)
		em.pos[i] += em.vel[i] * dt
		for m_v in post_mods:
			_apply_module(em, m_v, i, dt)
		if route_death and em.age[i] >= em.life[i]:
			em.events.append({"slot": 0, "pos": em.pos[i], "vel": em.vel[i]})


# ---- device path (UNVERIFIED on hardware) ------------------------------------

func _build_gpu(em: Em, emitter_asset_source: String) -> bool:
	var src: RDShaderSource = RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = emitter_asset_source.trim_prefix("#[compute]\n")
	var spirv: RDShaderSPIRV = _rd.shader_compile_spirv_from_source(src)
	if spirv == null or spirv.compile_error_compute != "":
		return false
	em.shader = _rd.shader_create_from_spirv(spirv)
	if not em.shader.is_valid():
		return false
	em.pipeline = _rd.compute_pipeline_create(em.shader)
	em.particle_buf = _rd.storage_buffer_create(em.cap * BYTES_PER_PARTICLE)
	em.event_buf = _rd.storage_buffer_create(EVENT_HEADER_BYTES + em.cap * 2 * EVENT_BYTES)
	var u0: RDUniform = RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u0.binding = 0
	u0.add_id(em.particle_buf)
	var u1: RDUniform = RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u1.binding = 1
	u1.add_id(em.event_buf)
	em.uniform_set = _rd.uniform_set_create([u0, u1], em.shader, 0)
	return em.pipeline.is_valid() and em.uniform_set.is_valid()


## Runs the update kernel on the device. Returns false (caller falls back to CPU) on any failure.
func _step_gpu(em: Em, dt: float) -> bool:
	if _rd == null or em.gpu_failed:
		return false
	if not em.pipeline.is_valid():
		var source: String = _source_for(em)
		if source.is_empty() or not _build_gpu(em, source):
			em.gpu_failed = true
			_free_em(em)
			return false
	var floats: PackedFloat32Array = PackedFloat32Array()
	floats.resize(em.count * FLOATS_PER_PARTICLE)
	for i in em.count:
		var o: int = i * FLOATS_PER_PARTICLE
		floats[o] = em.pos[i].x
		floats[o + 1] = em.pos[i].y
		floats[o + 2] = em.pos[i].z
		floats[o + 3] = em.age[i]
		floats[o + 4] = em.vel[i].x
		floats[o + 5] = em.vel[i].y
		floats[o + 6] = em.vel[i].z
		floats[o + 7] = em.life[i]
		floats[o + 8] = em.col[i].r
		floats[o + 9] = em.col[i].g
		floats[o + 10] = em.col[i].b
		floats[o + 11] = em.col[i].a
		floats[o + 12] = em.base_col[i].r
		floats[o + 13] = em.base_col[i].g
		floats[o + 14] = em.base_col[i].b
		floats[o + 15] = em.base_col[i].a
		floats[o + 16] = em.size[i]
		floats[o + 17] = em.base_size[i]
	_rd.buffer_update(em.particle_buf, 0, floats.size() * 4, floats.to_byte_array())
	var header: PackedByteArray = PackedByteArray()
	header.resize(EVENT_HEADER_BYTES)
	header.encode_u32(0, 0)
	header.encode_u32(4, em.cap * 2)
	_rd.buffer_update(em.event_buf, 0, EVENT_HEADER_BYTES, header)
	var push: PackedByteArray = PackedByteArray()
	push.resize(16)
	push.encode_float(0, dt)
	push.encode_float(4, em.time)
	push.encode_u32(8, em.count)
	push.encode_u32(12, 0)
	var groups: int = ceili(float(em.count) / float(LOCAL_SIZE))
	var list: int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, em.pipeline)
	_rd.compute_list_bind_uniform_set(list, em.uniform_set, 0)
	_rd.compute_list_set_push_constant(list, push, push.size())
	_rd.compute_list_dispatch(list, groups, 1, 1)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()
	var out: PackedFloat32Array = _rd.buffer_get_data(em.particle_buf, 0, em.count * BYTES_PER_PARTICLE).to_float32_array()
	for i in em.count:
		var o: int = i * FLOATS_PER_PARTICLE
		em.pos[i] = Vector3(out[o], out[o + 1], out[o + 2])
		em.age[i] = out[o + 3]
		em.vel[i] = Vector3(out[o + 4], out[o + 5], out[o + 6])
		em.col[i] = Color(out[o + 8], out[o + 9], out[o + 10], out[o + 11])
		em.size[i] = out[o + 16]
	var ev_bytes: PackedByteArray = _rd.buffer_get_data(em.event_buf)
	var ev_count: int = mini(int(ev_bytes.decode_u32(0)), em.cap * 2)
	var ev_floats: PackedFloat32Array = ev_bytes.slice(EVENT_HEADER_BYTES).to_float32_array()
	for k in ev_count:
		var q: int = k * 8
		em.events.append({"slot": int(ev_floats[q + 3]), "pos": Vector3(ev_floats[q], ev_floats[q + 1], ev_floats[q + 2]), "vel": Vector3(ev_floats[q + 4], ev_floats[q + 5], ev_floats[q + 6])})
	return true


var _sources: Dictionary = {}


func _source_for(em: Em) -> String:
	return str(_sources.get(em.ename, ""))


## Registers the source asset used to compile an emitter's device shader (set by create()).
func _remember_sources(system_asset: Dictionary) -> void:
	_sources.clear()
	var defs: Dictionary = system_asset.get("emitters", {"main": system_asset})
	for key in defs.keys():
		_sources[str(key)] = generate_compute_source(defs[key])


func _free_em(em: Em) -> void:
	if _rd == null:
		return
	for rid in [em.uniform_set, em.particle_buf, em.event_buf, em.pipeline, em.shader]:
		if (rid as RID).is_valid():
			_rd.free_rid(rid)
	em.uniform_set = RID()
	em.particle_buf = RID()
	em.event_buf = RID()
	em.pipeline = RID()
	em.shader = RID()


## Frees device resources and the local device. Safe to call repeatedly.
func shutdown() -> void:
	for key in _ems.keys():
		_free_em(_ems[key])
	if _rd != null:
		_rd.free()
		_rd = null
	_gpu_ready = false

