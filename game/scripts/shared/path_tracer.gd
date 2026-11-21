extends RefCounted
## CPU path tracer for light baking (per-vertex lighting, ambient occlusion) and an offline
## photo/movie render mode, on top of the BVH in bvh.gd.
##
## Technique references (concepts re-implemented, no source text copied):
##  - Peter Shirley, "Ray Tracing in One Weekend" / "The Next Week" / "The Rest of Your Life"
##    (CC0 1.0): https://raytracing.github.io/  -- diffuse bounce, cosine-weighted sampling.
##  - Pharr/Jakob/Humphreys, "Physically Based Rendering" 4th ed. (online, BSD-2 code):
##    https://pbr-book.org/  -- next-event estimation, Russian roulette, path integrator.
##  - Jacco Bikker, BVH/path tracing articles (public domain / ZLIB-style): https://jacco.ompf2.com/
## No Apache-2.0, GPL or LGPL code is included.
##
## Conventions: sun_dir is the direction the sunlight TRAVELS (like a DirectionalLight's forward).
## sun_color is the radiance a white diffuse surface facing the sun returns (irradiance / pi
## already folded in), sky_color is a constant-radiance environment. Output colours are linear.

const Bvh = preload("res://scripts/shared/bvh.gd")

const EPS := 0.001
const FAR := 1.0e20


## Accumulating image state for progressive rendering.
class Progressive extends RefCounted:
	var size: Vector2i
	var sum := PackedVector3Array()
	var samples: int = 0   ## samples per pixel accumulated so far
	var passes: int = 0
	var seed: int = 1

	func _init(p_size: Vector2i, p_seed: int = 1) -> void:
		size = p_size
		seed = p_seed
		sum.resize(maxi(size.x * size.y, 0))

	## Mean linear colour of pixel (x, y).
	func pixel(x: int, y: int) -> Vector3:
		if samples == 0:
			return Vector3.ZERO
		return sum[y * size.x + x] / float(samples)

	## Tone-mapped (clamp + gamma 2.2) RGB8 image of the current estimate.
	func to_image() -> Image:
		var img := Image.create(maxi(size.x, 1), maxi(size.y, 1), false, Image.FORMAT_RGB8)
		for y in size.y:
			for x in size.x:
				var c := pixel(x, y)
				img.set_pixel(x, y, Color(
					pow(clampf(c.x, 0.0, 1.0), 0.4545),
					pow(clampf(c.y, 0.0, 1.0), 0.4545),
					pow(clampf(c.z, 0.0, 1.0), 0.4545)))
		return img


## Light/material description for render_image and accumulate.
static func make_light(sun_dir: Vector3, sun_color: Color, sky_color: Color,
		albedo_per_tri: PackedColorArray = PackedColorArray(), bounces: int = 3) -> Dictionary:
	return {
		"sun_dir": sun_dir, "sun_color": sun_color, "sky_color": sky_color,
		"albedo": albedo_per_tri, "bounces": bounces,
	}


static func _cos_dir(n: Vector3, r1: float, r2: float) -> Vector3:
	var phi := TAU * r1
	var r := sqrt(r2)
	var z := sqrt(maxf(1.0 - r2, 0.0))
	var a := Vector3(1.0, 0.0, 0.0) if absf(n.x) < 0.9 else Vector3(0.0, 1.0, 0.0)
	var t := n.cross(a).normalized()
	var b := n.cross(t)
	return t * (r * cos(phi)) + b * (r * sin(phi)) + n * z


static func _col(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


static func _albedo(albedo: PackedColorArray, tri: int) -> Vector3:
	if tri >= 0 and tri < albedo.size():
		return _col(albedo[tri])
	return Vector3(0.7, 0.7, 0.7)


## Incoming radiance along (o, d) with at most `max_hits` surface interactions shaded
## (sun next-event estimation at each, then a cosine-sampled bounce with Russian roulette).
static func _radiance(bvh: Bvh, o_in: Vector3, d_in: Vector3, rng: RandomNumberGenerator,
		to_sun: Vector3, sun: Vector3, sky: Vector3, albedo: PackedColorArray, max_hits: int) -> Vector3:
	var o := o_in
	var d := d_in
	var thr := Vector3.ONE
	var acc := Vector3.ZERO
	for depth in max_hits + 1:
		var h: Dictionary = bvh.intersect(o, d, FAR)
		var hit: bool = h["hit"]
		if not hit:
			acc += thr * sky
			break
		if depth >= max_hits:
			break
		var tri: int = h["tri"]
		var t: float = h["t"]
		var n: Vector3 = h["normal"]
		var p := o + d * t + n * EPS
		var a := _albedo(albedo, tri)
		var ndl := n.dot(to_sun)
		if ndl > 0.0 and not bvh.occluded(p, to_sun, FAR):
			acc += thr * a * sun * ndl
		thr *= a
		if depth >= 2:
			var q := clampf(maxf(thr.x, maxf(thr.y, thr.z)), 0.05, 0.95)
			if rng.randf() > q:
				break
			thr /= q
		o = p
		d = _cos_dir(n, rng.randf(), rng.randf())
	return acc


## Per-vertex baked lighting for a triangle soup (vertices/normals are per vertex, three per
## triangle; albedo_per_tri has one colour per triangle). Alpha is 1.
static func bake_vertex_lighting(bvh: Bvh, vertices: PackedVector3Array, normals: PackedVector3Array,
		albedo_per_tri: PackedColorArray, sun_dir: Vector3, sun_color: Color, sky_color: Color,
		samples: int, bounces: int, seed: int) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(vertices.size())
	var rng := RandomNumberGenerator.new()
	var to_sun := -sun_dir.normalized()
	var sun := _col(sun_color)
	var sky := _col(sky_color)
	var n_samples := maxi(samples, 1)
	for i in vertices.size():
		var n := normals[i].normalized()
		var p := vertices[i] + n * EPS
		@warning_ignore("integer_division")
		var tri := i / 3
		var a := _albedo(albedo_per_tri, tri)
		rng.seed = seed * 73856093 + i * 19349663 + 1
		var direct := Vector3.ZERO
		var ndl := n.dot(to_sun)
		if ndl > 0.0 and not bvh.occluded(p, to_sun, FAR):
			direct = sun * ndl
		var indirect := Vector3.ZERO
		for s in n_samples:
			var d := _cos_dir(n, rng.randf(), rng.randf())
			indirect += _radiance(bvh, p, d, rng, to_sun, sun, sky, albedo_per_tri, bounces)
		var lit := a * (direct + indirect / float(n_samples))
		out[i] = Color(lit.x, lit.y, lit.z, 1.0)
	return out


## Ambient visibility per vertex: 1.0 fully open, 0.0 fully enclosed within max_dist.
static func bake_ambient_occlusion(bvh: Bvh, vertices: PackedVector3Array, normals: PackedVector3Array,
		samples: int, max_dist: float, seed: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(vertices.size())
	var rng := RandomNumberGenerator.new()
	var n_samples := maxi(samples, 1)
	for i in vertices.size():
		var n := normals[i].normalized()
		var p := vertices[i] + n * EPS
		rng.seed = seed * 73856093 + i * 19349663 + 7
		var blocked := 0
		for s in n_samples:
			var d := _cos_dir(n, rng.randf(), rng.randf())
			if bvh.occluded(p, d, max_dist):
				blocked += 1
		out[i] = 1.0 - float(blocked) / float(n_samples)
	return out


## Adds `spp` samples per pixel to `prog` (call repeatedly for progressive refinement).
## camera looks down its -Z axis; fov_deg is the vertical field of view.
static func accumulate(bvh: Bvh, prog: Progressive, camera: Transform3D, fov_deg: float,
		spp: int, light: Dictionary = {}) -> void:
	var sun_dir: Vector3 = light.get("sun_dir", Vector3(-0.4, -1.0, -0.3))
	var sun := _col(light.get("sun_color", Color(1.0, 0.95, 0.85)))
	var sky := _col(light.get("sky_color", Color(0.25, 0.35, 0.5)))
	var albedo: PackedColorArray = light.get("albedo", PackedColorArray())
	var bounces: int = light.get("bounces", 3)
	var to_sun := -sun_dir.normalized()
	var w := prog.size.x
	var h := prog.size.y
	var aspect := float(w) / float(maxi(h, 1))
	var tan_half := tan(deg_to_rad(fov_deg) * 0.5)
	var rng := RandomNumberGenerator.new()
	var n_spp := maxi(spp, 1)
	for y in h:
		for x in w:
			var idx := y * w + x
			rng.seed = prog.seed * 73856093 + prog.passes * 19349663 + idx * 83492791 + 3
			var col := Vector3.ZERO
			for s in n_spp:
				var u := (2.0 * (float(x) + rng.randf()) / float(w) - 1.0) * aspect * tan_half
				var v := (1.0 - 2.0 * (float(y) + rng.randf()) / float(h)) * tan_half
				var d := (camera.basis * Vector3(u, v, -1.0)).normalized()
				col += _radiance(bvh, camera.origin, d, rng, to_sun, sun, sky, albedo, bounces + 1)
			prog.sum[idx] += col
	prog.samples += n_spp
	prog.passes += 1


## One-shot offline render (photo / movie frame).
static func render_image(bvh: Bvh, camera: Transform3D, fov_deg: float, size: Vector2i, spp: int,
		light: Dictionary = {}, seed: int = 1) -> Image:
	var prog := Progressive.new(size, seed)
	accumulate(bvh, prog, camera, fov_deg, spp, light)
	return prog.to_image()
