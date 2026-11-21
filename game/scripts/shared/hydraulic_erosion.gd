extends RefCounted
## Droplet-based hydraulic erosion (Hans Beyer's particle model, as popularised by
## Sebastian Lague) plus a simple thermal/talus pass. Inspired by the erosion
## nodes of World Machine and Gaea. Pure data in, new data out; deterministic per seed.
## Heights are indexed y * width + x. Sediment is conserved: whatever a droplet
## picks up is deposited again (at the latest where it dies).

const DEFAULTS: Dictionary = {
	"inertia": 0.05,
	"capacity": 4.0,
	"deposition": 0.3,
	"erosion": 0.3,
	"evaporation": 0.02,
	"gravity": 4.0,
	"max_lifetime": 30,
	"erosion_radius": 2,
	"min_slope": 0.01,
}


## Returns an eroded copy of `heights`; the input is not modified.
static func erode(heights: PackedFloat32Array, width: int, height: int, droplets: int, seed: int, params: Dictionary = {}) -> PackedFloat32Array:
	var map: PackedFloat32Array = heights.duplicate()
	if width < 3 or height < 3 or heights.size() != width * height:
		return map
	var p: Dictionary = DEFAULTS.duplicate()
	p.merge(params, true)
	var inertia: float = clampf(float(p["inertia"]), 0.0, 0.99)
	var capacity_k: float = float(p["capacity"])
	var deposition_k: float = clampf(float(p["deposition"]), 0.0, 1.0)
	var erosion_k: float = clampf(float(p["erosion"]), 0.0, 1.0)
	var evaporation: float = clampf(float(p["evaporation"]), 0.0, 1.0)
	var gravity: float = float(p["gravity"])
	var max_life: int = int(p["max_lifetime"])
	var radius: int = maxi(1, int(p["erosion_radius"]))
	var min_slope: float = float(p["min_slope"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	for _d in droplets:
		var px: float = rng.randf_range(1.0, float(width) - 2.001)
		var py: float = rng.randf_range(1.0, float(height) - 2.001)
		var dx: float = 0.0
		var dy: float = 0.0
		var speed: float = 1.0
		var water: float = 1.0
		var sediment: float = 0.0
		for _step in max_life:
			var ix: int = int(px)
			var iy: int = int(py)
			var fx: float = px - float(ix)
			var fy: float = py - float(iy)
			var g: Vector3 = _height_and_gradient(map, width, ix, iy, fx, fy)
			dx = dx * inertia - g.x * (1.0 - inertia)
			dy = dy * inertia - g.y * (1.0 - inertia)
			var len: float = sqrt(dx * dx + dy * dy)
			if len < 0.00001:
				break
			dx /= len
			dy /= len
			var nx: float = px + dx
			var ny: float = py + dy
			if nx < 1.0 or nx >= float(width) - 2.0 or ny < 1.0 or ny >= float(height) - 2.0:
				# Leaving the map: drop the load where we stand so mass stays put.
				_deposit(map, width, ix, iy, fx, fy, sediment)
				sediment = 0.0
				break
			var nix: int = int(nx)
			var niy: int = int(ny)
			var new_h: float = _height_and_gradient(map, width, nix, niy, nx - float(nix), ny - float(niy)).z
			var delta_h: float = new_h - g.z
			var cap: float = maxf(-delta_h, min_slope) * speed * water * capacity_k
			if sediment > cap or delta_h > 0.0:
				var amount: float = minf(sediment, delta_h) if delta_h > 0.0 else (sediment - cap) * deposition_k
				sediment -= amount
				_deposit(map, width, ix, iy, fx, fy, amount)
			else:
				var take: float = minf((cap - sediment) * erosion_k, -delta_h)
				sediment += _erode_brush(map, width, height, ix, iy, take, radius)
			speed = sqrt(maxf(speed * speed + delta_h * -gravity, 0.0))
			water *= 1.0 - evaporation
			px = nx
			py = ny
		if sediment > 0.0:
			_deposit(map, width, int(px), int(py), px - floorf(px), py - floorf(py), sediment)
	return map


## Thermal erosion: material slides to lower neighbours where the drop exceeds `talus`
## (height units per cell). Mass conserving. Returns a new array.
static func thermal(heights: PackedFloat32Array, width: int, height: int, iterations: int, talus: float = 0.6) -> PackedFloat32Array:
	var map: PackedFloat32Array = heights.duplicate()
	if width < 3 or height < 3 or heights.size() != width * height:
		return map
	var offsets: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for _i in iterations:
		var next: PackedFloat32Array = map.duplicate()
		for y in height:
			for x in width:
				var i: int = y * width + x
				var h: float = map[i]
				var total: float = 0.0
				var biggest: float = 0.0
				for o in offsets:
					var nx: int = x + o.x
					var ny: int = y + o.y
					if nx < 0 or ny < 0 or nx >= width or ny >= height:
						continue
					var d: float = h - map[ny * width + nx]
					if d > talus:
						total += d - talus
						biggest = maxf(biggest, d - talus)
				if total <= 0.0:
					continue
				# Move at most half the largest excess so neighbours cannot overshoot.
				var move: float = biggest * 0.5
				for o in offsets:
					var nx: int = x + o.x
					var ny: int = y + o.y
					if nx < 0 or ny < 0 or nx >= width or ny >= height:
						continue
					var d: float = h - map[ny * width + nx]
					if d > talus:
						var share: float = move * (d - talus) / total
						next[i] -= share
						next[ny * width + nx] += share
		map = next
	return map


## Largest height difference between 4-neighbours, handy for thermal checks.
static func max_slope(heights: PackedFloat32Array, width: int, height: int) -> float:
	var best: float = 0.0
	for y in height:
		for x in width:
			var h: float = heights[y * width + x]
			if x + 1 < width:
				best = maxf(best, absf(h - heights[y * width + x + 1]))
			if y + 1 < height:
				best = maxf(best, absf(h - heights[(y + 1) * width + x]))
	return best


## Returns Vector3(grad_x, grad_y, height) by bilinear interpolation.
static func _height_and_gradient(map: PackedFloat32Array, width: int, ix: int, iy: int, fx: float, fy: float) -> Vector3:
	var i: int = iy * width + ix
	var h00: float = map[i]
	var h10: float = map[i + 1]
	var h01: float = map[i + width]
	var h11: float = map[i + width + 1]
	var gx: float = (h10 - h00) * (1.0 - fy) + (h11 - h01) * fy
	var gy: float = (h01 - h00) * (1.0 - fx) + (h11 - h10) * fx
	var h: float = h00 * (1.0 - fx) * (1.0 - fy) + h10 * fx * (1.0 - fy) + h01 * (1.0 - fx) * fy + h11 * fx * fy
	return Vector3(gx, gy, h)


static func _deposit(map: PackedFloat32Array, width: int, ix: int, iy: int, fx: float, fy: float, amount: float) -> void:
	var i: int = iy * width + ix
	map[i] += amount * (1.0 - fx) * (1.0 - fy)
	map[i + 1] += amount * fx * (1.0 - fy)
	map[i + width] += amount * (1.0 - fx) * fy
	map[i + width + 1] += amount * fx * fy


## Removes up to `amount` spread over a radius brush; returns what was actually removed.
static func _erode_brush(map: PackedFloat32Array, width: int, height: int, cx: int, cy: int, amount: float, radius: int) -> float:
	if amount <= 0.0:
		return 0.0
	var weight_sum: float = 0.0
	for oy in range(-radius, radius + 1):
		for ox in range(-radius, radius + 1):
			var d2: float = float(ox * ox + oy * oy)
			if d2 > float(radius * radius):
				continue
			var x: int = cx + ox
			var y: int = cy + oy
			if x < 0 or y < 0 or x >= width or y >= height:
				continue
			weight_sum += 1.0 - sqrt(d2) / float(radius + 1)
	if weight_sum <= 0.0:
		return 0.0
	var removed: float = 0.0
	for oy in range(-radius, radius + 1):
		for ox in range(-radius, radius + 1):
			var d2: float = float(ox * ox + oy * oy)
			if d2 > float(radius * radius):
				continue
			var x: int = cx + ox
			var y: int = cy + oy
			if x < 0 or y < 0 or x >= width or y >= height:
				continue
			var w: float = (1.0 - sqrt(d2) / float(radius + 1)) / weight_sum
			var idx: int = y * width + x
			var cut: float = amount * w
			map[idx] -= cut
			removed += cut
	return removed
