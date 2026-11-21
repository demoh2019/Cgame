extends RefCounted
## CPU BVH + path tracer: traversal vs brute force, occlusion, baking, determinism, progressive refinement.

const Bvh = preload("res://scripts/shared/bvh.gd")
const PathTracer = preload("res://scripts/shared/path_tracer.gd")


static func _quad(tris: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	tris.append_array(PackedVector3Array([a, b, c, a, c, d]))


## Floor y=0 (20x20), optional wall at x=0 (z -10..10, y 0..4).
static func _floor_scene(with_wall: bool) -> PackedVector3Array:
	var tris := PackedVector3Array()
	_quad(tris, Vector3(-10, 0, -10), Vector3(-10, 0, 10), Vector3(10, 0, 10), Vector3(10, 0, -10))
	if with_wall:
		_quad(tris, Vector3(0, 0, -10), Vector3(0, 4, -10), Vector3(0, 4, 10), Vector3(0, 0, 10))
	return tris


static func _up(n: int) -> PackedVector3Array:
	var arr := PackedVector3Array()
	arr.resize(n)
	arr.fill(Vector3.UP)
	return arr


static func _brute(tris: PackedVector3Array, o: Vector3, d: Vector3, t_max: float) -> float:
	var best := INF
	@warning_ignore("integer_division")
	var n := tris.size() / 3
	for i in n:
		var v0 := tris[i * 3]
		var e1 := tris[i * 3 + 1] - v0
		var e2 := tris[i * 3 + 2] - v0
		var pv := d.cross(e2)
		var det := e1.dot(pv)
		if absf(det) < 0.000000000001:
			continue
		var inv := 1.0 / det
		var tv := o - v0
		var u := tv.dot(pv) * inv
		if u < 0.0 or u > 1.0:
			continue
		var qv := tv.cross(e1)
		var v := d.dot(qv) * inv
		if v < 0.0 or u + v > 1.0:
			continue
		var t := e2.dot(qv) * inv
		if t > Bvh.T_MIN and t < t_max and t < best:
			best = t
	return best


func run(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234

	t.current = "bvh matches brute force"
	var soup := PackedVector3Array()
	for i in 150:
		var c := Vector3(rng.randf_range(-8, 8), rng.randf_range(-8, 8), rng.randf_range(-8, 8))
		for k in 3:
			soup.append(c + Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3)))
	var bvh := Bvh.new()
	bvh.build(soup)
	var mismatches := 0
	var anyhit_mismatch := 0
	var hits := 0
	for r in 250:
		var o := Vector3(rng.randf_range(-12, 12), rng.randf_range(-12, 12), rng.randf_range(-12, 12))
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var t_max := rng.randf_range(2.0, 30.0)
		var want := _brute(soup, o, d, t_max)
		var got: Dictionary = bvh.intersect(o, d, t_max)
		var got_hit: bool = got["hit"]
		var got_t: float = got["t"]
		if got_hit != (want < INF) or (got_hit and absf(got_t - want) > 0.0001):
			mismatches += 1
		if got_hit:
			hits += 1
		if bvh.occluded(o, d, t_max) != (want < INF):
			anyhit_mismatch += 1
	t.eq(mismatches, 0, "closest hit equals brute force on random rays")
	t.eq(anyhit_mismatch, 0, "any-hit query equals brute force")
	t.check(hits > 10, "random rays actually hit geometry")
	var st := bvh.get_stats()
	t.eq(st["triangles"], 150, "stats count triangles")
	t.check(int(st["nodes"]) > 1 and int(st["leaves"]) > 1, "tree is split")
	t.check(float(st["avg_leaf_size"]) <= float(Bvh.FORCE_SPLIT), "leaves stay small")
	t.check(float(st["sah_cost"]) > 0.0, "sah cost reported")
	var one := Bvh.new()
	one.build(PackedVector3Array())
	var none: Dictionary = one.intersect(Vector3.ZERO, Vector3.UP)
	var none_hit: bool = none["hit"]
	t.check(not none_hit and not one.occluded(Vector3.ZERO, Vector3.UP), "empty bvh never hits")

	t.current = "hit record"
	var fl := Bvh.new()
	fl.build(_floor_scene(false))
	var hd: Dictionary = fl.intersect(Vector3(1, 5, 1), Vector3.DOWN)
	var hn: Vector3 = hd["normal"]
	var ht: float = hd["t"]
	t.near(ht, 5.0, 0.0001, "ray hits floor at distance 5")
	t.check(hn.dot(Vector3.UP) > 0.99, "normal faces the ray")
	var miss: Dictionary = fl.intersect(Vector3(1, 5, 1), Vector3.UP)
	var miss_hit: bool = miss["hit"]
	t.check(not miss_hit, "ray pointing away misses")
	t.check(not fl.occluded(Vector3(1, 5, 1), Vector3.DOWN, 3.0), "t_max stops any-hit")

	t.current = "ambient occlusion"
	var corner := Bvh.new()
	corner.build(_floor_scene(true))
	var pts := PackedVector3Array([Vector3(0.2, 0, 0), Vector3(8, 0, 0)])
	var ao := PathTracer.bake_ambient_occlusion(corner, pts, _up(2), 64, 3.0, 5)
	t.check(ao[0] < ao[1] - 0.2, "corner is darker than open floor")
	t.check(ao[1] > 0.95, "open floor is nearly unoccluded")

	t.current = "vertex lighting"
	var tris := _floor_scene(false)
	_quad(tris, Vector3(-3, 1, -3), Vector3(-3, 1, 3), Vector3(3, 1, 3), Vector3(3, 1, -3))
	var scene := Bvh.new()
	scene.build(tris)
	var alb := PackedColorArray()
	for i in 4:
		alb.append(Color(0.8, 0.8, 0.8))
	# Vertex list: a lit point (tri 0) and a shadowed point (tri 0) -- albedo index is vertex / 3.
	var verts := PackedVector3Array([Vector3(7, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 1)])
	var sun_dir := Vector3(0, -1, 0)
	var dark := Color(0, 0, 0)
	var lit := PathTracer.bake_vertex_lighting(scene, verts, _up(3), alb, sun_dir, Color(1, 1, 1), dark, 4, 0, 9)
	t.near(lit[0].r, 0.8, 0.01, "unoccluded vertex receives the full sun")
	t.near(lit[1].r, 0.0, 0.0001, "vertex under the plate gets no sun")
	var bounced := PathTracer.bake_vertex_lighting(scene, verts, _up(3), alb, sun_dir, Color(1, 1, 1), dark, 400, 3, 9)
	t.check(bounced[1].r > 0.003, "bounce light reaches a shadowed vertex")
	t.check(bounced[1].r < lit[0].r, "shadowed vertex stays darker than lit")
	var sky_lit := PathTracer.bake_vertex_lighting(scene, verts, _up(3), alb, sun_dir, dark, Color(1, 1, 1), 64, 0, 9)
	t.check(sky_lit[0].r > 0.7 and sky_lit[1].r < sky_lit[0].r, "sky light is blocked by the plate")

	t.current = "determinism"
	var a := PathTracer.bake_vertex_lighting(scene, verts, _up(3), alb, sun_dir, Color(1, 1, 1), Color(0.3, 0.4, 0.5), 16, 2, 77)
	var b := PathTracer.bake_vertex_lighting(scene, verts, _up(3), alb, sun_dir, Color(1, 1, 1), Color(0.3, 0.4, 0.5), 16, 2, 77)
	var c := PathTracer.bake_vertex_lighting(scene, verts, _up(3), alb, sun_dir, Color(1, 1, 1), Color(0.3, 0.4, 0.5), 16, 2, 78)
	t.check(a == b, "same seed gives identical bake")
	t.check(a != c, "different seed gives a different estimate")

	t.current = "image render"
	var cam := Transform3D(Basis.IDENTITY, Vector3(0, 3, 12)).looking_at(Vector3(0, 0, 0), Vector3.UP)
	var light := PathTracer.make_light(Vector3(-0.3, -1, -0.2), Color(1, 1, 1), Color(0.3, 0.4, 0.6), alb, 1)
	var img := PathTracer.render_image(scene, cam, 50.0, Vector2i(16, 12), 2, light, 3)
	t.eq(img.get_size(), Vector2i(16, 12), "image has requested size")
	t.eq(img.get_format(), Image.FORMAT_RGB8, "image is RGB8")
	var sum := 0.0
	for y in 12:
		for x in 16:
			sum += img.get_pixel(x, y).get_luminance()
	t.check(sum > 1.0, "image is not black")

	t.current = "progressive accumulation"
	var wide := Transform3D(Basis.IDENTITY, Vector3(0, 6, 8)).looking_at(Vector3(0, 0, 0), Vector3.UP)
	var gi := PathTracer.make_light(Vector3(-0.2, -1, -0.3), Color(0.2, 0.2, 0.2), Color(1, 1, 1), alb, 2)
	var size := Vector2i(8, 6)
	var diff_low := _pair_diff(scene, wide, size, gi, 1, 1)
	var diff_high := _pair_diff(scene, wide, size, gi, 1, 24)
	t.check(diff_high < diff_low * 0.6, "more passes shrink noise between independent runs")
	var prog := PathTracer.Progressive.new(size, 4)
	PathTracer.accumulate(scene, prog, wide, 50.0, 1, gi)
	PathTracer.accumulate(scene, prog, wide, 50.0, 1, gi)
	t.eq(prog.passes, 2, "passes counted")
	t.eq(prog.samples, 2, "samples counted")
	t.eq(prog.to_image().get_size(), size, "progressive image size")


## Mean absolute difference between two independent estimates of the same image.
func _pair_diff(scene: Bvh, cam: Transform3D, size: Vector2i, light: Dictionary, spp: int, passes: int) -> float:
	var p1 := PathTracer.Progressive.new(size, 11)
	var p2 := PathTracer.Progressive.new(size, 222)
	for i in passes:
		PathTracer.accumulate(scene, p1, cam, 50.0, spp, light)
		PathTracer.accumulate(scene, p2, cam, 50.0, spp, light)
	var total := 0.0
	for y in size.y:
		for x in size.x:
			total += (p1.pixel(x, y) - p2.pixel(x, y)).length()
	return total / float(size.x * size.y)
