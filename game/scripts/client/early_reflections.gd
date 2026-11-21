extends RefCounted
## Early reflection simulation: image-source method for shoebox rooms and stochastic
## ray tracing (echogram) against arbitrary triangle soups via scripts/shared/bvh.gd.
##
## Method references (algorithms, no code copied): Allen & Berkley, "Image method for
## efficiently simulating small-room acoustics", JASA 65(4), 1979; Krokstad, Strom &
## Sorsdal, "Calculating the acoustical room response by the use of a ray tracing
## technique", J. Sound Vib. 8(1), 1968 (energy histogram / echogram).
## Implementation written from scratch for this project.

const AcousticRooms = preload("res://scripts/client/acoustic_rooms.gd")

const MIN_DISTANCE := 0.1


## Image sources of a box [0,size] (source/listener inside). Reflection amplitude per wall
## bounce is sqrt(1 - absorption); gain also carries 1/distance spreading. Order is the
## total number of wall bounces (0 = direct). Returns Array of
## {delay_s, gain, direction (unit, listener -> image), order, distance}.
static func image_sources_box(room_size: Vector3, source: Vector3, listener: Vector3, order: int, absorption: float, speed: float = 343.0) -> Array:
	var result: Array = []
	var refl: float = sqrt(clampf(1.0 - absorption, 0.0, 1.0))
	var max_order: int = maxi(order, 0)
	for nx in range(-max_order, max_order + 1):
		var rx: int = absi(nx)
		if rx > max_order:
			continue
		var ix: float = _image_axis(nx, room_size.x, source.x)
		for ny in range(-(max_order - rx), max_order - rx + 1):
			var rxy: int = rx + absi(ny)
			var iy: float = _image_axis(ny, room_size.y, source.y)
			var rem: int = max_order - rxy
			for nz in range(-rem, rem + 1):
				var bounces: int = rxy + absi(nz)
				var iz: float = _image_axis(nz, room_size.z, source.z)
				var delta: Vector3 = Vector3(ix, iy, iz) - listener
				var dist: float = delta.length()
				var dir: Vector3 = delta / dist if dist > 0.000001 else Vector3.ZERO
				result.append({
					"delay_s": dist / speed,
					"gain": pow(refl, float(bounces)) / maxf(dist, MIN_DISTANCE),
					"direction": dir,
					"order": bounces,
					"distance": dist,
				})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["delay_s"]) < float(b["delay_s"]))
	return result


static func _image_axis(n: int, length: float, s: float) -> float:
	if n % 2 == 0:
		return float(n) * length + s
	return float(n) * length + (length - s)


## Stochastic ray tracing: `rays` uniformly distributed rays leave `source`, bounce up to
## `max_bounces` times specularly off `bvh` triangles (energy scaled by 1 - absorption per
## bounce) and deposit energy into a time histogram whenever a path segment passes within
## `listener_radius` of the listener. Returns the echogram: energy per `bin_s` bin.
static func ray_reflections(bvh: RefCounted, source: Vector3, listener: Vector3, rays: int, max_bounces: int, seed_value: int, absorption: float = 0.3, listener_radius: float = 0.5, bin_s: float = 0.001, max_time_s: float = 0.5, speed: float = 343.0) -> PackedFloat32Array:
	var bins: int = maxi(int(ceil(max_time_s / bin_s)), 1)
	var echo: PackedFloat32Array = PackedFloat32Array()
	echo.resize(bins)
	if rays <= 0:
		return echo
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var keep: float = clampf(1.0 - absorption, 0.0, 1.0)
	var r2: float = listener_radius * listener_radius
	var unit_energy: float = 1.0 / float(rays)
	for _r in rays:
		var dir: Vector3 = _random_dir(rng)
		var origin: Vector3 = source
		var travelled: float = 0.0
		var energy: float = unit_energy
		for bounce in max_bounces + 1:
			var hit: Dictionary = bvh.intersect(origin, dir, 1000.0)
			var seg: float = float(hit["t"]) if bool(hit["hit"]) else 1000.0
			var s: float = clampf((listener - origin).dot(dir), 0.0, seg)
			if (origin + dir * s).distance_squared_to(listener) <= r2:
				var bin: int = int((travelled + s) / speed / bin_s)
				if bin < bins:
					echo[bin] += energy
			if not bool(hit["hit"]):
				break
			travelled += seg
			if travelled / speed >= max_time_s:
				break
			var n: Vector3 = hit["normal"]
			origin = origin + dir * seg
			dir = dir - 2.0 * dir.dot(n) * n
			origin += n * 0.001
			energy *= keep
	return echo


static func _random_dir(rng: RandomNumberGenerator) -> Vector3:
	var z: float = rng.randf_range(-1.0, 1.0)
	var a: float = rng.randf_range(0.0, TAU)
	var rr: float = sqrt(maxf(1.0 - z * z, 0.0))
	return Vector3(rr * cos(a), rr * sin(a), z)


## Converts an echogram to reflection entries (gain = sqrt(energy) at bin centre).
static func echogram_to_reflections(echo: PackedFloat32Array, bin_s: float) -> Array:
	var result: Array = []
	for i in echo.size():
		if echo[i] > 0.0:
			result.append({"delay_s": (float(i) + 0.5) * bin_s, "gain": sqrt(echo[i]), "direction": Vector3.ZERO, "order": 1})
	return result


## Builds a mono IR: early reflections as fractionally delayed impulses plus a late
## diffuse tail from AcousticRooms.impulse_response (faded in after `late_start_s`).
## Result is peak-normalised to 1 and exactly sample_rate * length_s samples long.
static func to_ir(reflections: Array, sample_rate: int, length_s: float, rt60: Vector3 = Vector3(0.7, 0.6, 0.4), late_start_s: float = 0.04, late_gain: float = 0.25, seed_value: int = 1) -> PackedFloat32Array:
	var count: int = maxi(int(length_s * float(sample_rate)), 1)
	var ir: PackedFloat32Array = PackedFloat32Array()
	ir.resize(count)
	var early_peak: float = 0.0
	for r in reflections:
		var pos: float = float(r["delay_s"]) * float(sample_rate)
		var i0: int = int(floor(pos))
		var frac: float = pos - float(i0)
		var g: float = float(r["gain"])
		if i0 >= 0 and i0 < count:
			ir[i0] += g * (1.0 - frac)
		if i0 + 1 >= 0 and i0 + 1 < count:
			ir[i0 + 1] += g * frac
	for i in count:
		early_peak = maxf(early_peak, absf(ir[i]))
	if early_peak > 0.0:
		for i in count:
			ir[i] /= early_peak
	var tail: PackedFloat32Array = AcousticRooms.impulse_response(rt60, sample_rate, length_s, seed_value)
	var fade: float = maxf(late_start_s * float(sample_rate), 1.0)
	for i in count:
		var w: float = clampf(float(i) / fade, 0.0, 1.0)
		ir[i] += tail[i] * late_gain * w * w
	var peak: float = 0.0
	for i in count:
		peak = maxf(peak, absf(ir[i]))
	if peak > 0.0:
		for i in count:
			ir[i] /= peak
	return ir
