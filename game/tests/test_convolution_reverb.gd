extends RefCounted
## Partitioned convolution, early reflections and the reverb player.

const Convolver = preload("res://scripts/client/partitioned_convolver.gd")
const EarlyReflections = preload("res://scripts/client/early_reflections.gd")
const Player = preload("res://scripts/client/convolution_reverb_player.gd")
const Bvh = preload("res://scripts/shared/bvh.gd")


func _noise(n: int, seed_value: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		a[i] = rng.randf_range(-1.0, 1.0)
	return a


func _stream(conv: Convolver, x: PackedFloat32Array, bs: int, total: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var pos := 0
	while pos < total:
		var blk := PackedFloat32Array()
		blk.resize(bs)
		for i in bs:
			if pos + i < x.size():
				blk[i] = x[pos + i]
		out.append_array(conv.process(blk))
		pos += bs
	return out


func _max_err(a: PackedFloat32Array, b: PackedFloat32Array, n: int) -> float:
	var worst := 0.0
	for i in n:
		worst = maxf(worst, absf(a[i] - b[i]))
	return worst


func _box_tris(sz: Vector3) -> PackedVector3Array:
	var c: Array[Vector3] = []
	for i in 8:
		c.append(Vector3(sz.x if i & 1 else 0.0, sz.y if i & 2 else 0.0, sz.z if i & 4 else 0.0))
	var quads: Array = [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]
	var tris := PackedVector3Array()
	for q in quads:
		tris.append_array([c[q[0]], c[q[1]], c[q[2]], c[q[0]], c[q[2]], c[q[3]]])
	return tris


func run(t) -> void:
	t.current = "partitioned vs direct convolution"
	for cfg in [[16, 10], [16, 100], [64, 64], [64, 333], [256, 1000], [128, 1]]:
		var bs: int = cfg[0]
		var ir_len: int = cfg[1]
		var ir := _noise(ir_len, 3 + ir_len)
		var x := _noise(bs * 12 + 5, 9)
		var conv := Convolver.new()
		conv.setup(ir, bs)
		var total: int = bs * 12
		var got := _stream(conv, x, bs, total)
		var ref := Convolver.direct_convolve(x, ir)
		t.eq(got.size(), total, "output length bs=%d len=%d" % [bs, ir_len])
		t.check(_max_err(got, ref, total) < 1.0e-4, "matches direct bs=%d len=%d err=%f" % [bs, ir_len, _max_err(got, ref, total)])

	t.current = "streaming continuity"
	var ir2 := _noise(200, 5)
	var x2 := _noise(32 * 20, 6)
	var c_a := Convolver.new()
	c_a.setup(ir2, 32)
	var c_b := Convolver.new()
	c_b.setup(ir2, 32)
	var whole := _stream(c_a, x2, 32, 640)
	var first := _stream(c_b, x2.slice(0, 320), 32, 320)
	var second := _stream(c_b, x2.slice(320), 32, 320)
	first.append_array(second)
	t.check(_max_err(whole, first, 640) < 1.0e-6, "split streaming equals one pass")
	c_b.reset()
	var again := _stream(c_b, x2, 32, 640)
	t.check(_max_err(whole, again, 640) < 1.0e-6, "reset restores initial state")
	t.eq(c_a.process(PackedFloat32Array([1.0])).size(), 0, "wrong block size rejected")
	var tail_conv := Convolver.new()
	tail_conv.setup(PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 1.0]), 4)
	var imp := PackedFloat32Array([1.0, 0.0, 0.0, 0.0])
	var o1 := tail_conv.process(imp)
	var o2 := tail_conv.process(PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))
	t.near(o1[1], 0.0, 1.0e-5, "delay beyond block not early")
	t.near(o2[1], 1.0, 1.0e-4, "tail crosses block boundary (sample 5)")

	t.current = "image sources"
	var room := Vector3(6.0, 4.0, 3.0)
	var src := Vector3(1.5, 1.0, 1.2)
	var lis := Vector3(4.0, 2.5, 1.6)
	var img := EarlyReflections.image_sources_box(room, src, lis, 1, 0.3)
	var first_count := 0
	for r in img:
		if int(r["order"]) == 1:
			first_count += 1
	t.eq(first_count, 6, "box has six first-order images")
	t.eq(img.size(), 7, "order 1 gives direct + 6")
	t.near(float(img[0]["delay_s"]), lis.distance_to(src) / 343.0, 1.0e-6, "direct delay")
	var mirrored: Array[float] = [
		Vector3(-src.x, src.y, src.z).distance_to(lis),
		Vector3(2.0 * room.x - src.x, src.y, src.z).distance_to(lis),
		Vector3(src.x, -src.y, src.z).distance_to(lis),
		Vector3(src.x, 2.0 * room.y - src.y, src.z).distance_to(lis),
		Vector3(src.x, src.y, -src.z).distance_to(lis),
		Vector3(src.x, src.y, 2.0 * room.z - src.z).distance_to(lis)]
	for d in mirrored:
		var found := false
		for r in img:
			if int(r["order"]) == 1 and absf(float(r["delay_s"]) - d / 343.0) < 1.0e-6:
				found = true
		t.check(found, "mirrored image delay %f present" % d)
	var img3 := EarlyReflections.image_sources_box(room, src, lis, 3, 0.3)
	var best: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for r in img3:
		var o: int = int(r["order"])
		best[o] = maxf(best[o], float(r["gain"]))
	t.check(best[0] > best[1] and best[1] > best[2] and best[2] > best[3], "peak gain falls with order")
	var sorted_ok := true
	for i in range(1, img3.size()):
		if float(img3[i]["delay_s"]) < float(img3[i - 1]["delay_s"]):
			sorted_ok = false
	t.check(sorted_ok, "reflections sorted by delay")

	t.current = "ray echogram"
	var bvh := Bvh.new()
	bvh.build(_box_tris(room))
	var echo := EarlyReflections.ray_reflections(bvh, src, lis, 6000, 12, 42, 0.3, 0.5, 0.002, 0.5)
	t.eq(echo.size(), 250, "echogram bins")
	var early_e := 0.0
	var late_e := 0.0
	for i in echo.size():
		if i < 60:
			early_e += echo[i]
		elif i < 120:
			late_e += echo[i]
	t.check(early_e > 0.0 and late_e > 0.0, "echogram has energy")
	t.check(early_e > late_e, "echogram energy decays")
	var echo2 := EarlyReflections.ray_reflections(bvh, src, lis, 6000, 12, 42, 0.3, 0.5, 0.002, 0.5)
	t.check(_max_err(echo, echo2, echo.size()) == 0.0, "ray tracing deterministic per seed")

	t.current = "ir synthesis"
	var ir_img := EarlyReflections.to_ir(img3, 24000, 0.5)
	t.eq(ir_img.size(), 12000, "IR length from seconds")
	var pk := 0.0
	for v in ir_img:
		pk = maxf(pk, absf(v))
	t.near(pk, 1.0, 1.0e-4, "IR peak normalised")
	var d_idx := int(round(lis.distance_to(src) / 343.0 * 24000.0))
	t.check(absf(ir_img[d_idx]) > 0.3, "direct impulse at geometric delay")
	var ir_ray := EarlyReflections.to_ir(EarlyReflections.echogram_to_reflections(echo, 0.002), 24000, 0.3)
	t.eq(ir_ray.size(), 7200, "echogram IR length")

	t.current = "reverb player"
	var pl := Player.new()
	pl.block_size = 64
	pl.wet = 1.0
	var ir3 := _noise(150, 8)
	pl.set_ir(ir3)
	var dry := _noise(64 * 4, 4)
	pl.push_dry(dry)
	t.eq(pl.queued_samples(), 256, "dry queued")
	var rendered := PackedFloat32Array()
	for i in 4:
		rendered.append_array(pl.render_block())
	var ref3 := Convolver.direct_convolve(dry, ir3)
	t.eq(rendered.size(), 256, "four blocks rendered")
	t.check(_max_err(rendered, ref3, 256) < 1.0e-4, "player wet output equals convolution")
	var ring := PackedFloat32Array()
	while true:
		var blk: PackedFloat32Array = pl.render_block()
		if blk.is_empty():
			break
		ring.append_array(blk)
		if ring.size() > 1000:
			break
	t.check(ring.size() > 0 and ring.size() <= 64 * 5, "tail rings out then goes idle")
	pl.free()
