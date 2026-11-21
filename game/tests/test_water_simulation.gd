extends RefCounted
## FFT ocean (Tessendorf) and virtual-pipes shallow water solver.

const FFTOcean = preload("res://scripts/shared/fft_ocean.gd")
const ShallowWater = preload("res://scripts/shared/shallow_water.gd")


func _make_ocean(seed: int) -> FFTOcean:
	var o := FFTOcean.new()
	o.setup(32, 100.0, Vector2(12.0, 5.0), 4.0, seed)
	return o


func run(t) -> void:
	t.current = "fft_1d"
	var re := PackedFloat32Array([1.0, 2.0, -3.0, 0.5, 4.0, -1.0, 0.0, 2.5])
	var im := PackedFloat32Array([0.0, 1.0, 0.5, -2.0, 0.0, 3.0, 1.0, -1.0])
	var re0: PackedFloat32Array = re.duplicate()
	var im0: PackedFloat32Array = im.duplicate()
	FFTOcean.fft_1d(re, im, false)
	FFTOcean.fft_1d(re, im, true)
	var worst: float = 0.0
	for i in re.size():
		worst = maxf(worst, maxf(absf(re[i] - re0[i]), absf(im[i] - im0[i])))
	t.check(worst < 1e-4, "forward+inverse round trip restores signal")
	var cr := PackedFloat32Array([1, 1, 1, 1, 1, 1, 1, 1])
	var ci := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
	FFTOcean.fft_1d(cr, ci, false)
	t.near(cr[0], 8.0, 1e-4, "FFT of constant puts all energy in DC")
	var rest: float = 0.0
	for i in range(1, 8):
		rest += absf(cr[i]) + absf(ci[i])
	t.check(rest < 1e-4, "FFT of constant has no other bins")
	var dr := PackedFloat32Array([1, 0, 0, 0, 0, 0, 0, 0])
	var di := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
	FFTOcean.fft_1d(dr, di, false)
	var flat: bool = true
	for i in 8:
		if absf(dr[i] - 1.0) > 1e-4 or absf(di[i]) > 1e-4:
			flat = false
	t.check(flat, "FFT of a delta is flat")

	t.current = "fft ocean"
	var a := _make_ocean(7)
	var b := _make_ocean(7)
	var c := _make_ocean(8)
	var ha: PackedFloat32Array = a.evaluate(1.5)
	var hb: PackedFloat32Array = b.evaluate(1.5)
	var hc: PackedFloat32Array = c.evaluate(1.5)
	t.eq(ha.size(), 32 * 32, "n*n heights")
	t.check(ha == hb, "same seed is deterministic")
	t.check(ha != hc, "different seed differs")
	var finite: bool = true
	var sum: float = 0.0
	var lo: float = INF
	var hi: float = -INF
	for h in ha:
		if is_nan(h) or is_inf(h):
			finite = false
		sum += h
		lo = minf(lo, h)
		hi = maxf(hi, h)
	t.check(finite, "heights finite")
	t.check(hi - lo > 0.001, "surface has relief")
	t.near(sum / float(ha.size()), 0.0, 0.01, "mean height ~0")
	t.check(a.last_max_imag < 1e-3, "imaginary part ~0 (real field)")
	var h2: PackedFloat32Array = a.evaluate(4.0)
	var diff: float = 0.0
	for i in ha.size():
		diff += absf(ha[i] - h2[i])
	t.check(diff > 0.01, "heights change over time")
	var img: Image = a.displacement_image(2.0)
	t.eq(img.get_width(), 32, "image width")
	t.eq(img.get_height(), 32, "image height")
	t.eq(img.get_format(), Image.FORMAT_RF, "image is RF")

	t.current = "shallow water"
	var flat_t := PackedFloat32Array()
	flat_t.resize(32 * 32)
	var lake := ShallowWater.new()
	lake.setup(32, 32, 1.0, flat_t)
	for y in 32:
		for x in 32:
			lake.add_water(Vector2i(x, y), 1.0)
	for i in 60:
		lake.step(0.05)
	var still: bool = true
	for y in 32:
		for x in 32:
			if absf(lake.depth_at(Vector2i(x, y)) - 1.0) > 1e-4:
				still = false
	t.check(still, "flat lake stays at rest")
	t.near(lake.velocity_at(Vector2i(10, 10)).length(), 0.0, 1e-4, "flat lake has no velocity")

	# Slope descending to +x with a basin on the right.
	var slope := PackedFloat32Array()
	slope.resize(32 * 32)
	for y in 32:
		for x in 32:
			slope[y * 32 + x] = float(31 - x) * 0.2
	var basin := ShallowWater.new()
	basin.setup(32, 32, 1.0, slope)
	for y in range(12, 20):
		basin.add_water(Vector2i(2, y), 1.0)
	var v0: float = basin.total_volume()
	var min_depth: float = 0.0
	for i in 200:
		basin.step(0.05)
		for y in 32:
			for x in 32:
				min_depth = minf(min_depth, basin.depth_at(Vector2i(x, y)))
	t.check(min_depth >= 0.0, "depth never negative")
	t.near(basin.total_volume() / v0, 1.0, 0.001, "volume conserved (closed boundaries)")
	var low_side: float = 0.0
	for y in 32:
		for x in range(20, 32):
			low_side += basin.depth_at(Vector2i(x, y))
	var start_side: float = 0.0
	for y in 32:
		for x in range(0, 6):
			start_side += basin.depth_at(Vector2i(x, y))
	t.check(low_side > start_side, "water flows downhill into the basin")
	t.check(basin.depth_at(Vector2i(0, 15)) < 1.0, "source cell drained")

	# Dam break on flat ground.
	var dam := ShallowWater.new()
	dam.setup(32, 32, 1.0, flat_t)
	for y in 32:
		for x in 16:
			dam.add_water(Vector2i(x, y), 2.0)
	var dv: float = dam.total_volume()
	for i in 80:
		dam.step(0.05)
	t.check(dam.depth_at(Vector2i(22, 16)) > 0.01, "dam break floods the dry side")
	t.check(dam.depth_at(Vector2i(15, 16)) < 2.0, "wet side lowers")
	t.near(dam.total_volume() / dv, 1.0, 0.001, "dam break conserves volume")
	t.check(dam.velocity_at(Vector2i(16, 16)).x > 0.0, "front moves toward the dry side")
