extends RefCounted
## Strand hair: DFTL constraints, shape matching, capsule collision, lag, LOD, culling, mesh.

const HairStrands = preload("res://scripts/client/hair_strands.gd")

const SEGS := 6
const LEN := 0.3
const DT := 1.0 / 60.0


func _make(with_head: bool) -> HairStrands:
	var h := HairStrands.new()
	var roots := PackedVector3Array()
	var normals := PackedVector3Array()
	for ring in 2:
		var elev: float = deg_to_rad(40.0 + 25.0 * float(ring))
		for k in 8:
			var az: float = TAU * float(k) / 8.0
			var n := Vector3(cos(elev) * cos(az), sin(elev), cos(elev) * sin(az))
			roots.append(n * 0.13)
			normals.append(n)
	h.grow_guides(roots, normals, SEGS, LEN)
	if with_head:
		h.add_capsule(Vector3.ZERO, Vector3(0, 0.02, 0), 0.1)
	return h


func _frustum() -> Array[Plane]:
	# Camera at origin looking down -Z, 90 degree FOV, outward normals.
	var s := 1.0 / sqrt(2.0)
	var planes: Array[Plane] = []
	planes.append(Plane(Vector3(0, 0, 1), -0.1))
	planes.append(Plane(Vector3(0, 0, -1), 100.0))
	planes.append(Plane(Vector3(s, 0, s), 0.0))
	planes.append(Plane(Vector3(-s, 0, s), 0.0))
	planes.append(Plane(Vector3(0, s, s), 0.0))
	planes.append(Plane(Vector3(0, -s, s), 0.0))
	return planes


func run(t) -> void:
	t.current = "segment lengths"
	var h := _make(false)
	for i in 120:
		h.step(DT, Transform3D.IDENTITY)
	var worst := 0.0
	for g in h.guide_count:
		var pts := h.guide_points(g)
		for i in range(1, pts.size()):
			worst = maxf(worst, absf(pts[i].distance_to(pts[i - 1]) - h.seg_len))
	t.check(worst < h.seg_len * 0.02, "segment lengths stay within 2%% (worst %.5f)" % worst)

	t.current = "gravity vs shape matching"
	var styled := _make(false)
	var limp := _make(false)
	limp.stiffness = 0.0
	for i in 180:
		styled.step(DT, Transform3D.IDENTITY)
		limp.step(DT, Transform3D.IDENTITY)
	var sd := 0.0
	var ld := 0.0
	var sy := 0.0
	for g in styled.guide_count:
		var tip: int = g * styled.points_per_guide + SEGS
		sd += styled.pos[tip].distance_to(styled.rest[tip])
		ld += limp.pos[tip].distance_to(limp.rest[tip])
		sy += styled.pos[tip].y - styled.rest[tip].y
	sd /= float(styled.guide_count)
	ld /= float(styled.guide_count)
	t.check(sy < 0.0, "hair sags under gravity")
	t.check(sd < LEN * 0.5, "shape matching keeps the tips near rest (%.3f)" % sd)
	t.check(ld > sd * 1.5, "without stiffness hair falls much further (%.3f vs %.3f)" % [ld, sd])

	t.current = "head collision"
	var c := _make(true)
	c.stiffness = 0.0
	c.gravity = Vector3(0, -9.8, 0)
	var minpen := INF
	for i in 240:
		c.step(DT, Transform3D.IDENTITY)
		for g in c.guide_count:
			for k in range(1, c.points_per_guide):
				var p: Vector3 = c.pos[g * c.points_per_guide + k]
				var tt: float = clampf(p.y / 0.02, 0.0, 1.0)
				minpen = minf(minpen, p.distance_to(Vector3(0, 0.02 * tt, 0)) - 0.1)
	t.check(minpen > -0.002, "no point inside the head capsule (min clearance %.4f)" % minpen)

	t.current = "follow the leader lag"
	var m := _make(false)
	var head := Transform3D.IDENTITY
	for i in 60:
		head.origin.x += 0.02
		m.step(DT, head)
	var lag := 0.0
	for g in m.guide_count:
		var tip2: int = g * m.points_per_guide + SEGS
		lag += (head * m.rest[tip2]).x - m.pos[tip2].x
	lag /= float(m.guide_count)
	t.check(lag > 0.003, "tips trail a moving head (lag %.4f)" % lag)
	var root_err: float = m.pos[0].distance_to(head * m.rest[0])
	t.check(root_err < 0.0001, "roots stay pinned to the head")

	t.current = "interpolation"
	var strands := h.render_strands(4, 7)
	t.eq(strands.size(), h.guide_count * 4, "per_guide strands per guide")
	var s0: PackedVector3Array = strands[0]
	t.eq(s0.size(), SEGS + 1, "render strand has all points")
	t.check(s0[SEGS].is_equal_approx(h.pos[SEGS]), "strand 0 is the guide")
	var again := h.render_strands(4, 7)
	var a1: PackedVector3Array = strands[1]
	var a2: PackedVector3Array = again[1]
	t.check(a1[3].is_equal_approx(a2[3]), "same seed, same strands")
	t.check(not a1[SEGS].is_equal_approx(s0[SEGS]), "interpolated strands differ from the guide")

	t.current = "lod"
	var prev_n := -1
	var mono := true
	for i in 101:
		var n: int = h.lod_strand_count(float(i) / 100.0)
		if n < prev_n:
			mono = false
		prev_n = n
	t.check(mono, "LOD count never decreases with coverage")
	t.eq(h.lod_strand_count(0.0), 0, "invisible hair draws nothing")
	t.eq(h.lod_strand_count(1.0), h.max_per_guide, "full coverage uses the maximum")

	t.current = "culling"
	var cu := _make(false)
	var front := Transform3D(Basis.IDENTITY, Vector3(0, 0, -2))
	cu.step(DT, front)
	t.eq(cu.cull(_frustum(), Vector3.ZERO).size(), cu.guide_count, "hair in front is visible")
	var cb := _make(false)
	cb.step(DT, Transform3D(Basis.IDENTITY, Vector3(0, 0, 2)))
	t.eq(cb.cull(_frustum(), Vector3.ZERO).size(), 0, "hair behind the camera is culled")
	var cf := _make(false)
	cf.step(DT, Transform3D(Basis.IDENTITY, Vector3(0, 0, -90)))
	t.eq(cf.cull(_frustum(), Vector3.ZERO).size(), 0, "hair beyond max distance is culled")

	t.current = "mesh"
	var mesh := h.build_mesh(strands, 0.004)
	t.eq(mesh.get_surface_count(), 1, "one surface")
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	t.eq(verts.size(), strands.size() * (SEGS + 1) * 2, "two vertices per strand point")
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	t.eq(idx.size(), strands.size() * SEGS * 6, "two triangles per segment")
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	t.near(nrm[0].length(), 1.0, 0.001, "tangent stored as unit normal")
	t.eq(h.build_mesh([], 0.01).get_surface_count(), 0, "empty input gives an empty mesh")

	t.current = "shader"
	var shader := load("res://assets/shaders/hair_strand.gdshader")
	t.check(shader is Shader, "hair shader loads as a Shader")
	if shader is Shader:
		var code: String = (shader as Shader).code
		t.check(code.contains("cull_disabled") and code.contains("shift_secondary"), "shader declares cull_disabled and dual shifts")
