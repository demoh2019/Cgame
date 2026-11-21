extends RefCounted
## Niagara-style data-driven VFX graph runtime (CPU simulation, structure-of-arrays).
##
## An emitter is a Dictionary asset:
##   {"spawn": [modules], "update": [modules], "max_particles": int, "duration": float,
##    "attributes": {custom_float_name: default}, "events": {"death": spec, "collision": spec}}
## A system asset groups emitters: {"emitters": {name: emitter_asset, ...}}.
## An event spec is {"emitter": name, "count": n, "inherit_velocity": 0..1} (or an Array of them);
## it routes a death/collision to a spawn in another emitter of the same system, the CPU analogue
## of Niagara GPU event routing. collide_plane also accepts "on_event" directly.
##
## Spawn modules: spawn_rate, spawn_burst, initial_position_sphere/box/cone, initial_velocity,
## lifetime_random, initial_color, initial_size, initial_attribute.
## Update modules: gravity, drag, curl_noise, vortex, attractor, color_over_life, size_over_life,
## collide_plane, kill_below_plane (the two plane modules run after integration).
##
## Design inspired by Niagara's emitter/module/event-handler model (concepts only, no third-party
## code ported; curl noise uses Godot's FastNoiseLite, MIT). Original implementation, project license.

const POST_MODULES: PackedStringArray = ["collide_plane", "kill_below_plane"]
const EMISSION_MODULES: PackedStringArray = ["spawn_rate", "spawn_burst"]
const OFFSET_A := Vector3(0.0, 0.0, 0.0)
const OFFSET_B := Vector3(31.4, 17.2, 5.9)
const OFFSET_C := Vector3(-12.7, 44.1, 23.3)


class Attr extends RefCounted:
	var data: PackedFloat32Array = PackedFloat32Array()
	var default_value: float = 0.0


class Emitter extends RefCounted:
	var ename: String = ""
	var def: Dictionary = {}
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
	var custom: Dictionary = {}
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var noise: FastNoiseLite = FastNoiseLite.new()
	var time: float = 0.0
	var accum: float = 0.0
	var duration: float = 0.0
	var fired: Dictionary = {}
	var events_in: Array = []
	var out_events: Array = []
	var spawn_mods: Array = []
	var update_mods: Array = []
	var post_mods: Array = []
	var prof: Dictionary = {}
	var budget_left: int = -1
	var total_spawned: int = 0

	func _init(emitter_name: String, definition: Dictionary, seed_value: int) -> void:
		ename = emitter_name
		def = definition
		cap = maxi(int(definition.get("max_particles", 1000)), 1)
		duration = float(definition.get("duration", 0.0))
		pos.resize(cap)
		vel.resize(cap)
		col.resize(cap)
		base_col.resize(cap)
		size.resize(cap)
		base_size.resize(cap)
		age.resize(cap)
		life.resize(cap)
		rng.seed = seed_value
		noise.seed = seed_value
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		var attrs: Dictionary = definition.get("attributes", {})
		for key in attrs.keys():
			var a := Attr.new()
			a.default_value = float(attrs[key])
			a.data.resize(cap)
			custom[str(key)] = a
		var spawn_list: Array = definition.get("spawn", [])
		for i in spawn_list.size():
			spawn_mods.append(_prepare(spawn_list[i], "spawn", i))
		var update_list: Array = definition.get("update", [])
		for i in update_list.size():
			var m: Dictionary = _prepare(update_list[i], "update", i)
			if POST_MODULES.has(str(m["type"])):
				post_mods.append(m)
			else:
				update_mods.append(m)

	func _prepare(src: Dictionary, stage: String, index: int) -> Dictionary:
		var m: Dictionary = src.duplicate()
		m["_key"] = "%s/%s/%d:%s" % [ename, stage, index, str(src.get("type", "?"))]
		m["_idx"] = index
		return m

	func _charge(key: String, t0: int) -> void:
		prof[key] = int(prof.get(key, 0)) + (Time.get_ticks_usec() - t0)

	# ---- lifecycle -------------------------------------------------------

	func tick(dt: float) -> void:
		time += dt
		if count > 0:
			for i in count:
				age[i] += dt
			for m in update_mods:
				var t0: int = Time.get_ticks_usec()
				_update_module(m, dt)
				_charge(str(m["_key"]), t0)
			for i in count:
				pos[i] += vel[i] * dt
			for m in post_mods:
				var t1: int = Time.get_ticks_usec()
				_update_module(m, dt)
				_charge(str(m["_key"]), t1)
			_cull()
		var pending: Array = events_in
		events_in = []
		for ev in pending:
			var inherit: Vector3 = ev["vel"]
			spawn(int(ev["count"]), ev["pos"], inherit)
		for m in spawn_mods:
			var kind: String = str(m["type"])
			if kind == "spawn_rate":
				var t2: int = Time.get_ticks_usec()
				if duration <= 0.0 or time <= duration:
					accum += float(m.get("rate", 10.0)) * dt
					var n: int = int(floor(accum))
					accum -= float(n)
					spawn(n, Vector3.ZERO, Vector3.ZERO)
				_charge(str(m["_key"]), t2)
			elif kind == "spawn_burst":
				var idx: int = int(m["_idx"])
				if not fired.has(idx) and time >= float(m.get("time", 0.0)) + 0.0:
					fired[idx] = true
					spawn(int(m.get("count", 10)), Vector3.ZERO, Vector3.ZERO)

	func spawn_done() -> bool:
		for m in spawn_mods:
			var kind: String = str(m["type"])
			if kind == "spawn_rate" and duration <= 0.0:
				return false
			if kind == "spawn_rate" and time <= duration:
				return false
			if kind == "spawn_burst" and not fired.has(int(m["_idx"])):
				return false
		return true

	func is_finished() -> bool:
		return count == 0 and events_in.is_empty() and spawn_done()

	func queue_event(n: int, p: Vector3, v: Vector3) -> void:
		events_in.append({"count": n, "pos": p, "vel": v})

	func spawn(requested: int, origin: Vector3, inherit: Vector3) -> void:
		var n: int = mini(requested, cap - count)
		if budget_left >= 0:
			n = mini(n, budget_left)
			budget_left -= maxi(n, 0)
		if n <= 0:
			return
		var start: int = count
		count += n
		total_spawned += n
		for i in range(start, count):
			pos[i] = origin
			vel[i] = inherit
			col[i] = Color.WHITE
			size[i] = 1.0
			age[i] = 0.0
			life[i] = 1.0
		for key in custom.keys():
			var a: Attr = custom[key]
			for i in range(start, count):
				a.data[i] = a.default_value
		for m in spawn_mods:
			var kind: String = str(m["type"])
			if EMISSION_MODULES.has(kind):
				continue
			var t0: int = Time.get_ticks_usec()
			_init_module(m, kind, start)
			_charge(str(m["_key"]), t0)
		for i in range(start, count):
			base_col[i] = col[i]
			base_size[i] = size[i]

	func _cull() -> void:
		var i: int = count - 1
		while i >= 0:
			if age[i] >= life[i]:
				_route("death", {}, pos[i], vel[i])
				_remove(i)
			i -= 1

	func _remove(i: int) -> void:
		var last: int = count - 1
		if i != last:
			pos[i] = pos[last]
			vel[i] = vel[last]
			col[i] = col[last]
			base_col[i] = base_col[last]
			size[i] = size[last]
			base_size[i] = base_size[last]
			age[i] = age[last]
			life[i] = life[last]
			for key in custom.keys():
				var a: Attr = custom[key]
				a.data[i] = a.data[last]
		count -= 1

	func _route(kind: String, m: Dictionary, p: Vector3, v: Vector3) -> void:
		var spec: Variant = m.get("on_event", null)
		if spec == null:
			var events: Dictionary = def.get("events", {})
			spec = events.get(kind, null)
		if spec == null:
			return
		if spec is Dictionary:
			_push_event(spec, p, v)
		elif spec is Array:
			for s in spec:
				if s is Dictionary:
					_push_event(s, p, v)

	func _push_event(spec: Dictionary, p: Vector3, v: Vector3) -> void:
		var inherit: float = float(spec.get("inherit_velocity", 0.0))
		out_events.append({"emitter": str(spec.get("emitter", "")), "count": int(spec.get("count", 1)), "pos": p, "vel": v * inherit})

	# ---- random helpers --------------------------------------------------

	func _unit_vector() -> Vector3:
		var z: float = rng.randf_range(-1.0, 1.0)
		var phi: float = rng.randf() * TAU
		var r: float = sqrt(maxf(1.0 - z * z, 0.0))
		return Vector3(r * cos(phi), z, r * sin(phi))

	func _cone_dir(axis: Vector3, half_angle: float) -> Vector3:
		var a: Vector3 = axis.normalized()
		var cos_t: float = lerpf(cos(half_angle), 1.0, rng.randf())
		var sin_t: float = sqrt(maxf(1.0 - cos_t * cos_t, 0.0))
		var phi: float = rng.randf() * TAU
		var helper: Vector3 = Vector3.RIGHT if absf(a.x) < 0.9 else Vector3.UP
		var u: Vector3 = a.cross(helper).normalized()
		var w: Vector3 = a.cross(u)
		return a * cos_t + (u * cos(phi) + w * sin(phi)) * sin_t

	# ---- spawn-stage modules ---------------------------------------------

	func _init_module(m: Dictionary, kind: String, start: int) -> void:
		match kind:
			"initial_position_sphere":
				var radius: float = float(m.get("radius", 1.0))
				var center: Vector3 = m.get("center", Vector3.ZERO)
				var shell: bool = bool(m.get("surface", false))
				for i in range(start, count):
					var r: float = radius if shell else radius * pow(rng.randf(), 1.0 / 3.0)
					pos[i] += center + _unit_vector() * r
			"initial_position_box":
				var ext: Vector3 = m.get("size", Vector3.ONE)
				var center_b: Vector3 = m.get("center", Vector3.ZERO)
				for i in range(start, count):
					pos[i] += center_b + Vector3(rng.randf_range(-0.5, 0.5) * ext.x, rng.randf_range(-0.5, 0.5) * ext.y, rng.randf_range(-0.5, 0.5) * ext.z)
			"initial_position_cone":
				var axis: Vector3 = m.get("axis", Vector3.UP)
				var half: float = deg_to_rad(float(m.get("angle", 30.0)))
				var height: float = float(m.get("height", 1.0))
				var center_c: Vector3 = m.get("center", Vector3.ZERO)
				for i in range(start, count):
					pos[i] += center_c + _cone_dir(axis, half) * (rng.randf() * height)
			"initial_velocity":
				var dir: Vector3 = m.get("direction", Vector3.UP)
				var spread: float = deg_to_rad(float(m.get("spread", 0.0)))
				var smin: float = float(m.get("speed_min", m.get("speed", 1.0)))
				var smax: float = float(m.get("speed_max", m.get("speed", 1.0)))
				var radial: float = float(m.get("radial", 0.0))
				for i in range(start, count):
					var d: Vector3 = _cone_dir(dir, spread) if spread > 0.0 else dir.normalized()
					vel[i] += d * rng.randf_range(smin, smax)
					if radial != 0.0:
						vel[i] += _unit_vector() * radial
			"lifetime_random":
				var lmin: float = float(m.get("min", 1.0))
				var lmax: float = float(m.get("max", 1.0))
				for i in range(start, count):
					life[i] = rng.randf_range(lmin, lmax)
			"initial_color":
				var c0: Color = m.get("color", Color.WHITE)
				var c1: Color = m.get("color_b", c0)
				for i in range(start, count):
					col[i] = c0.lerp(c1, rng.randf())
			"initial_size":
				var s0: float = float(m.get("min", 1.0))
				var s1: float = float(m.get("max", s0))
				for i in range(start, count):
					size[i] = rng.randf_range(s0, s1)
			"initial_attribute":
				var attr_name: String = str(m.get("attribute", ""))
				if custom.has(attr_name):
					var a: Attr = custom[attr_name]
					var v0: float = float(m.get("min", 0.0))
					var v1: float = float(m.get("max", v0))
					for i in range(start, count):
						a.data[i] = rng.randf_range(v0, v1)

	# ---- update-stage modules --------------------------------------------

	func _update_module(m: Dictionary, dt: float) -> void:
		match str(m["type"]):
			"gravity":
				var g: Vector3 = m.get("gravity", Vector3(0.0, -9.81, 0.0))
				var step: Vector3 = g * dt
				for i in count:
					vel[i] += step
			"drag":
				var k: float = exp(-float(m.get("drag", 1.0)) * dt)
				for i in count:
					vel[i] *= k
			"curl_noise":
				var strength: float = float(m.get("strength", 1.0))
				noise.frequency = float(m.get("frequency", 0.5))
				var scroll: Vector3 = m.get("scroll", Vector3.ZERO)
				var shift: Vector3 = scroll * time
				for i in count:
					vel[i] += _curl(pos[i] + shift) * (strength * dt)
			"vortex":
				var center: Vector3 = m.get("center", Vector3.ZERO)
				var axis: Vector3 = (m.get("axis", Vector3.UP) as Vector3).normalized()
				var vs: float = float(m.get("strength", 1.0))
				var pull: float = float(m.get("pull", 0.0))
				for i in count:
					var r: Vector3 = pos[i] - center
					var tangent: Vector3 = axis.cross(r)
					var len: float = tangent.length()
					if len > 0.0001:
						vel[i] += tangent / len * (vs * dt)
					if pull != 0.0:
						vel[i] -= (r - axis * r.dot(axis)).normalized() * (pull * dt)
			"attractor":
				var target: Vector3 = m.get("position", Vector3.ZERO)
				var power: float = float(m.get("strength", 5.0))
				var reach: float = float(m.get("radius", 0.0))
				for i in count:
					var to: Vector3 = target - pos[i]
					var dist: float = to.length()
					if dist < 0.0001 or (reach > 0.0 and dist > reach):
						continue
					var falloff: float = 1.0 if reach <= 0.0 else 1.0 - dist / reach
					vel[i] += to / dist * (power * falloff * dt)
			"color_over_life":
				var grad: Variant = m.get("gradient", null)
				var stops: Array = m.get("stops", [])
				for i in count:
					var u: float = clampf(age[i] / maxf(life[i], 0.0001), 0.0, 1.0)
					var c: Color = Color.WHITE
					if grad is Gradient:
						c = (grad as Gradient).sample(u)
					elif not stops.is_empty():
						c = _sample_color(stops, u)
					col[i] = base_col[i] * c
			"size_over_life":
				var stops_s: Array = m.get("stops", [])
				if not stops_s.is_empty():
					for i in count:
						var u: float = clampf(age[i] / maxf(life[i], 0.0001), 0.0, 1.0)
						size[i] = base_size[i] * _sample_float(stops_s, u)
			"collide_plane":
				var n: Vector3 = (m.get("normal", Vector3.UP) as Vector3).normalized()
				var offset: float = float(m.get("offset", 0.0))
				var bounce: float = float(m.get("restitution", 0.5))
				var friction: float = float(m.get("friction", 0.0))
				for i in count:
					var d: float = n.dot(pos[i]) - offset
					var vn: float = n.dot(vel[i])
					if d < 0.0 and vn < 0.0:
						pos[i] -= n * d
						var normal_v: Vector3 = n * vn
						var tangent_v: Vector3 = (vel[i] - normal_v) * (1.0 - friction)
						vel[i] = tangent_v - normal_v * bounce
						_route("collision", m, pos[i], vel[i])
			"kill_below_plane":
				var kn: Vector3 = (m.get("normal", Vector3.UP) as Vector3).normalized()
				var koff: float = float(m.get("offset", 0.0))
				for i in count:
					if kn.dot(pos[i]) - koff < 0.0:
						age[i] = life[i] + 1.0

	func _pot(p: Vector3, offset: Vector3) -> float:
		return noise.get_noise_3dv(p + offset)

	func _curl(p: Vector3) -> Vector3:
		var e: float = 0.05
		var ex := Vector3(e, 0.0, 0.0)
		var ey := Vector3(0.0, e, 0.0)
		var ez := Vector3(0.0, 0.0, e)
		var dc_dy: float = _pot(p + ey, OFFSET_C) - _pot(p - ey, OFFSET_C)
		var db_dz: float = _pot(p + ez, OFFSET_B) - _pot(p - ez, OFFSET_B)
		var da_dz: float = _pot(p + ez, OFFSET_A) - _pot(p - ez, OFFSET_A)
		var dc_dx: float = _pot(p + ex, OFFSET_C) - _pot(p - ex, OFFSET_C)
		var db_dx: float = _pot(p + ex, OFFSET_B) - _pot(p - ex, OFFSET_B)
		var da_dy: float = _pot(p + ey, OFFSET_A) - _pot(p - ey, OFFSET_A)
		return Vector3(dc_dy - db_dz, da_dz - dc_dx, db_dx - da_dy) / (2.0 * e)

	func _sample_float(stops: Array, u: float) -> float:
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

	func _sample_color(stops: Array, u: float) -> Color:
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


# ---- public API ---------------------------------------------------------

static func create_system(asset: Dictionary, seed_value: int) -> Dictionary:
	var system: Dictionary = {"emitters": {}, "order": [], "profile": {}, "time": 0.0, "budget_left": -1, "seed": seed_value}
	var defs: Dictionary = asset.get("emitters", {})
	var emitters: Dictionary = system["emitters"]
	var order: Array = system["order"]
	var idx: int = 0
	for key in defs.keys():
		var emitter_name: String = str(key)
		var em := Emitter.new(emitter_name, defs[key], seed_value * 1000003 + idx * 7919 + 17)
		em.prof = system["profile"]
		emitters[emitter_name] = em
		order.append(emitter_name)
		idx += 1
	return system


## Total live-particle budget for the next tick (-1 = unlimited).
static func set_budget(system: Dictionary, particles_left: int) -> void:
	system["budget_left"] = particles_left


static func tick(system: Dictionary, delta: float) -> void:
	var emitters: Dictionary = system["emitters"]
	for key in system["order"]:
		var em: Emitter = emitters[key]
		em.budget_left = int(system["budget_left"])
		em.tick(delta)
		system["budget_left"] = em.budget_left
		for ev in em.out_events:
			var target: Variant = emitters.get(str(ev["emitter"]), null)
			if target != null:
				(target as Emitter).queue_event(int(ev["count"]), ev["pos"], ev["vel"])
		em.out_events.clear()
	system["time"] = float(system["time"]) + delta


static func particle_count(system: Dictionary, emitter: String) -> int:
	var emitters: Dictionary = system["emitters"]
	if not emitters.has(emitter):
		return 0
	return (emitters[emitter] as Emitter).count


static func total_particles(system: Dictionary) -> int:
	var total: int = 0
	var emitters: Dictionary = system["emitters"]
	for key in emitters.keys():
		total += (emitters[key] as Emitter).count
	return total


static func get_emitter(system: Dictionary, emitter: String) -> Emitter:
	var emitters: Dictionary = system["emitters"]
	return emitters.get(emitter, null) as Emitter


## Copy of one attribute's live range: position, velocity, color, size, age, lifetime or a custom name.
static func attribute(system: Dictionary, emitter: String, attr_name: String) -> Variant:
	var em: Emitter = get_emitter(system, emitter)
	if em == null:
		return null
	match attr_name:
		"position":
			return em.pos.slice(0, em.count)
		"velocity":
			return em.vel.slice(0, em.count)
		"color":
			return em.col.slice(0, em.count)
		"size":
			return em.size.slice(0, em.count)
		"age":
			return em.age.slice(0, em.count)
		"lifetime":
			return em.life.slice(0, em.count)
	if em.custom.has(attr_name):
		var a: Attr = em.custom[attr_name]
		return a.data.slice(0, em.count)
	return null


static func is_finished(system: Dictionary) -> bool:
	var emitters: Dictionary = system["emitters"]
	for key in emitters.keys():
		if not (emitters[key] as Emitter).is_finished():
			return false
	return true
