@tool
extends Resource
class_name OWHeightmap
## Editable heightfield with a secondary texture-weight channel.
## Indices are (x, z), and terrain is defined in local +X/+Z coordinates.

enum SculptMode { RAISE, LOWER, SMOOTH, FLATTEN }

@export_range(2, 1025, 1) var columns: int = 65
@export_range(2, 1025, 1) var rows: int = 65
@export_range(0.01, 100.0, 0.01) var cell_size: float = 1.0
@export_storage var heights: PackedFloat32Array = PackedFloat32Array()
@export_storage var blend: PackedFloat32Array = PackedFloat32Array()


func ensure_storage() -> void:
	columns = maxi(columns, 2)
	rows = maxi(rows, 2)
	cell_size = maxf(cell_size, 0.01)
	var count := columns * rows
	if heights.size() != count:
		var previous := heights
		heights = PackedFloat32Array()
		heights.resize(count)
		for i in mini(count, previous.size()):
			heights[i] = previous[i]
	if blend.size() != count:
		var previous := blend
		blend = PackedFloat32Array()
		blend.resize(count)
		for i in mini(count, previous.size()):
			blend[i] = previous[i]


func reset(p_columns: int, p_rows: int, p_cell_size: float = 1.0) -> void:
	columns = clampi(p_columns, 2, 1025)
	rows = clampi(p_rows, 2, 1025)
	cell_size = maxf(p_cell_size, 0.01)
	heights = PackedFloat32Array()
	blend = PackedFloat32Array()
	ensure_storage()
	emit_changed()


func _index(x: int, z: int) -> int:
	return z * columns + x


func get_height(x: int, z: int) -> float:
	ensure_storage()
	if x < 0 or z < 0 or x >= columns or z >= rows:
		return 0.0
	return heights[_index(x, z)]


func set_height(x: int, z: int, value: float) -> bool:
	ensure_storage()
	if x < 0 or z < 0 or x >= columns or z >= rows or not is_finite(value):
		return false
	var idx := _index(x, z)
	if is_equal_approx(heights[idx], value):
		return false
	heights[idx] = value
	emit_changed()
	return true


func get_blend(x: int, z: int) -> float:
	ensure_storage()
	if x < 0 or z < 0 or x >= columns or z >= rows:
		return 0.0
	return blend[_index(x, z)]


func get_width() -> float:
	return (maxi(2, columns) - 1) * maxf(cell_size, 0.01)


func get_depth() -> float:
	return (maxi(2, rows) - 1) * maxf(cell_size, 0.01)


func contains(local_x: float, local_z: float) -> bool:
	return local_x >= 0.0 and local_z >= 0.0 and local_x <= get_width() and local_z <= get_depth()


func sample_height(local_x: float, local_z: float) -> float:
	ensure_storage()
	var gx := clampf(local_x / cell_size, 0.0, float(columns - 1))
	var gz := clampf(local_z / cell_size, 0.0, float(rows - 1))
	var x := mini(int(floor(gx)), columns - 2)
	var z := mini(int(floor(gz)), rows - 2)
	var tx := gx - float(x)
	var tz := gz - float(z)
	return lerpf(
		lerpf(heights[_index(x, z)], heights[_index(x + 1, z)], tx),
		lerpf(heights[_index(x, z + 1)], heights[_index(x + 1, z + 1)], tx), tz)


func sample_normal(local_x: float, local_z: float) -> Vector3:
	var offset := maxf(cell_size, 0.01)
	var left := sample_height(local_x - offset, local_z)
	var right := sample_height(local_x + offset, local_z)
	var top := sample_height(local_x, local_z - offset)
	var bottom := sample_height(local_x, local_z + offset)
	return Vector3(left - right, 2.0 * offset, top - bottom).normalized()


func _average_neighborhood(source: PackedFloat32Array, x: int, z: int) -> float:
	var total := 0.0
	var count := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var sx := x + dx
			var sz := z + dz
			if sx >= 0 and sz >= 0 and sx < columns and sz < rows:
				total += source[_index(sx, sz)]
				count += 1
	return total / float(count)


func sculpt(local_x: float, local_z: float, radius: float, amount: float, mode: SculptMode = SculptMode.RAISE, target: float = 0.0) -> bool:
	ensure_storage()
	if radius <= 0.0 or amount <= 0.0 or not is_finite(radius) or not is_finite(amount) or not is_finite(target):
		return false
	var x0 := maxi(0, int(floor((local_x - radius) / cell_size)))
	var z0 := maxi(0, int(floor((local_z - radius) / cell_size)))
	var x1 := mini(columns - 1, int(ceil((local_x + radius) / cell_size)))
	var z1 := mini(rows - 1, int(ceil((local_z + radius) / cell_size)))
	var old := heights.duplicate()
	var changed := false
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var distance := Vector2(x * cell_size - local_x, z * cell_size - local_z).length()
			if distance >= radius:
				continue
			var weight := pow(1.0 - distance / radius, 2.0)
			var idx := _index(x, z)
			var value := old[idx]
			match mode:
				SculptMode.RAISE:
					value += amount * weight
				SculptMode.LOWER:
					value -= amount * weight
				SculptMode.SMOOTH:
					value = lerpf(value, _average_neighborhood(old, x, z), minf(1.0, amount * weight))
				SculptMode.FLATTEN:
					value = lerpf(value, target, minf(1.0, amount * weight))
			if not is_equal_approx(heights[idx], value):
				heights[idx] = value
				changed = true
	if changed:
		emit_changed()
	return changed


func paint(local_x: float, local_z: float, radius: float, amount: float, layer: int = 1) -> bool:
	ensure_storage()
	if radius <= 0.0 or amount <= 0.0 or not is_finite(radius) or not is_finite(amount):
		return false
	var x0 := maxi(0, int(floor((local_x - radius) / cell_size)))
	var z0 := maxi(0, int(floor((local_z - radius) / cell_size)))
	var x1 := mini(columns - 1, int(ceil((local_x + radius) / cell_size)))
	var z1 := mini(rows - 1, int(ceil((local_z + radius) / cell_size)))
	var changed := false
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var distance := Vector2(x * cell_size - local_x, z * cell_size - local_z).length()
			if distance >= radius:
				continue
			var idx := _index(x, z)
			var shift := amount * pow(1.0 - distance / radius, 2.0) * (1.0 if layer == 1 else -1.0)
			var next := clampf(blend[idx] + shift, 0.0, 1.0)
			if not is_equal_approx(blend[idx], next):
				blend[idx] = next
				changed = true
	if changed:
		emit_changed()
	return changed


func erode(iterations: int = 1, talus: float = 0.5, rate: float = 0.25) -> bool:
	## Conservative thermal erosion: height is transferred, not created or removed.
	ensure_storage()
	if iterations <= 0 or rate <= 0.0 or not is_finite(rate) or not is_finite(talus):
		return false
	var changed := false
	for iteration in mini(iterations, 100):
		var original := heights.duplicate()
		var diff := PackedFloat32Array()
		diff.resize(original.size())
		for z in rows:
			for x in columns:
				var idx := _index(x, z)
				var steepest := -1
				var slope := maxf(0.0, talus)
				for offset in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					var nx := x + offset.x
					var nz := z + offset.y
					if nx >= 0 and nz >= 0 and nx < columns and nz < rows:
						var neighbor := _index(nx, nz)
						var gradient := original[idx] - original[neighbor]
						if gradient > slope:
							slope = gradient
							steepest = neighbor
				if steepest >= 0:
					var movement := (slope - maxf(0.0, talus)) * clampf(rate, 0.0, 0.5)
					diff[idx] -= movement
					diff[steepest] += movement
		for i in diff.size():
			if diff[i] != 0.0:
				heights[i] += diff[i]
				changed = true
	if changed:
		emit_changed()
	return changed


func generate_noise(seed_value: int, frequency: float = 0.04, amplitude: float = 8.0, octaves: int = 4) -> void:
	ensure_storage()
	var generator := FastNoiseLite.new()
	generator.seed = seed_value
	generator.frequency = maxf(0.000001, frequency)
	generator.fractal_type = FastNoiseLite.FRACTAL_FBM
	generator.fractal_octaves = clampi(octaves, 1, 10)
	for z in rows:
		for x in columns:
			heights[_index(x, z)] = generator.get_noise_2d(float(x), float(z)) * amplitude
	emit_changed()


func set_snapshots(p_heights: PackedFloat32Array, p_blend: PackedFloat32Array) -> bool:
	ensure_storage()
	if p_heights.size() != columns * rows or p_blend.size() != columns * rows:
		return false
	heights = p_heights.duplicate()
	blend = p_blend.duplicate()
	emit_changed()
	return true