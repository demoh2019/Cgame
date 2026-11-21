extends RefCounted
## Hydraulic/thermal erosion and spline terrain authoring (roads, rivers, bridges).

const HydraulicErosion = preload("res://scripts/shared/hydraulic_erosion.gd")
const TerrainSplines = preload("res://scripts/shared/terrain_splines.gd")

const W := 64
const H := 64


func _slope() -> PackedFloat32Array:
	# Tilted plane with a shallow trench and a little deterministic bumpiness.
	var a := PackedFloat32Array()
	a.resize(W * H)
	for y in H:
		for x in W:
			var trench: float = -2.0 * exp(-pow((float(x) - 32.0) / 5.0, 2.0))
			var bump: float = sin(float(x) * 0.7) * cos(float(y) * 0.5) * 0.3
			a[y * W + x] = 30.0 - float(y) * 0.4 + trench + bump
	return a


func _sum(a: PackedFloat32Array) -> float:
	var s: float = 0.0
	for v in a:
		s += v
	return s


func _mean_abs_diff_lower(before: PackedFloat32Array, after: PackedFloat32Array) -> int:
	var n: int = 0
	for i in before.size():
		if after[i] < before[i] - 0.0001:
			n += 1
	return n


func run(t) -> void:
	t.current = "hydraulic erosion"
	var base: PackedFloat32Array = _slope()
	var snapshot: PackedFloat32Array = base.duplicate()
	var a: PackedFloat32Array = HydraulicErosion.erode(base, W, H, 2000, 7)
	var b: PackedFloat32Array = HydraulicErosion.erode(base, W, H, 2000, 7)
	var c: PackedFloat32Array = HydraulicErosion.erode(base, W, H, 2000, 8)
	t.check(a == b, "same seed gives same result")
	t.check(a != c, "different seed gives different result")
	t.check(base == snapshot, "input array is not mutated")
	t.check(_mean_abs_diff_lower(base, a) > 0, "erosion lowers some cells")
	var finite := true
	for v in a:
		if not is_finite(v):
			finite = false
	t.check(finite, "heights stay finite")
	var before_sum: float = _sum(base)
	t.check(absf(_sum(a) - before_sum) / absf(before_sum) < 0.02, "mass conserved within 2%")
	# Upper reach of the valley: the source zone (sediment settles further downslope).
	var valley_before: float = 0.0
	var valley_after: float = 0.0
	var changed: int = 0
	for y in range(3, 14):
		for x in range(30, 35):
			valley_before += base[y * W + x]
			valley_after += a[y * W + x]
	for i in a.size():
		if absf(a[i] - base[i]) > 0.001:
			changed += 1
	t.check(changed > 100, "droplets reshape many cells")
	t.check(valley_after < valley_before, "valley cells lower on average (channel carved)")

	t.current = "thermal erosion"
	var spike: PackedFloat32Array = _slope()
	spike[32 * W + 32] += 12.0
	var slope_before: float = HydraulicErosion.max_slope(spike, W, H)
	var th: PackedFloat32Array = HydraulicErosion.thermal(spike, W, H, 40, 0.6)
	t.check(HydraulicErosion.max_slope(th, W, H) < slope_before, "thermal reduces max slope")
	t.check(absf(_sum(th) - _sum(spike)) < 0.01 * absf(_sum(spike)), "thermal conserves mass")
	t.check(th[32 * W + 32] < spike[32 * W + 32], "thermal lowers the spike")

	t.current = "terrain splines"
	var ctrl := PackedVector3Array([Vector3(4, 10, 4), Vector3(20, 11, 30), Vector3(40, 9, 36), Vector3(58, 10, 58)])
	var sp: PackedVector3Array = TerrainSplines.catmull_rom(ctrl, 8)
	t.eq(sp.size(), 3 * 8 + 1, "sample count")
	var passes := true
	for i in ctrl.size():
		if not sp[i * 8].is_equal_approx(ctrl[i]):
			passes = false
	t.check(passes, "spline passes through control points")
	t.near(TerrainSplines.distance_to_polyline(Vector2(5, 5), PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])), 5.0, 0.0001, "distance to segment")
	t.near(TerrainSplines.distance_to_polyline(Vector2(15, 0), PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])), 5.0, 0.0001, "distance clamps to endpoint")

	var flat := PackedFloat32Array()
	flat.resize(W * H)
	for i in flat.size():
		flat[i] = 20.0 + float(i % 5) * 0.2
	var road := PackedVector3Array([Vector3(0, 8, 32), Vector3(63, 8, 32)])
	var d: PackedFloat32Array = TerrainSplines.deform(flat, W, H, 1.0, road, 3.0, 4.0, "flatten")
	t.near(d[32 * W + 30], 8.0, 0.001, "flatten sets road height under centre")
	t.eq(d[10 * W + 30], flat[10 * W + 30], "flatten leaves far cells untouched")
	t.check(d[36 * W + 30] > 8.0 and d[36 * W + 30] < flat[36 * W + 30], "flatten blends across the falloff")

	var river := PackedVector3Array([Vector3(0, 20, 32), Vector3(63, 20, 32)])
	var cv: PackedFloat32Array = TerrainSplines.deform(flat, W, H, 1.0, river, 2.0, 4.0, "carve")
	t.check(cv[32 * W + 30] < cv[37 * W + 30], "carved bed lies below the banks")
	t.check(cv[32 * W + 30] <= 19.0 + 0.001, "river centre is depth 1 below the spline")
	t.eq(cv[10 * W + 30], flat[10 * W + 30], "carve leaves far cells untouched")

	var low := PackedFloat32Array()
	low.resize(W * H)
	low.fill(5.0)
	var emb: PackedFloat32Array = TerrainSplines.deform(low, W, H, 1.0, PackedVector3Array([Vector3(0, 8, 32), Vector3(63, 8, 32)]), 2.0, 3.0, "raise")
	t.near(emb[32 * W + 20], 8.0, 0.001, "raise lifts to embankment height")
	t.eq(emb[5 * W + 20], 5.0, "raise leaves far cells untouched")

	t.current = "bridge spans"
	var ravine := PackedFloat32Array()
	ravine.resize(W * H)
	for y in H:
		for x in W:
			ravine[y * W + x] = 10.0 - (8.0 if x >= 24 and x <= 38 else 0.0)
	var line := PackedVector3Array([Vector3(0, 10, 32), Vector3(63, 10, 32)])
	var dense: PackedVector3Array = TerrainSplines.catmull_rom(line, 63)
	var spans: Array = TerrainSplines.bridge_spans(ravine, W, H, 1.0, dense, 2.0)
	t.eq(spans.size(), 1, "one bridge across the ravine")
	if spans.size() == 1:
		var span: Dictionary = spans[0]
		var s0: int = int(span["start"])
		var s1: int = int(span["end"])
		t.check(s0 >= 22 and s0 <= 26 and s1 >= 36 and s1 <= 40, "span covers the ravine")
	t.eq(TerrainSplines.bridge_spans(flat, W, H, 1.0, PackedVector3Array([Vector3(0, 20, 10), Vector3(63, 20, 10)]), 2.0).size(), 0, "no bridge on level ground")
