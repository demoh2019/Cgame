extends RefCounted
## Chunked, non-destructive terrain editing core.
##
## Concepts ported from (clean-room reimplementation in GDScript, no code copied):
##   - Terrain3D (TokisanGames/Terrain3D), MIT License, (c) Cory Petkovsek, Roope Palmroos,
##     and contributors: region/chunk storage, brush falloff, splat (control map) painting.
##   - Unreal Engine Landscape edit layers (concept only; no source used): ordered height
##     layers with visibility, alpha and blend modes composited over a base heightfield.
##
## Layout: a heightfield of `width` x `height` texels. A chunk covers `chunk_size` cells,
## i.e. chunk (cx, cz) spans texels [cx*cs .. cx*cs+cs] inclusive, so neighbouring chunks
## share a seam row/column. Exports add a 1-texel border for seamless normals.
## Layers store a height delta + alpha; the base heights are never modified.
## Layer property changes (visibility, opacity, blend, order) are not on the undo stack;
## brush strokes and fills are.

enum Blend { ADD, MAX, REPLACE }
enum Brush { RAISE, LOWER, SMOOTH, FLATTEN, NOISE, ERODE }
enum Falloff { LINEAR, SMOOTH, SPHERE, CONSTANT }
enum UndoKind { HEIGHT, SPLAT }

class EditLayer extends RefCounted:
	var id: int = 0
	var name: String = ""
	var visible: bool = true
	var opacity: float = 1.0
	var blend: int = 0
	var delta: PackedFloat32Array = PackedFloat32Array()
	var alpha: PackedFloat32Array = PackedFloat32Array()
	## Texel bounds ever touched (for cheap dirty marking on property changes).
	var bounds: Rect2i = Rect2i()
	var has_bounds: bool = false

class UndoEntry extends RefCounted:
	var kind: int = 0
	var layer_id: int = -1
	var rect: Rect2i = Rect2i()
	var data: PackedFloat32Array = PackedFloat32Array()
	var data2: PackedFloat32Array = PackedFloat32Array()

	func bytes() -> int:
		return (data.size() + data2.size()) * 4

var width: int = 0
var height: int = 0
var chunk_size: int = 16
var chunks_x: int = 0
var chunks_z: int = 0
## Upper bound on undo+redo history memory. Oldest entries are dropped first.
var max_undo_bytes: int = 8 * 1024 * 1024

var _base: PackedFloat32Array = PackedFloat32Array()
var _layers: Array[EditLayer] = []
var _next_layer_id: int = 1

var _splat_count: int = 0
var _splat: PackedFloat32Array = PackedFloat32Array()

var _undo: Array[UndoEntry] = []
var _redo: Array[UndoEntry] = []

var _dirty: Dictionary = {}
var _collision_pending: Dictionary = {}
var _collision_queue: Array[Vector2i] = []


func setup(p_width: int, p_height: int, p_chunk_size: int, base_heights: PackedFloat32Array) -> void:
	width = maxi(2, p_width)
	height = maxi(2, p_height)
	chunk_size = maxi(1, p_chunk_size)
	chunks_x = maxi(1, ceili(float(width - 1) / float(chunk_size)))
	chunks_z = maxi(1, ceili(float(height - 1) / float(chunk_size)))
	_base = PackedFloat32Array()
	_base.resize(width * height)
	if base_heights.size() == width * height:
		_base = base_heights.duplicate()
	_layers.clear()
	_next_layer_id = 1
	_splat_count = 0
	_splat = PackedFloat32Array()
	_undo.clear()
	_redo.clear()
	_dirty.clear()
	_collision_pending.clear()
	_collision_queue.clear()
	_mark_rect_dirty(Rect2i(0, 0, width, height))


func chunk_count() -> int:
	return chunks_x * chunks_z


# ---------------------------------------------------------------- layers

func add_layer(p_name: String, blend: int = Blend.ADD, opacity: float = 1.0) -> int:
	var l := EditLayer.new()
	l.id = _next_layer_id
	_next_layer_id += 1
	l.name = p_name
	l.blend = blend
	l.opacity = opacity
	l.delta.resize(width * height)
	l.alpha.resize(width * height)
	_layers.append(l)
	return l.id


func remove_layer(id: int) -> bool:
	var i := _layer_index(id)
	if i < 0:
		return false
	_mark_layer_dirty(_layers[i])
	_layers.remove_at(i)
	return true


## Moves a layer to `to_index` in the stack (0 = bottom, composited first).
func move_layer(id: int, to_index: int) -> bool:
	var i := _layer_index(id)
	if i < 0:
		return false
	var l := _layers[i]
	_layers.remove_at(i)
	_layers.insert(clampi(to_index, 0, _layers.size()), l)
	_mark_all_layers_dirty()
	return true


func set_layer_visible(id: int, p_visible: bool) -> void:
	var i := _layer_index(id)
	if i >= 0 and _layers[i].visible != p_visible:
		_layers[i].visible = p_visible
		_mark_layer_dirty(_layers[i])


func set_layer_opacity(id: int, p_opacity: float) -> void:
	var i := _layer_index(id)
	if i >= 0:
		_layers[i].opacity = clampf(p_opacity, 0.0, 1.0)
		_mark_layer_dirty(_layers[i])


func set_layer_blend(id: int, blend: int) -> void:
	var i := _layer_index(id)
	if i >= 0:
		_layers[i].blend = blend
		_mark_layer_dirty(_layers[i])


func layer_count() -> int:
	return _layers.size()


## Layer ids from bottom to top.
func layer_ids() -> PackedInt32Array:
	var out := PackedInt32Array()
	for l in _layers:
		out.append(l.id)
	return out


func _layer_index(id: int) -> int:
	for i in _layers.size():
		if _layers[i].id == id:
			return i
	return -1


func _mark_layer_dirty(l: EditLayer) -> void:
	if l.has_bounds:
		_mark_rect_dirty(l.bounds)


func _mark_all_layers_dirty() -> void:
	for l in _layers:
		_mark_layer_dirty(l)


func _grow_bounds(l: EditLayer, rect: Rect2i) -> void:
	if l.has_bounds:
		l.bounds = l.bounds.merge(rect)
	else:
		l.bounds = rect
		l.has_bounds = true


# ---------------------------------------------------------------- compositing

func _blend_texel(h: float, b: float, l: EditLayer, i: int) -> float:
	var d: float = l.delta[i]
	match l.blend:
		Blend.ADD:
			return h + d * l.opacity
		Blend.MAX:
			return lerpf(h, maxf(h, b + d), l.opacity)
		_:
			return lerpf(h, b + d, l.alpha[i] * l.opacity)


func composite_height(x: int, y: int) -> float:
	var cx := clampi(x, 0, width - 1)
	var cy := clampi(y, 0, height - 1)
	var i := cy * width + cx
	var b: float = _base[i]
	var h := b
	for l in _layers:
		if l.visible and l.opacity > 0.0:
			h = _blend_texel(h, b, l, i)
	return h


## Composite heights for `rect` (clipped to the map), row-major, rect.size.x per row.
func composite_region(rect: Rect2i) -> PackedFloat32Array:
	var r := rect.intersection(Rect2i(0, 0, width, height))
	var out := PackedFloat32Array()
	out.resize(maxi(0, r.size.x * r.size.y))
	var k := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := y * width + x
			var b: float = _base[i]
			var h := b
			for l in _layers:
				if l.visible and l.opacity > 0.0:
					h = _blend_texel(h, b, l, i)
			out[k] = h
			k += 1
	return out


## Writes `delta`/`alpha` into the whole rect of a layer (undoable).
func fill_layer_rect(id: int, rect: Rect2i, delta: float, alpha: float = 1.0) -> void:
	var li := _layer_index(id)
	var r := rect.intersection(Rect2i(0, 0, width, height))
	if li < 0 or r.size.x <= 0 or r.size.y <= 0:
		return
	var l := _layers[li]
	_push_undo(_snapshot_height(l, r))
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			l.delta[y * width + x] = delta
			l.alpha[y * width + x] = alpha
	_grow_bounds(l, r)
	_mark_rect_dirty(r)


func layer_delta_at(id: int, x: int, y: int) -> float:
	var li := _layer_index(id)
	if li < 0 or x < 0 or y < 0 or x >= width or y >= height:
		return 0.0
	return _layers[li].delta[y * width + x]


# ---------------------------------------------------------------- brushes

func _falloff(t: float, kind: int, curve: Curve) -> float:
	var u := clampf(t, 0.0, 1.0)
	if curve != null:
		return clampf(curve.sample(u), 0.0, 1.0)
	match kind:
		Falloff.LINEAR:
			return u
		Falloff.SPHERE:
			return sqrt(maxf(0.0, 1.0 - (1.0 - u) * (1.0 - u)))
		Falloff.CONSTANT:
			return 1.0
		_:
			return u * u * (3.0 - 2.0 * u)


func _brush_rect(center: Vector2, radius: float) -> Rect2i:
	var x0 := maxi(0, floori(center.x - radius))
	var y0 := maxi(0, floori(center.y - radius))
	var x1 := mini(width - 1, ceili(center.x + radius))
	var y1 := mini(height - 1, ceili(center.y + radius))
	if x1 < x0 or y1 < y0:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


func _hash_noise(x: int, y: int, seed_value: int) -> float:
	var n: int = x * 374761393 + y * 668265263 + seed_value * 1442695041
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xffff) / 32767.5 - 1.0


## Applies a height brush to one edit layer. Returns the changed rect (empty if none).
## `target_height` is used by FLATTEN; `seed_value` by NOISE.
func apply_brush(layer_id: int, brush: int, center: Vector2, radius: float, strength: float,
		falloff: int = Falloff.SMOOTH, target_height: float = 0.0, seed_value: int = 0,
		curve: Curve = null) -> Rect2i:
	var li := _layer_index(layer_id)
	if li < 0 or radius <= 0.0:
		return Rect2i()
	var l := _layers[li]
	var rect := _brush_rect(center, radius)
	if rect.size.x <= 0:
		return Rect2i()
	var region := rect.grow(1).intersection(Rect2i(0, 0, width, height))
	var src := composite_region(region)
	var rw := region.size.x
	var entry := _snapshot_height(l, rect)
	var inv_opacity := 1.0 / maxf(l.opacity, 0.01) if l.blend == Blend.ADD else 1.0
	var changed := false
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var dist := Vector2(float(x), float(y)).distance_to(center)
			if dist > radius:
				continue
			var w := _falloff(1.0 - dist / radius, falloff, curve)
			if w <= 0.0:
				continue
			var h: float = src[(y - region.position.y) * rw + (x - region.position.x)]
			var goal := h
			match brush:
				Brush.RAISE:
					goal = h + strength * w
				Brush.LOWER:
					goal = h - strength * w
				Brush.SMOOTH:
					var sum := 0.0
					for oy in range(-1, 2):
						for ox in range(-1, 2):
							var sx := clampi(x + ox, region.position.x, region.end.x - 1)
							var sy := clampi(y + oy, region.position.y, region.end.y - 1)
							sum += src[(sy - region.position.y) * rw + (sx - region.position.x)]
					goal = lerpf(h, sum / 9.0, clampf(strength * w, 0.0, 1.0))
				Brush.FLATTEN:
					goal = lerpf(h, target_height, clampf(strength * w, 0.0, 1.0))
				Brush.NOISE:
					goal = h + _hash_noise(x, y, seed_value) * strength * w
				Brush.ERODE:
					var lowest := h
					for oy in range(-1, 2):
						for ox in range(-1, 2):
							var sx := clampi(x + ox, region.position.x, region.end.x - 1)
							var sy := clampi(y + oy, region.position.y, region.end.y - 1)
							lowest = minf(lowest, src[(sy - region.position.y) * rw + (sx - region.position.x)])
					goal = h - minf((h - lowest) * 0.5, strength * w)
			var dh := goal - h
			if is_zero_approx(dh):
				continue
			var i := y * width + x
			l.delta[i] += dh * inv_opacity
			l.alpha[i] = maxf(l.alpha[i], clampf(w, 0.0, 1.0))
			changed = true
	if not changed:
		return Rect2i()
	_push_undo(entry)
	_grow_bounds(l, rect)
	_mark_rect_dirty(rect)
	return rect


# ---------------------------------------------------------------- splat (material weights)

## Creates `count` material layers per texel; layer 0 starts at weight 1.
func setup_splat(count: int) -> void:
	_splat_count = maxi(1, count)
	_splat = PackedFloat32Array()
	_splat.resize(width * height * _splat_count)
	for i in width * height:
		_splat[i * _splat_count] = 1.0
	_mark_rect_dirty(Rect2i(0, 0, width, height))


func splat_count() -> int:
	return _splat_count


func splat_weights(x: int, y: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if _splat_count == 0:
		return out
	var i := (clampi(y, 0, height - 1) * width + clampi(x, 0, width - 1)) * _splat_count
	return _splat.slice(i, i + _splat_count)


## Paints material `material` with the brush; other weights shrink so the sum stays 1.
func paint_splat(material: int, center: Vector2, radius: float, strength: float,
		falloff: int = Falloff.SMOOTH, curve: Curve = null) -> Rect2i:
	if _splat_count == 0 or material < 0 or material >= _splat_count or radius <= 0.0:
		return Rect2i()
	var rect := _brush_rect(center, radius)
	if rect.size.x <= 0:
		return Rect2i()
	var entry := UndoEntry.new()
	entry.kind = UndoKind.SPLAT
	entry.rect = rect
	entry.data = _read_rect(_splat, rect, _splat_count)
	var changed := false
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var dist := Vector2(float(x), float(y)).distance_to(center)
			if dist > radius:
				continue
			var a := clampf(_falloff(1.0 - dist / radius, falloff, curve) * strength, 0.0, 1.0)
			if a <= 0.0:
				continue
			var base := (y * width + x) * _splat_count
			var old_t: float = _splat[base + material]
			var new_t := minf(1.0, old_t + a)
			var others := 1.0 - old_t
			var scale := 0.0
			if others > 0.00001:
				scale = (1.0 - new_t) / others
			for k in _splat_count:
				if k == material:
					_splat[base + k] = new_t if others > 0.00001 else 1.0
				else:
					_splat[base + k] = _splat[base + k] * scale
			changed = true
	if not changed:
		return Rect2i()
	_push_undo(entry)
	_mark_rect_dirty(rect)
	return rect


# ---------------------------------------------------------------- undo / redo

func _read_rect(arr: PackedFloat32Array, rect: Rect2i, stride: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for y in range(rect.position.y, rect.end.y):
		var s := (y * width + rect.position.x) * stride
		out.append_array(arr.slice(s, s + rect.size.x * stride))
	return out


func _write_rect(arr: PackedFloat32Array, rect: Rect2i, stride: int, data: PackedFloat32Array) -> void:
	var k := 0
	var row := rect.size.x * stride
	for y in range(rect.position.y, rect.end.y):
		var s := (y * width + rect.position.x) * stride
		for j in row:
			arr[s + j] = data[k]
			k += 1


func _snapshot_height(l: EditLayer, rect: Rect2i) -> UndoEntry:
	var e := UndoEntry.new()
	e.kind = UndoKind.HEIGHT
	e.layer_id = l.id
	e.rect = rect
	e.data = _read_rect(l.delta, rect, 1)
	e.data2 = _read_rect(l.alpha, rect, 1)
	return e


func _push_undo(e: UndoEntry) -> void:
	_undo.append(e)
	_redo.clear()
	_trim_history()


func undo_bytes() -> int:
	var total := 0
	for e in _undo:
		total += e.bytes()
	for e in _redo:
		total += e.bytes()
	return total


func undo_depth() -> int:
	return _undo.size()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func _trim_history() -> void:
	while undo_bytes() > max_undo_bytes and (_undo.size() + _redo.size()) > 1:
		if not _redo.is_empty():
			_redo.remove_at(0)
		else:
			_undo.remove_at(0)


## Swaps the entry's stored data with the live data, so the same routine serves undo and redo.
func _swap_entry(e: UndoEntry) -> bool:
	if e.kind == UndoKind.HEIGHT:
		var li := _layer_index(e.layer_id)
		if li < 0:
			return false
		var l := _layers[li]
		var cur_d := _read_rect(l.delta, e.rect, 1)
		var cur_a := _read_rect(l.alpha, e.rect, 1)
		_write_rect(l.delta, e.rect, 1, e.data)
		_write_rect(l.alpha, e.rect, 1, e.data2)
		e.data = cur_d
		e.data2 = cur_a
	else:
		var cur := _read_rect(_splat, e.rect, _splat_count)
		_write_rect(_splat, e.rect, _splat_count, e.data)
		e.data = cur
	_mark_rect_dirty(e.rect)
	return true


func undo() -> bool:
	while not _undo.is_empty():
		var e: UndoEntry = _undo.pop_back()
		if _swap_entry(e):
			_redo.append(e)
			return true
	return false


func redo() -> bool:
	while not _redo.is_empty():
		var e: UndoEntry = _redo.pop_back()
		if _swap_entry(e):
			_undo.append(e)
			return true
	return false


# ---------------------------------------------------------------- dirty tracking / collision queue

## Marks every chunk whose export (including its 1-texel border) sees a texel in `rect`.
func _mark_rect_dirty(rect: Rect2i) -> void:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var c0x := maxi(0, ceili(float(rect.position.x - 1) / float(chunk_size)) - 1)
	var c0z := maxi(0, ceili(float(rect.position.y - 1) / float(chunk_size)) - 1)
	var c1x := mini(chunks_x - 1, floori(float(rect.end.x) / float(chunk_size)))
	var c1z := mini(chunks_z - 1, floori(float(rect.end.y) / float(chunk_size)))
	for cz in range(c0z, c1z + 1):
		for cx in range(c0x, c1x + 1):
			var c := Vector2i(cx, cz)
			_dirty[c] = true
			if not _collision_pending.has(c):
				_collision_pending[c] = true
				_collision_queue.append(c)


## Chunks touched since the previous call (sorted by z then x); clears the set.
func take_dirty_chunks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k in _dirty.keys():
		var c: Vector2i = k
		out.append(c)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	_dirty.clear()
	return out


## Pops up to `max_per_frame` distinct chunks needing a collision rebuild (oldest first).
func collision_jobs(max_per_frame: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n := mini(maxi(0, max_per_frame), _collision_queue.size())
	for i in n:
		var c: Vector2i = _collision_queue[i]
		_collision_pending.erase(c)
		out.append(c)
	_collision_queue = _collision_queue.slice(n)
	return out


func pending_collision_count() -> int:
	return _collision_queue.size()


# ---------------------------------------------------------------- chunk export / mesh

func _valid_chunk(chunk: Vector2i) -> bool:
	return chunk.x >= 0 and chunk.y >= 0 and chunk.x < chunks_x and chunk.y < chunks_z


## Heights for a chunk with a 1-texel border: (chunk_size + 3)^2 values, row-major.
## Index (i, j) is texel (cx*cs - 1 + i, cz*cs - 1 + j); out-of-map texels clamp to the edge.
func export_chunk_heights(chunk: Vector2i) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if not _valid_chunk(chunk):
		return out
	var side := chunk_size + 3
	var ox := chunk.x * chunk_size - 1
	var oz := chunk.y * chunk_size - 1
	var region := Rect2i(ox, oz, side, side).intersection(Rect2i(0, 0, width, height))
	var src := composite_region(region)
	out.resize(side * side)
	for j in side:
		var sy := clampi(oz + j, region.position.y, region.end.y - 1) - region.position.y
		for i in side:
			var sx := clampi(ox + i, region.position.x, region.end.x - 1) - region.position.x
			out[j * side + i] = src[sy * region.size.x + sx]
	return out


## Builds the chunk's mesh in chunk-local space (origin at the chunk's min corner).
## Normals use the exported border so lighting is continuous across seams.
## ARRAY_COLOR carries the first four splat weights (when splat is set up).
func build_chunk_mesh(chunk: Vector2i, cell_size: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if not _valid_chunk(chunk):
		return mesh
	var hs := export_chunk_heights(chunk)
	var side := chunk_size + 3
	var nx := mini(chunk_size, width - 1 - chunk.x * chunk_size)
	var nz := mini(chunk_size, height - 1 - chunk.y * chunk_size)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	for j in nz + 1:
		for i in nx + 1:
			var hx := i + 1
			var hz := j + 1
			var h: float = hs[hz * side + hx]
			var hl: float = hs[hz * side + hx - 1]
			var hr: float = hs[hz * side + hx + 1]
			var hd: float = hs[(hz - 1) * side + hx]
			var hu: float = hs[(hz + 1) * side + hx]
			verts.append(Vector3(i * cell_size, h, j * cell_size))
			normals.append(Vector3(hl - hr, 2.0 * cell_size, hd - hu).normalized())
			var tx := chunk.x * chunk_size + i
			var tz := chunk.y * chunk_size + j
			uvs.append(Vector2(float(tx) / float(width - 1), float(tz) / float(height - 1)))
			if _splat_count > 0:
				var w := splat_weights(tx, tz)
				colors.append(Color(w[0], w[1] if _splat_count > 1 else 0.0,
					w[2] if _splat_count > 2 else 0.0, w[3] if _splat_count > 3 else 0.0))
	var indices := PackedInt32Array()
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			var b := a + 1
			var c := a + nx + 1
			var d := c + 1
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
