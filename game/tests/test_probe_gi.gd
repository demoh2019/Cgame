extends RefCounted
## L2 SH lighting and adaptive probe-volume GI.

const SHLighting = preload("res://scripts/shared/sh_lighting.gd")
const ProbeVolume = preload("res://scripts/shared/probe_volume.gd")

var _box: AABB = AABB(Vector3(1.5, 2.5, 1.5), Vector3(3.0, 1.0, 3.0))
var _wall: Color = Color(1.0, 0.0, 0.0)


func _world_trace(o: Vector3, d: Vector3) -> Dictionary:
	if _box.has_point(o):
		return {"hit": true, "color": Color.BLACK, "distance": 0.0, "backface": true}
	var best: float = INF
	var col: Color = Color.BLACK
	var h: Variant = _box.intersects_ray(o, d)
	if h != null:
		var hp: Vector3 = h
		best = o.distance_to(hp)
		col = Color(0.03, 0.03, 0.03) if d.y > 0.0 else Color(0.8, 0.8, 0.8)
	if d.x > 0.001:
		var tw: float = (6.0 - o.x) / d.x
		if tw > 0.0 and tw < best:
			best = tw
			col = _wall
	if best == INF:
		return {"hit": false}
	return {"hit": true, "color": col, "distance": best}


func _lum(c: Color) -> float:
	return c.r * 0.3 + c.g * 0.6 + c.b * 0.1


func run(t) -> void:
	t.current = "sh constant light"
	var n: int = 256
	var w: float = 4.0 * PI / float(n)
	var sh := SHLighting.create()
	for i in n:
		sh = SHLighting.accumulate(sh, SHLighting.fibonacci_dir(i, n), Color(0.5 * w, 0.25 * w, 1.0 * w, 0.0))
	for nrm in [Vector3.UP, Vector3.DOWN, Vector3(1, 1, 0).normalized(), Vector3(0.3, -0.7, 0.2).normalized()]:
		var e := SHLighting.evaluate_irradiance(sh, nrm)
		t.near(e.r, 0.5, 0.02, "constant radiance gives constant irradiance r")
		t.near(e.b, 1.0, 0.02, "constant radiance gives constant irradiance b")
	var one := SHLighting.project_direction(Vector3.UP, Color(1, 2, 3))
	t.near(one[0].r, SHLighting.C0, 0.0001, "delta projection DC term")
	t.near(one[1].g, SHLighting.C1 * 2.0, 0.0001, "delta projection y band")

	t.current = "sh directional light"
	var sun_dir := Vector3(0.0, 1.0, 0.0)
	var sky := SHLighting.from_sky(sun_dir, Color(1, 1, 1), Color.BLACK, Color.BLACK, 64)
	var toward := SHLighting.evaluate_irradiance(sky, Vector3.UP)
	var away := SHLighting.evaluate_irradiance(sky, Vector3.DOWN)
	var side := SHLighting.evaluate_irradiance(sky, Vector3.RIGHT)
	t.check(toward.r > 0.8 and toward.r < 1.3, "facing the sun is about the sun irradiance")
	t.check(toward.r > side.r and side.r > away.r - 0.0001, "irradiance falls off away from the sun")
	var mn: float = 1.0
	for i in 200:
		var e2 := SHLighting.evaluate_irradiance(sky, SHLighting.fibonacci_dir(i, 200))
		mn = minf(mn, minf(e2.r, minf(e2.g, e2.b)))
	t.check(mn >= 0.0, "irradiance never negative (ringing clamped)")
	var a := SHLighting.from_sky(Vector3.ZERO, Color.BLACK, Color(1, 1, 1), Color(1, 1, 1), 32)
	var b2 := SHLighting.scale(a, 0.0)
	var mid := SHLighting.lerp_sh(a, b2, 0.5)
	t.near(SHLighting.evaluate_irradiance(mid, Vector3.UP).r, 0.5, 0.02, "lerp halves the light")
	t.near(SHLighting.evaluate_irradiance(SHLighting.add(a, a), Vector3.UP).r, 2.0, 0.04, "add doubles the light")
	var rot := SHLighting.rotate(sky, Basis(Vector3.FORWARD, PI * 0.5))
	var rotated_n := Basis(Vector3.FORWARD, PI * 0.5) * Vector3.UP
	t.near(SHLighting.evaluate_irradiance(rot, rotated_n).r, toward.r, 0.05, "rotation moves the lobe")

	t.current = "adaptive placement"
	var dense := ProbeVolume.new()
	dense.build(AABB(Vector3.ZERO, Vector3(8, 2, 8)), 2.0,
		func(c: Vector3) -> float: return 1.0 if c.x < 4.0 else 0.0)
	var left: int = 0
	var right: int = 0
	for i in dense.probe_count():
		var px: float = dense.probe_position(i).x
		if px < 3.9:
			left += 1
		elif px > 4.1:
			right += 1
	t.check(left > right * 2, "dense half holds many more probes")
	var flat := ProbeVolume.new()
	flat.build(AABB(Vector3.ZERO, Vector3(8, 2, 8)), 2.0, func(_c: Vector3) -> float: return 0.0)
	t.eq(flat.probe_count(), 5 * 2 * 5, "uniform sparse volume has one probe per brick corner")
	t.check(dense.probe_count() > flat.probe_count(), "adaptive volume has extra probes")

	t.current = "baked probes"
	var vol := ProbeVolume.new()
	vol.build(AABB(Vector3.ZERO, Vector3(6, 4, 6)), 1.0, func(_c: Vector3) -> float: return 0.0)
	vol.bake(Callable(self, "_world_trace"), 32, 7)
	var under := vol.sample(Vector3(3, 2, 3), Vector3.UP)
	var open := vol.sample(Vector3(0, 2, 0), Vector3.UP)
	t.check(_lum(under) < _lum(open) * 0.5, "probe under an occluder is darker than an open one")
	var inside_idx: int = vol.find_probe(Vector3(3, 3, 3))
	t.check(inside_idx >= 0 and not vol.is_probe_valid(inside_idx), "probe inside geometry is invalid")
	t.check(vol.is_probe_valid(vol.find_probe(Vector3(3, 2, 3))), "probe below the slab is valid")
	var near_slab := vol.sample(Vector3(3, 2.5, 3), Vector3.UP)
	var direct := SHLighting.evaluate_irradiance(vol.probe_sh(vol.find_probe(Vector3(3, 2, 3))), Vector3.UP)
	t.near(near_slab.r, direct.r, 0.001, "invalid probes are ignored in interpolation")

	t.current = "sampling continuity"
	var prev := vol.sample(Vector3(4.6, 1.5, 5.2), Vector3.RIGHT)
	var worst: float = 0.0
	var span_total: float = 0.0
	for i in range(1, 131):
		var cur := vol.sample(Vector3(4.6 + 0.01 * i, 1.5, 5.2), Vector3.RIGHT)
		worst = maxf(worst, absf(cur.r - prev.r))
		span_total += absf(cur.r - prev.r)
		prev = cur
	t.check(worst < 0.02, "no jumps between probes (worst step %.4f)" % worst)
	t.check(span_total > 0.0, "the field actually varies")

	t.current = "streaming"
	var cells := vol.cells_needed(Vector3(3, 2, 3), 100.0)
	t.eq(cells.size(), 18, "huge radius needs every cell")
	t.check(vol.cells_needed(Vector3(0.1, 0.1, 0.1), 0.5).size() == 1, "tiny radius needs one cell")
	var cell: Vector3i = cells[0]
	var ids := vol.cell_probe_ids(cell)
	var before := vol.probe_sh(ids[0])
	var bytes := vol.unload_cell(cell)
	t.check(not vol.is_cell_resident(cell), "unloaded cell is not resident")
	t.check(vol.probe_sh(ids[0]).is_empty(), "unloaded cell frees probe memory")
	t.check(vol.load_cell(cell, bytes), "cell reloads from bytes")
	var after := vol.probe_sh(ids[0])
	var same: bool = true
	for j in SHLighting.COEFFS:
		if before[j] != after[j]:
			same = false
	t.check(same, "cell round trip preserves SH exactly")
	t.check(not vol.load_cell(cell, PackedByteArray([1, 2, 3])), "malformed cell data is rejected")

	vol.memory_budget_bytes = 9000
	for c in cells:
		vol.touch_cell(c)
	var first: Vector3i = cells[0]
	var last: Vector3i = cells[cells.size() - 1]
	var evicted: int = vol.enforce_budget()
	t.check(evicted > 0, "budget forces evictions")
	t.check(vol.resident_bytes() <= 9000, "resident memory within budget")
	t.check(vol.is_cell_resident(last), "most recently used cell survives")
	t.check(not vol.is_cell_resident(first), "least recently used cell is evicted first")
	var fallback := vol.sample(vol.probe_position(vol.cell_probe_ids(first)[0]), Vector3.UP)
	t.check(fallback.r >= 0.0 and is_finite(fallback.r), "sampling an evicted cell falls back safely")
	t.check(vol.request_cell(first), "evicted cell streams back in")
	t.check(vol.is_cell_resident(first) and vol.resident_bytes() <= 9000, "streaming back respects the budget")
	vol.memory_budget_bytes = 0
	for c in cells:
		vol.request_cell(c)

	t.current = "temporal update"
	var probe_p := Vector3(5, 2, 5)
	var red := vol.sample(probe_p, Vector3.RIGHT)
	t.check(red.r > red.g * 3.0, "baked wall light is red")
	_wall = Color(0.0, 1.0, 0.0)
	var count: int = vol.temporal_update(0.5, Callable(self, "_world_trace"), 11)
	t.check(count > 0 and count < vol.probe_count(), "only a subset is updated per frame")
	var half := vol.sample(probe_p, Vector3.RIGHT)
	for f in 23:
		vol.temporal_update(0.5, Callable(self, "_world_trace"), 11)
	var green := vol.sample(probe_p, Vector3.RIGHT)
	t.check(green.g > green.r * 3.0, "radiance cache converges to the changed light")
	t.check(half.r > green.r, "hysteresis blends instead of snapping")
