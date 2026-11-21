extends RefCounted
## XPBD cloth and rope: hanging, collision, self-collision, tearing, attachment, knots.

const XpbdCloth = preload("res://scripts/shared/xpbd_cloth.gd")
const XpbdRope = preload("res://scripts/shared/xpbd_rope.gd")

const DT := 1.0 / 60.0


func _finite(points: PackedVector3Array) -> bool:
	for p in points:
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			return false
	return true


func _hanging_cloth() -> XpbdCloth:
	var cloth := XpbdCloth.new()
	cloth.setup_grid(8, 8, 0.1, Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0)))
	for i in cloth.columns():
		var k := cloth.index_of(i, 0)
		cloth.pin(k, cloth.positions()[k])
	return cloth


func run(t) -> void:
	t.current = "xpbd cloth hanging"
	var cloth := _hanging_cloth()
	t.eq(cloth.particle_count(), 81, "9x9 particles")
	t.check(cloth.triangles().size() == 8 * 8 * 2 * 3, "two triangles per cell")
	for _f in 120:
		cloth.step(DT, 8)
	t.check(_finite(cloth.positions()), "positions stay finite")
	t.check(cloth.max_stretch_error() < 0.1, "constraint lengths near rest after settling (%.3f)" % cloth.max_stretch_error())
	var bottom := cloth.positions()[cloth.index_of(4, 8)]
	t.check(bottom.y < 2.0 - 0.6 and bottom.y > 2.0 - 0.95, "pinned cloth hangs below its top edge")
	var top := cloth.positions()[cloth.index_of(3, 0)]
	t.near(top.y, 2.0, 0.0001, "pinned particle does not move")
	var mesh := cloth.build_mesh()
	t.eq(mesh.get_surface_count(), 1, "mesh has one surface")
	var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	t.eq(normals.size(), 81, "one normal per particle")
	t.near(normals[40].length(), 1.0, 0.001, "normals are unit length")

	t.current = "xpbd cloth sphere collision"
	var drape := XpbdCloth.new()
	var flat := Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0.0, 1.0, 0.0))
	drape.setup_grid(8, 8, 0.1, flat)
	var center := Vector3(0.4, 0.5, 0.4)
	drape.add_sphere(center, 0.3)
	drape.add_plane(Vector3.UP, 0.0)
	for _f in 150:
		drape.step(DT, 8)
	var closest := INF
	for p in drape.positions():
		closest = minf(closest, p.distance_to(center))
	t.check(_finite(drape.positions()), "draped cloth finite")
	t.check(closest >= 0.3 + drape.collision_margin - 0.003, "particles stay outside the sphere (%.4f)" % closest)
	var mid := drape.positions()[drape.index_of(4, 4)]
	t.check(mid.y > 0.7, "cloth rests on top of the sphere")

	t.current = "xpbd cloth self-collision"
	var thickness := 0.05
	var folded := _folded_cloth(thickness, true)
	for _f in 30:
		folded.step(DT, 8)
	var with_sc := _min_contact_distance(folded, thickness)
	t.check(with_sc >= thickness * 0.8, "folded layers keep the thickness (%.4f)" % with_sc)
	var ghost := _folded_cloth(thickness, false)
	for _f in 30:
		ghost.step(DT, 8)
	t.check(_min_contact_distance(ghost, thickness) < thickness * 0.5, "without self-collision the layers interpenetrate")

	t.current = "xpbd cloth tearing"
	var tearing := XpbdCloth.new()
	tearing.setup_grid(6, 6, 0.1, Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0)))
	var span := tearing.columns() - 1
	tearing.pin(tearing.index_of(0, 0), tearing.positions()[tearing.index_of(0, 0)])
	tearing.pin(tearing.index_of(span, 0), tearing.positions()[tearing.index_of(span, 0)] + Vector3(0.5, 0.0, 0.0))
	tearing.tear_threshold = 1.3
	var constraints_before := tearing.constraint_count()
	var stretch_before := tearing.stretch_constraint_count()
	var tris_before := tearing.triangles().size()
	for _f in 30:
		tearing.step(DT, 8)
	t.check(tearing.torn_count > 0, "over-stretched constraints are removed")
	t.check(tearing.constraint_count() < constraints_before, "constraint list shrinks")
	t.check(tearing.stretch_constraint_count() < stretch_before, "stretch constraints removed")
	t.check(tearing.triangles().size() < tris_before, "triangles of torn cells are dropped")
	t.eq(tearing.triangles().size() % 3, 0, "triangle list stays well-formed")
	t.check(_finite(tearing.positions()), "torn cloth stays finite")
	var calm := _hanging_cloth()
	calm.tear_threshold = 1.5
	var calm_count := calm.constraint_count()
	for _f in 60:
		calm.step(DT, 8)
	t.eq(calm.constraint_count(), calm_count, "unstressed cloth does not tear")

	t.current = "xpbd cloth attach"
	var anchor: Array[Vector3] = [Vector3(0.0, 3.0, 0.0)]
	var flag := XpbdCloth.new()
	flag.setup_grid(4, 4, 0.1, Transform3D(Basis.IDENTITY, Vector3(0.0, 3.0, 0.0)))
	flag.attach(0, func() -> Vector3: return anchor[0])
	flag.step(DT, 4)
	t.near(flag.positions()[0].y, 3.0, 0.0001, "attached particle starts at the callable")
	anchor[0] = Vector3(2.0, 4.0, 1.0)
	flag.step(DT, 4)
	t.near(flag.positions()[0].distance_to(Vector3(2.0, 4.0, 1.0)), 0.0, 0.0001, "attached particle follows the callable")
	for _f in 120:
		anchor[0] += Vector3(0.01, 0.0, 0.0)
		flag.step(DT, 8)
	var far := flag.positions()[flag.index_of(4, 4)]
	t.check(far.distance_to(anchor[0]) < 0.4 * 1.5, "rest of the cloth is dragged along")
	t.check(far.x > 2.5, "cloth moved with the anchor")

	t.current = "xpbd rope"
	var rope := XpbdRope.new()
	rope.setup(Vector3(0.0, 3.0, 0.0), Vector3(2.0, 3.0, 0.0), 20)
	rope.pin(0, Vector3(0.0, 3.0, 0.0))
	t.near(rope.length(), 2.0, 0.0001, "initial rope length")
	rope.iterations = 2
	for _f in 180:
		rope.step(DT, 16)
	t.check(_finite(rope.positions()), "rope finite")
	t.check(absf(rope.length() - rope.rest_length()) / rope.rest_length() < 0.05, "rope keeps its length (%.3f)" % rope.length())
	t.check(rope.positions()[20].y < 2.2, "rope end swings down")
	t.near(rope.positions()[0].y, 3.0, 0.0001, "pinned rope end fixed")

	t.current = "xpbd rope plane and sphere"
	var lying := XpbdRope.new()
	lying.setup(Vector3(-1.0, 1.0, 0.0), Vector3(1.0, 1.0, 0.0), 20)
	lying.add_plane(Vector3.UP, 0.0)
	for _f in 200:
		lying.step(DT, 8)
	var lowest := INF
	var highest := -INF
	for p in lying.positions():
		lowest = minf(lowest, p.y)
		highest = maxf(highest, p.y)
	t.check(lowest >= lying.radius - 0.002, "rope does not sink through the plane (%.4f)" % lowest)
	t.check(highest < lying.radius + 0.05, "rope comes to rest on the plane (%.4f)" % highest)
	var draped := XpbdRope.new()
	draped.setup(Vector3(-0.6, 1.0, 0.0), Vector3(0.6, 1.0, 0.0), 24)
	draped.add_sphere(Vector3(0.0, 0.5, 0.0), 0.3)
	for _f in 120:
		draped.step(DT, 8)
	var near_sphere := INF
	for p in draped.positions():
		near_sphere = minf(near_sphere, p.distance_to(Vector3(0.0, 0.5, 0.0)))
	t.check(near_sphere >= 0.3 + draped.radius - 0.003, "rope stays outside the sphere (%.4f)" % near_sphere)

	t.current = "xpbd rope self-collision"
	var crossed := XpbdRope.new()
	crossed.setup_points(_crossed_points())
	crossed.gravity = Vector3.ZERO
	crossed.radius = 0.02
	var before := crossed.min_self_distance()
	t.check(before < 0.01, "crafted rope starts with overlapping strands")
	crossed.self_collision_enabled = true
	for _f in 60:
		crossed.step(DT, 8)
	var after := crossed.min_self_distance()
	t.check(after >= 2.0 * crossed.radius * 0.9, "strands are pushed apart (%.4f)" % after)
	t.check(_finite(crossed.positions()), "self-colliding rope finite")

	t.current = "xpbd rope knots"
	var straight := XpbdRope.new()
	straight.setup(Vector3.ZERO, Vector3(3.0, 0.0, 0.0), 12)
	t.eq(straight.crossing_number(), 0, "straight rope has no crossings")
	t.eq(straight.knot_count(), 0, "straight rope has no knots")
	var loop := XpbdRope.new()
	loop.setup_points(PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(3.0, 0.0, 0.05), Vector3(3.0, 2.0, 0.0),
		Vector3(1.0, 2.0, 0.05), Vector3(1.0, -1.0, 0.0)]))
	t.eq(loop.crossing_number(), 1, "a single loop has one crossing")
	t.eq(loop.knot_count(), 0, "a single loop is not a knot")
	var trefoil := PackedVector3Array()
	var samples := 64
	for k in samples + 1:
		var a := 0.123 + TAU * float(k) / float(samples)
		trefoil.append(Vector3(sin(a) + 2.0 * sin(2.0 * a), cos(a) - 2.0 * cos(2.0 * a), -sin(3.0 * a)))
	var knot := XpbdRope.new()
	knot.setup_points(trefoil)
	t.eq(knot.crossing_number(), 3, "trefoil projection has three crossings")
	t.eq(knot.knot_count(), 1, "trefoil counts as one knot")

	t.current = "xpbd determinism"
	var run_a := _deterministic_run()
	var run_b := _deterministic_run()
	var same := run_a.size() == run_b.size()
	for k in mini(run_a.size(), run_b.size()):
		if run_a[k] != run_b[k]:
			same = false
			break
	t.check(same, "identical setups give identical results")


func _folded_cloth(thickness: float, self_collision: bool) -> XpbdCloth:
	var cloth := XpbdCloth.new()
	cloth.setup_grid(6, 6, 0.1, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)))
	cloth.gravity = Vector3.ZERO
	cloth.thickness = thickness
	cloth.compliance_bend = 100.0 # keep bending from pushing the folded layers apart
	cloth.self_collision_enabled = self_collision
	for j in range(4, cloth.rows()):
		for i in cloth.columns():
			var mirror := cloth.positions()[cloth.index_of(i, 6 - j)]
			cloth.set_particle(cloth.index_of(i, j), mirror + Vector3(0.0, 0.0, 0.01))
	return cloth


## Smallest distance between particles whose rest (flat) distance is at least the thickness.
func _min_contact_distance(cloth: XpbdCloth, thickness: float) -> float:
	var best := INF
	var pts := cloth.positions()
	for a in pts.size():
		for b in range(a + 1, pts.size()):
			var di := float(a % cloth.columns() - b % cloth.columns())
			@warning_ignore("integer_division")
			var dj := float(a / cloth.columns() - b / cloth.columns())
			if sqrt(di * di + dj * dj) * 0.1 < thickness:
				continue
			best = minf(best, pts[a].distance_to(pts[b]))
	return best


func _crossed_points() -> PackedVector3Array:
	var pts := PackedVector3Array()
	for k in 11:
		pts.append(Vector3(-0.5 + 0.1 * k, 0.0, 0.0))
	pts.append(Vector3(0.05, 0.005, 0.4))
	pts.append(Vector3(0.05, 0.005, 0.2))
	pts.append(Vector3(0.05, 0.005, 0.0))
	pts.append(Vector3(0.05, 0.005, -0.2))
	pts.append(Vector3(0.05, 0.005, -0.4))
	return pts


func _deterministic_run() -> PackedVector3Array:
	var cloth := XpbdCloth.new()
	cloth.setup_grid(6, 6, 0.1, Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0.0, 1.0, 0.0)))
	cloth.self_collision_enabled = true
	cloth.wind = Vector3(1.0, 0.0, 0.5)
	cloth.tear_threshold = 2.0
	cloth.add_sphere(Vector3(0.3, 0.5, -0.3), 0.25)
	cloth.pin(0, cloth.positions()[0])
	for _f in 40:
		cloth.step(DT, 6)
	return cloth.positions()
