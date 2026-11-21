extends RefCounted
## Small deterministic rigid-body solver (spheres and boxes) with snapshot / restore, built to be
## stepped inside a rollback netcode loop.
##
## Design sources (ideas and algorithms only, independent 3D implementation, no code copied):
##  - Erin Catto, Box2D-Lite (https://github.com/erincatto/box2d-lite, MIT; earlier releases zlib):
##    sequential-impulse contact solver with accumulated impulses, Baumgarte-style position bias,
##    friction clamped by the normal impulse, SAT box-box with incident-face clipping.
##  - Glenn Fiedler, "Networked Physics" / "Deterministic Lockstep" / "State Synchronization"
##    articles (gafferongames.com): snapshot the full simulation state, restore and resimulate.
##  - Christer Ericson, "Real-Time Collision Detection" (closest points between lines, slab ray test).
## Attribution lines kept here for the permissive Box2D-Lite lineage (Copyright (c) Erin Catto).
##
## Determinism rules: bodies live in an array sorted by id; the sorted sweep breaks ties by id;
## contact pairs are sorted by (id_a, id_b); there is no Dictionary iteration in the step; the
## solver has a fixed iteration count; no warm starting (contacts are rebuilt every step) so the
## complete simulation state is exactly what snapshot() serialises. All math is IEEE double on a
## fixed operation order, so identical inputs give identical bytes on the same build/platform.
##
## Conventions: mass <= 0 means static. A sphere uses size.x as radius; a box uses size as the
## half extents. Contact normals point from body a to body b (a.id < b.id).

enum Shape { SPHERE = 0, BOX = 1 }

const SNAPSHOT_VERSION: int = 1
const BAUMGARTE: float = 0.2
const SLOP: float = 0.005
const MAX_BIAS_SPEED: float = 2.0
const RESTITUTION_THRESHOLD: float = 1.0
const SLEEP_LIN_SQ: float = 0.02
const SLEEP_ANG_SQ: float = 0.05
const SLEEP_TIME: float = 0.5
const LINEAR_DAMPING: float = 0.01
const ANGULAR_DAMPING: float = 0.05
const EDGE_BIAS: float = 0.005
const MAX_CONTACTS_PER_PAIR: int = 8


class Body extends RefCounted:
	var id: int = 0
	var shape: int = 0
	var mass: float = 0.0
	var inv_mass: float = 0.0
	var size: Vector3 = Vector3.ONE
	var friction: float = 0.5
	var restitution: float = 0.0
	var pos: Vector3 = Vector3.ZERO
	var rot: Quaternion = Quaternion.IDENTITY
	var vel: Vector3 = Vector3.ZERO
	var ang: Vector3 = Vector3.ZERO
	var asleep: bool = false
	var sleep_t: float = 0.0
	# Transient (not serialised).
	var inv_i_local: Vector3 = Vector3.ZERO
	var inv_iw: Basis = Basis.from_scale(Vector3.ZERO)
	var force: Vector3 = Vector3.ZERO
	var torque: Vector3 = Vector3.ZERO
	var lo: Vector3 = Vector3.ZERO
	var hi: Vector3 = Vector3.ZERO
	var index: int = 0

	func is_static() -> bool:
		return inv_mass == 0.0

	func setup_mass() -> void:
		if mass <= 0.0:
			inv_mass = 0.0
			inv_i_local = Vector3.ZERO
			return
		inv_mass = 1.0 / mass
		if shape == Shape.SPHERE:
			var i: float = 0.4 * mass * size.x * size.x
			inv_i_local = Vector3(1.0 / i, 1.0 / i, 1.0 / i)
		else:
			var k: float = mass / 3.0
			inv_i_local = Vector3(1.0 / (k * (size.y * size.y + size.z * size.z)),
				1.0 / (k * (size.x * size.x + size.z * size.z)),
				1.0 / (k * (size.x * size.x + size.y * size.y)))

	func update_derived() -> void:
		if inv_mass == 0.0:
			inv_iw = Basis.from_scale(Vector3.ZERO)
		else:
			var r: Basis = Basis(rot)
			inv_iw = r * Basis.from_scale(inv_i_local) * r.transposed()
		if shape == Shape.SPHERE:
			var e: Vector3 = Vector3(size.x, size.x, size.x)
			lo = pos - e
			hi = pos + e
		else:
			var r2: Basis = Basis(rot)
			var ax: Vector3 = r2.x.abs()
			var ay: Vector3 = r2.y.abs()
			var az: Vector3 = r2.z.abs()
			var e2: Vector3 = ax * size.x + ay * size.y + az * size.z
			lo = pos - e2
			hi = pos + e2


class Contact extends RefCounted:
	var a: Body = null
	var b: Body = null
	var p: Vector3 = Vector3.ZERO
	var n: Vector3 = Vector3.ZERO
	var depth: float = 0.0
	var ra: Vector3 = Vector3.ZERO
	var rb: Vector3 = Vector3.ZERO
	var t1: Vector3 = Vector3.ZERO
	var t2: Vector3 = Vector3.ZERO
	var mn: float = 0.0
	var m1: float = 0.0
	var m2: float = 0.0
	var target: float = 0.0
	var mu: float = 0.0
	var jn: float = 0.0
	var j1: float = 0.0
	var j2: float = 0.0


var gravity: Vector3 = Vector3(0.0, -9.81, 0.0)
var iterations: int = 16
## Optional PhysicsTimeline (duck typed: begin_step/begin_phase/end_phase/end_step).
var timeline: Variant = null
var step_count: int = 0

var bodies: Array[Body] = []
var last_contact_count: int = 0
var last_pair_count: int = 0
var last_sleeping_count: int = 0

var _contacts: Array[Contact] = []


# --- body management -------------------------------------------------------------------------

func add_body(id: int, shape: int, mass: float, position: Vector3, size: Vector3,
		rotation: Quaternion = Quaternion.IDENTITY, friction: float = 0.5, restitution: float = 0.0) -> bool:
	if has_body(id):
		return false
	var b: Body = Body.new()
	b.id = id
	b.shape = shape
	b.mass = maxf(mass, 0.0)
	b.size = size
	b.pos = position
	b.rot = rotation.normalized()
	b.friction = friction
	b.restitution = restitution
	b.setup_mass()
	b.update_derived()
	_insert_sorted(b)
	return true


func remove_body(id: int) -> void:
	var i: int = _find(id)
	if i >= 0:
		bodies.remove_at(i)


func has_body(id: int) -> bool:
	return _find(id) >= 0


func body_ids() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for b in bodies:
		out.append(b.id)
	return out


func body_count() -> int:
	return bodies.size()


func get_body(id: int) -> Body:
	var i: int = _find(id)
	return bodies[i] if i >= 0 else null


func get_position(id: int) -> Vector3:
	var b: Body = get_body(id)
	return b.pos if b != null else Vector3.ZERO


func get_rotation(id: int) -> Quaternion:
	var b: Body = get_body(id)
	return b.rot if b != null else Quaternion.IDENTITY


func get_velocity(id: int) -> Vector3:
	var b: Body = get_body(id)
	return b.vel if b != null else Vector3.ZERO


func is_asleep(id: int) -> bool:
	var b: Body = get_body(id)
	return b != null and b.asleep


func set_velocity(id: int, v: Vector3) -> void:
	var b: Body = get_body(id)
	if b != null and not b.is_static():
		b.vel = v
		_wake(b)


func set_pose(id: int, position: Vector3, rotation: Quaternion) -> void:
	var b: Body = get_body(id)
	if b != null:
		b.pos = position
		b.rot = rotation.normalized()
		b.update_derived()


## Forces / torques apply to the next step() only and are not part of the snapshot.
func apply_force(id: int, f: Vector3) -> void:
	var b: Body = get_body(id)
	if b != null and not b.is_static():
		b.force += f
		_wake(b)


func apply_impulse(id: int, impulse: Vector3) -> void:
	var b: Body = get_body(id)
	if b != null and not b.is_static():
		b.vel += impulse * b.inv_mass
		_wake(b)


func sleeping_count() -> int:
	var n: int = 0
	for b in bodies:
		if b.asleep:
			n += 1
	return n


func _find(id: int) -> int:
	var lo_i: int = 0
	var hi_i: int = bodies.size() - 1
	while lo_i <= hi_i:
		var mid: int = lo_i + ((hi_i - lo_i) >> 1)
		var mid_id: int = bodies[mid].id
		if mid_id == id:
			return mid
		if mid_id < id:
			lo_i = mid + 1
		else:
			hi_i = mid - 1
	return -1


func _insert_sorted(b: Body) -> void:
	var i: int = 0
	while i < bodies.size() and bodies[i].id < b.id:
		i += 1
	bodies.insert(i, b)


func _wake(b: Body) -> void:
	b.asleep = false
	b.sleep_t = 0.0


# --- snapshot / restore ----------------------------------------------------------------------

func snapshot() -> PackedByteArray:
	var sp: StreamPeerBuffer = StreamPeerBuffer.new()
	sp.big_endian = false
	sp.put_32(SNAPSHOT_VERSION)
	sp.put_32(bodies.size())
	sp.put_64(step_count)
	for b in bodies:
		sp.put_32(b.id)
		sp.put_8(b.shape)
		sp.put_8(1 if b.asleep else 0)
		for v in [b.mass, b.size.x, b.size.y, b.size.z, b.friction, b.restitution,
				b.pos.x, b.pos.y, b.pos.z, b.rot.x, b.rot.y, b.rot.z, b.rot.w,
				b.vel.x, b.vel.y, b.vel.z, b.ang.x, b.ang.y, b.ang.z, b.sleep_t]:
			sp.put_double(v)
	return sp.data_array


func restore(bytes: PackedByteArray) -> bool:
	if bytes.size() < 16:
		return false
	var sp: StreamPeerBuffer = StreamPeerBuffer.new()
	sp.big_endian = false
	sp.data_array = bytes
	if sp.get_32() != SNAPSHOT_VERSION:
		return false
	var n: int = sp.get_32()
	step_count = sp.get_64()
	bodies.clear()
	for _i in n:
		var b: Body = Body.new()
		b.id = sp.get_32()
		b.shape = sp.get_u8()
		b.asleep = sp.get_u8() != 0
		b.mass = sp.get_double()
		b.size = Vector3(sp.get_double(), sp.get_double(), sp.get_double())
		b.friction = sp.get_double()
		b.restitution = sp.get_double()
		b.pos = Vector3(sp.get_double(), sp.get_double(), sp.get_double())
		b.rot = Quaternion(sp.get_double(), sp.get_double(), sp.get_double(), sp.get_double())
		b.vel = Vector3(sp.get_double(), sp.get_double(), sp.get_double())
		b.ang = Vector3(sp.get_double(), sp.get_double(), sp.get_double())
		b.sleep_t = sp.get_double()
		b.setup_mass()
		b.update_derived()
		bodies.append(b)
	_contacts.clear()
	return true


func checksum() -> int:
	return hash(snapshot())


# --- stepping --------------------------------------------------------------------------------

func step(dt: float) -> void:
	if timeline != null:
		timeline.begin_step(step_count)
	for i in bodies.size():
		bodies[i].index = i

	_phase_begin("integrate")
	for b in bodies:
		b.update_derived()
		if b.is_static() or b.asleep:
			continue
		b.vel += (gravity + b.force * b.inv_mass) * dt
		b.ang += b.inv_iw * b.torque * dt
		b.vel *= 1.0 / (1.0 + LINEAR_DAMPING * dt)
		b.ang *= 1.0 / (1.0 + ANGULAR_DAMPING * dt)
	_phase_end()

	_phase_begin("broadphase")
	var pairs: Array = _broadphase()
	_phase_end()

	_phase_begin("narrowphase")
	_contacts.clear()
	for pr in pairs:
		_collide(pr[0] as Body, pr[1] as Body)
	_phase_end()

	_phase_begin("solve")
	_solve(dt)
	_phase_end()

	_phase_begin("integrate")
	for b in bodies:
		if b.is_static() or b.asleep:
			continue
		b.pos += b.vel * dt
		var wl: float = b.ang.length()
		if wl > 1e-12:
			b.rot = (Quaternion(b.ang / wl, wl * dt) * b.rot).normalized()
		b.update_derived()
	_update_sleep(dt)
	for b in bodies:
		b.force = Vector3.ZERO
		b.torque = Vector3.ZERO
	_phase_end()

	step_count += 1
	last_pair_count = pairs.size()
	last_contact_count = _contacts.size()
	last_sleeping_count = sleeping_count()
	if timeline != null:
		timeline.end_step({"contacts": last_contact_count, "pairs": last_pair_count,
			"sleeping": last_sleeping_count, "bodies": bodies.size()})


func _phase_begin(name: String) -> void:
	if timeline != null:
		timeline.begin_phase(name)


func _phase_end() -> void:
	if timeline != null:
		timeline.end_phase()


# --- broadphase: sorted sweep on x -----------------------------------------------------------

static func _sweep_less(a: Body, b: Body) -> bool:
	if a.lo.x != b.lo.x:
		return a.lo.x < b.lo.x
	return a.id < b.id


static func _pair_less(p: Array, q: Array) -> bool:
	var pa: int = (p[0] as Body).id
	var qa: int = (q[0] as Body).id
	if pa != qa:
		return pa < qa
	return (p[1] as Body).id < (q[1] as Body).id


func _broadphase() -> Array:
	var order: Array[Body] = bodies.duplicate()
	order.sort_custom(_sweep_less)
	var pairs: Array = []
	for i in order.size():
		var a: Body = order[i]
		for j in range(i + 1, order.size()):
			var b: Body = order[j]
			if b.lo.x > a.hi.x:
				break
			if a.is_static() and b.is_static():
				continue
			if (a.asleep or a.is_static()) and (b.asleep or b.is_static()):
				continue
			if a.hi.y < b.lo.y or b.hi.y < a.lo.y or a.hi.z < b.lo.z or b.hi.z < a.lo.z:
				continue
			if a.id < b.id:
				pairs.append([a, b])
			else:
				pairs.append([b, a])
	pairs.sort_custom(_pair_less)
	return pairs


# --- narrowphase -----------------------------------------------------------------------------

func _collide(a: Body, b: Body) -> void:
	var before: int = _contacts.size()
	if a.shape == Shape.SPHERE and b.shape == Shape.SPHERE:
		_sphere_sphere(a, b)
	elif a.shape == Shape.SPHERE:
		_sphere_box(a, b, true)
	elif b.shape == Shape.SPHERE:
		_sphere_box(b, a, false)
	else:
		_box_box(a, b)
	if _contacts.size() > before:
		# Touching an awake body wakes a sleeper.
		if a.asleep and not b.asleep and not b.is_static():
			_wake(a)
		elif b.asleep and not a.asleep and not a.is_static():
			_wake(b)


func _emit(a: Body, b: Body, p: Vector3, n: Vector3, depth: float) -> void:
	var c: Contact = Contact.new()
	c.a = a
	c.b = b
	c.p = p
	c.n = n
	c.depth = depth
	_contacts.append(c)


func _sphere_sphere(a: Body, b: Body) -> void:
	var d: Vector3 = b.pos - a.pos
	var rs: float = a.size.x + b.size.x
	var l2: float = d.length_squared()
	if l2 >= rs * rs:
		return
	var l: float = sqrt(l2)
	var n: Vector3 = d / l if l > 1e-9 else Vector3.UP
	_emit(a, b, a.pos + n * (a.size.x - 0.5 * (rs - l)), n, rs - l)


## sphere_first: true when the sphere is body a of the ordered pair (normal a -> b).
func _sphere_box(s: Body, bx: Body, sphere_first: bool) -> void:
	var basis: Basis = Basis(bx.rot)
	var local: Vector3 = basis.transposed() * (s.pos - bx.pos)
	var h: Vector3 = bx.size
	var clamped: Vector3 = Vector3(clampf(local.x, -h.x, h.x), clampf(local.y, -h.y, h.y), clampf(local.z, -h.z, h.z))
	var n_box_to_sphere: Vector3
	var depth: float
	var q_local: Vector3
	if clamped == local:
		# Centre inside the box: leave through the nearest face.
		var dx: float = h.x - absf(local.x)
		var dy: float = h.y - absf(local.y)
		var dz: float = h.z - absf(local.z)
		q_local = local
		var nl: Vector3
		if dx <= dy and dx <= dz:
			nl = Vector3(signf(local.x) if local.x != 0.0 else 1.0, 0.0, 0.0)
			q_local.x = nl.x * h.x
			depth = dx + s.size.x
		elif dy <= dz:
			nl = Vector3(0.0, signf(local.y) if local.y != 0.0 else 1.0, 0.0)
			q_local.y = nl.y * h.y
			depth = dy + s.size.x
		else:
			nl = Vector3(0.0, 0.0, signf(local.z) if local.z != 0.0 else 1.0)
			q_local.z = nl.z * h.z
			depth = dz + s.size.x
		n_box_to_sphere = basis * nl
	else:
		var delta: Vector3 = local - clamped
		var l2: float = delta.length_squared()
		if l2 >= s.size.x * s.size.x:
			return
		var l: float = sqrt(l2)
		q_local = clamped
		n_box_to_sphere = basis * (delta / l)
		depth = s.size.x - l
	var point: Vector3 = bx.pos + basis * q_local
	if sphere_first:
		_emit(s, bx, point, -n_box_to_sphere, depth)
	else:
		_emit(bx, s, point, n_box_to_sphere, depth)


static func _extent(axes: Array[Vector3], half: Vector3, dir: Vector3) -> float:
	return half.x * absf(axes[0].dot(dir)) + half.y * absf(axes[1].dot(dir)) + half.z * absf(axes[2].dot(dir))


static func _clip(poly: Array[Vector3], n: Vector3, d: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var cnt: int = poly.size()
	for i in cnt:
		var p: Vector3 = poly[i]
		var q: Vector3 = poly[(i + 1) % cnt]
		var dp: float = p.dot(n) - d
		var dq: float = q.dot(n) - d
		if dp <= 0.0:
			out.append(p)
		if (dp < 0.0 and dq > 0.0) or (dp > 0.0 and dq < 0.0):
			out.append(p.lerp(q, dp / (dp - dq)))
	return out


func _box_box(a: Body, b: Body) -> void:
	var ba: Basis = Basis(a.rot)
	var bb: Basis = Basis(b.rot)
	var ax: Array[Vector3] = [ba.x, ba.y, ba.z]
	var bx: Array[Vector3] = [bb.x, bb.y, bb.z]
	var d: Vector3 = b.pos - a.pos
	var best: float = INF
	var best_kind: int = -1 # 0 face of A, 1 face of B, 2 edge
	var best_i: int = 0
	var best_j: int = 0
	var best_n: Vector3 = Vector3.ZERO
	for i in 3:
		var ov: float = a.size[i] + _extent(bx, b.size, ax[i]) - absf(d.dot(ax[i]))
		if ov < 0.0:
			return
		if ov < best:
			best = ov
			best_kind = 0
			best_i = i
			best_n = ax[i]
	for i in 3:
		var ov: float = b.size[i] + _extent(ax, a.size, bx[i]) - absf(d.dot(bx[i]))
		if ov < 0.0:
			return
		if ov < best:
			best = ov
			best_kind = 1
			best_i = i
			best_n = bx[i]
	var face_best: float = best
	for i in 3:
		for j in 3:
			var cr: Vector3 = ax[i].cross(bx[j])
			var l: float = cr.length()
			if l < 1e-6:
				continue
			var axis: Vector3 = cr / l
			var ov: float = _extent(ax, a.size, axis) + _extent(bx, b.size, axis) - absf(d.dot(axis))
			if ov < 0.0:
				return
			if ov + EDGE_BIAS < face_best and ov + EDGE_BIAS < best:
				best = ov
				best_kind = 2
				best_i = i
				best_j = j
				best_n = axis
	if best_kind < 0:
		return
	var n_ab: Vector3 = best_n
	if n_ab.dot(d) < 0.0:
		n_ab = -n_ab
	if best_kind == 2:
		var pa: Vector3 = a.pos
		var pb: Vector3 = b.pos
		for k in 3:
			if k != best_i:
				pa += ax[k] * (a.size[k] * (1.0 if ax[k].dot(n_ab) > 0.0 else -1.0))
			if k != best_j:
				pb += bx[k] * (b.size[k] * (1.0 if bx[k].dot(n_ab) < 0.0 else -1.0))
		var da: Vector3 = ax[best_i]
		var db: Vector3 = bx[best_j]
		var r: Vector3 = pa - pb
		var bdot: float = da.dot(db)
		var c: float = da.dot(r)
		var f: float = db.dot(r)
		var denom: float = 1.0 - bdot * bdot
		var t: float = (f - bdot * c) / denom
		var s: float = bdot * t - c
		_emit(a, b, ((pa + da * s) + (pb + db * t)) * 0.5, n_ab, best)
		return
	# Face contact: clip the incident face against the reference face side planes.
	var ref_is_a: bool = best_kind == 0
	var ref: Body = a if ref_is_a else b
	var inc: Body = b if ref_is_a else a
	var rax: Array[Vector3] = ax if ref_is_a else bx
	var iax: Array[Vector3] = bx if ref_is_a else ax
	var n_ref: Vector3 = n_ab if ref_is_a else -n_ab
	var ri: int = best_i
	# Incident face: most anti-parallel to the reference normal.
	var ii: int = 0
	var most: float = 0.0
	for k in 3:
		var dd: float = absf(iax[k].dot(n_ref))
		if dd > most + 1e-12:
			most = dd
			ii = k
	var isign: float = -1.0 if iax[ii].dot(n_ref) > 0.0 else 1.0
	var ic: Vector3 = inc.pos + iax[ii] * (isign * inc.size[ii])
	var ja: int = (ii + 1) % 3
	var jb: int = (ii + 2) % 3
	var ua: Vector3 = iax[ja] * inc.size[ja]
	var ub: Vector3 = iax[jb] * inc.size[jb]
	var poly: Array[Vector3] = [ic + ua + ub, ic - ua + ub, ic - ua - ub, ic + ua - ub]
	for k in 3:
		if k == ri:
			continue
		var side: Vector3 = rax[k]
		var base: float = ref.pos.dot(side)
		poly = _clip(poly, side, base + ref.size[k])
		poly = _clip(poly, -side, -base + ref.size[k])
		if poly.is_empty():
			return
	var emitted: int = 0
	for p in poly:
		var dep: float = ref.size[ri] - (p - ref.pos).dot(n_ref)
		if dep < -1e-9:
			continue
		_emit(a, b, p + n_ref * (dep * 0.5), n_ab, maxf(dep, 0.0))
		emitted += 1
		if emitted >= MAX_CONTACTS_PER_PAIR:
			break


# --- solver ----------------------------------------------------------------------------------

static func _eff_mass(c: Contact, dir: Vector3) -> float:
	var ra_n: Vector3 = c.ra.cross(dir)
	var rb_n: Vector3 = c.rb.cross(dir)
	var k: float = c.a.inv_mass + c.b.inv_mass \
		+ dir.dot((c.a.inv_iw * ra_n).cross(c.ra) + (c.b.inv_iw * rb_n).cross(c.rb))
	return 1.0 / k if k > 1e-12 else 0.0


static func _rel_vel(c: Contact) -> Vector3:
	return (c.b.vel + c.b.ang.cross(c.rb)) - (c.a.vel + c.a.ang.cross(c.ra))


static func _apply(c: Contact, impulse: Vector3) -> void:
	c.a.vel -= impulse * c.a.inv_mass
	c.a.ang -= c.a.inv_iw * c.ra.cross(impulse)
	c.b.vel += impulse * c.b.inv_mass
	c.b.ang += c.b.inv_iw * c.rb.cross(impulse)


func _solve(dt: float) -> void:
	for c in _contacts:
		c.ra = c.p - c.a.pos
		c.rb = c.p - c.b.pos
		var n: Vector3 = c.n
		if absf(n.x) >= 0.57735:
			c.t1 = Vector3(n.y, -n.x, 0.0).normalized()
		else:
			c.t1 = Vector3(0.0, n.z, -n.y).normalized()
		c.t2 = n.cross(c.t1)
		c.mn = _eff_mass(c, n)
		c.m1 = _eff_mass(c, c.t1)
		c.m2 = _eff_mass(c, c.t2)
		c.mu = sqrt(c.a.friction * c.b.friction)
		var e: float = maxf(c.a.restitution, c.b.restitution)
		var vn: float = _rel_vel(c).dot(n)
		var bounce: float = -e * vn if vn < -RESTITUTION_THRESHOLD else 0.0
		var bias: float = minf(BAUMGARTE / dt * maxf(c.depth - SLOP, 0.0), MAX_BIAS_SPEED)
		c.target = maxf(bounce, bias)
		c.jn = 0.0
		c.j1 = 0.0
		c.j2 = 0.0
	for _it in iterations:
		for c in _contacts:
			var v: Vector3 = _rel_vel(c)
			var lim: float = c.mu * c.jn
			var l1: float = -c.m1 * v.dot(c.t1)
			var n1: float = clampf(c.j1 + l1, -lim, lim)
			var d1: float = n1 - c.j1
			c.j1 = n1
			var l2: float = -c.m2 * v.dot(c.t2)
			var n2: float = clampf(c.j2 + l2, -lim, lim)
			var d2: float = n2 - c.j2
			c.j2 = n2
			_apply(c, c.t1 * d1 + c.t2 * d2)
			var vn: float = _rel_vel(c).dot(c.n)
			var ln: float = c.mn * (c.target - vn)
			var nn: float = maxf(c.jn + ln, 0.0)
			var dn: float = nn - c.jn
			c.jn = nn
			_apply(c, c.n * dn)


# --- sleeping --------------------------------------------------------------------------------

func _uf_find(parent: PackedInt32Array, x: int) -> int:
	var r: int = x
	while parent[r] != r:
		r = parent[r]
	while parent[x] != r:
		var nx: int = parent[x]
		parent[x] = r
		x = nx
	return r


func _update_sleep(dt: float) -> void:
	var cnt: int = bodies.size()
	var parent: PackedInt32Array = PackedInt32Array()
	parent.resize(cnt)
	for i in cnt:
		parent[i] = i
		var b: Body = bodies[i]
		if b.is_static() or b.asleep:
			continue
		if b.vel.length_squared() < SLEEP_LIN_SQ and b.ang.length_squared() < SLEEP_ANG_SQ:
			b.sleep_t += dt
		else:
			b.sleep_t = 0.0
	for c in _contacts:
		if c.a.is_static() or c.b.is_static():
			continue
		var ra: int = _uf_find(parent, c.a.index)
		var rb: int = _uf_find(parent, c.b.index)
		if ra != rb:
			# Lower index becomes the root: deterministic.
			if ra < rb:
				parent[rb] = ra
			else:
				parent[ra] = rb
	var min_t: PackedFloat64Array = PackedFloat64Array()
	min_t.resize(cnt)
	for i in cnt:
		min_t[i] = INF
	for i in cnt:
		var b: Body = bodies[i]
		if b.is_static() or b.asleep:
			continue
		var r: int = _uf_find(parent, i)
		min_t[r] = minf(min_t[r], b.sleep_t)
	for i in cnt:
		var b: Body = bodies[i]
		if b.is_static() or b.asleep:
			continue
		if min_t[_uf_find(parent, i)] >= SLEEP_TIME:
			b.asleep = true
			b.vel = Vector3.ZERO
			b.ang = Vector3.ZERO


# --- queries ---------------------------------------------------------------------------------

## Ray cast against all bodies. Returns {"hit": bool, "id": int, "t": float, "point": Vector3}.
func raycast(origin: Vector3, dir: Vector3, max_dist: float = 1000.0) -> Dictionary:
	var out: Dictionary = {"hit": false, "id": -1, "t": max_dist, "point": Vector3.ZERO}
	var dl: float = dir.length()
	if dl < 1e-12:
		return out
	var d: Vector3 = dir / dl
	var best: float = max_dist
	for b in bodies:
		var t: float = _ray_body(b, origin, d, best)
		if t >= 0.0 and t < best:
			best = t
			out["hit"] = true
			out["id"] = b.id
			out["t"] = t
			out["point"] = origin + d * t
	return out


static func _ray_body(b: Body, o: Vector3, d: Vector3, max_t: float) -> float:
	if b.shape == Shape.SPHERE:
		var m: Vector3 = o - b.pos
		var bq: float = m.dot(d)
		var cq: float = m.dot(m) - b.size.x * b.size.x
		if cq > 0.0 and bq > 0.0:
			return -1.0
		var disc: float = bq * bq - cq
		if disc < 0.0:
			return -1.0
		var t: float = maxf(-bq - sqrt(disc), 0.0)
		return t if t <= max_t else -1.0
	var basis: Basis = Basis(b.rot)
	var inv: Basis = basis.transposed()
	var lo_p: Vector3 = inv * (o - b.pos)
	var ld: Vector3 = inv * d
	var tmin: float = 0.0
	var tmax: float = max_t
	for i in 3:
		var oi: float = lo_p[i]
		var di: float = ld[i]
		var hi_e: float = b.size[i]
		if absf(di) < 1e-12:
			if oi < -hi_e or oi > hi_e:
				return -1.0
		else:
			var t1: float = (-hi_e - oi) / di
			var t2: float = (hi_e - oi) / di
			if t1 > t2:
				var tmp: float = t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return -1.0
	return tmin
