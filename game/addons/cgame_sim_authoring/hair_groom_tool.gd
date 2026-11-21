extends RefCounted
## Hair grooming brushes over the guide strands of res://scripts/client/hair_strands.gd.
## Operates on `hair.rest` (head space). Original code.
## Layout reminder: guide g owns rest[g*ppg .. (g+1)*ppg), index 0 is the root and is never moved.

const MAX_UNDO := 64

var _undo: Array[PackedVector3Array] = []
var _redo: Array[PackedVector3Array] = []


static func falloff(dist: float, radius: float) -> float:
	if radius <= 0.0 or dist >= radius:
		return 0.0
	var t: float = 1.0 - dist / radius
	return t * t * (3.0 - 2.0 * t)


func _push(hair: RefCounted) -> void:
	var rest: PackedVector3Array = hair.get("rest")
	_undo.append(rest.duplicate())
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
	_redo.clear()


func undo(hair: RefCounted) -> bool:
	if _undo.is_empty():
		return false
	var rest: PackedVector3Array = hair.get("rest")
	_redo.append(rest.duplicate())
	hair.set("rest", _undo.pop_back())
	return true


func redo(hair: RefCounted) -> bool:
	if _redo.is_empty():
		return false
	var rest: PackedVector3Array = hair.get("rest")
	_undo.append(rest.duplicate())
	hair.set("rest", _redo.pop_back())
	return true


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


## Bends segments toward `direction`, weighted by falloff from `center`. Segment lengths are
## preserved; guides with no point inside the radius are untouched. Returns guides changed.
func comb(hair: RefCounted, center: Vector3, radius: float, direction: Vector3, strength: float) -> int:
	var dir: Vector3 = direction.normalized()
	var guides: int = hair.get("guide_count")
	var ppg: int = hair.get("points_per_guide")
	var rest: PackedVector3Array = hair.get("rest")
	var changed: Array[int] = []
	var out: PackedVector3Array = rest.duplicate()
	for g in guides:
		var base: int = g * ppg
		var any: bool = false
		for i in range(1, ppg):
			var mid: Vector3 = (rest[base + i] + rest[base + i - 1]) * 0.5
			if falloff(mid.distance_to(center), radius) > 0.0:
				any = true
				break
		if not any:
			continue
		changed.append(g)
		for i in range(1, ppg):
			var seg: Vector3 = rest[base + i] - rest[base + i - 1]
			var seg_len: float = seg.length()
			if seg_len < 0.000001:
				out[base + i] = out[base + i - 1]
				continue
			var mid2: Vector3 = (rest[base + i] + rest[base + i - 1]) * 0.5
			var w: float = clampf(falloff(mid2.distance_to(center), radius) * strength, 0.0, 1.0)
			var nd: Vector3 = (seg / seg_len).lerp(dir, w).normalized()
			out[base + i] = out[base + i - 1] + nd * seg_len
	if changed.is_empty():
		return 0
	_push(hair)
	hair.set("rest", out)
	return changed.size()


## Shortens guides whose root lies within `radius` by `amount` (0..1 of their length).
## Roots stay put. Returns guides changed.
func cut(hair: RefCounted, center: Vector3, radius: float, amount: float) -> int:
	return paint_length(hair, center, radius, 1.0 - clampf(amount, 0.0, 1.0), 1.0, true)


## Moves guide length toward `target_scale` (relative to current length) with falloff by root
## distance. `hard` ignores falloff (used by cut). Returns guides changed.
func paint_length(hair: RefCounted, center: Vector3, radius: float, target_scale: float, strength: float, hard: bool = false) -> int:
	var guides: int = hair.get("guide_count")
	var ppg: int = hair.get("points_per_guide")
	var rest: PackedVector3Array = hair.get("rest")
	var out: PackedVector3Array = rest.duplicate()
	var n: int = 0
	for g in guides:
		var base: int = g * ppg
		var d: float = rest[base].distance_to(center)
		var w: float = 1.0 if hard and d <= radius else falloff(d, radius)
		w = clampf(w * strength, 0.0, 1.0)
		if w <= 0.0:
			continue
		var s: float = lerpf(1.0, maxf(target_scale, 0.01), w)
		for i in range(1, ppg):
			out[base + i] = rest[base] + (rest[base + i] - rest[base]) * s
		n += 1
	if n == 0:
		return 0
	_push(hair)
	hair.set("rest", out)
	return n


## Pulls guide points toward the nearest of `cluster_centers` (tip-weighted, roots fixed) for
## guides whose tip is within `radius` of that centre. Returns guides changed.
func clump(hair: RefCounted, cluster_centers: PackedVector3Array, radius: float, strength: float) -> int:
	if cluster_centers.is_empty():
		return 0
	var guides: int = hair.get("guide_count")
	var ppg: int = hair.get("points_per_guide")
	var rest: PackedVector3Array = hair.get("rest")
	var out: PackedVector3Array = rest.duplicate()
	var n: int = 0
	for g in guides:
		var base: int = g * ppg
		var tip: Vector3 = rest[base + ppg - 1]
		var best: Vector3 = cluster_centers[0]
		for c in cluster_centers:
			if tip.distance_squared_to(c) < tip.distance_squared_to(best):
				best = c
		var w: float = falloff(tip.distance_to(best), radius) * strength
		if w <= 0.0:
			continue
		w = clampf(w, 0.0, 1.0)
		for i in range(1, ppg):
			var t: float = float(i) / float(ppg - 1)
			out[base + i] = rest[base + i].lerp(best, w * t * t)
		n += 1
	if n == 0:
		return 0
	_push(hair)
	hair.set("rest", out)
	return n


## Seeded random displacement growing toward the tip (frizz), falloff by point distance.
func noise(hair: RefCounted, center: Vector3, radius: float, amount: float, seed: int) -> int:
	var guides: int = hair.get("guide_count")
	var ppg: int = hair.get("points_per_guide")
	var rest: PackedVector3Array = hair.get("rest")
	var out: PackedVector3Array = rest.duplicate()
	var rng := RandomNumberGenerator.new()
	var n: int = 0
	for g in guides:
		var base: int = g * ppg
		var touched: bool = false
		for i in range(1, ppg):
			var w: float = falloff(rest[base + i].distance_to(center), radius)
			rng.seed = seed * 7919 + (base + i) * 104729
			var jitter := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
			if w <= 0.0:
				continue
			touched = true
			var t: float = float(i) / float(ppg - 1)
			out[base + i] = rest[base + i] + jitter * (amount * w * t)
		if touched:
			n += 1
	if n == 0:
		return 0
	_push(hair)
	hair.set("rest", out)
	return n


## JSON-safe snapshot (flat float arrays; no engine types).
func export_groom(hair: RefCounted) -> Dictionary:
	var rest: PackedVector3Array = hair.get("rest")
	var flat: Array = []
	for p in rest:
		flat.append_array([p.x, p.y, p.z])
	return {
		"version": 1,
		"guide_count": hair.get("guide_count") as int,
		"points_per_guide": hair.get("points_per_guide") as int,
		"segments": hair.get("segments") as int,
		"seg_len": hair.get("seg_len") as float,
		"rest": flat,
	}


## Restores a snapshot into `hair`. Returns false on malformed data.
func import_groom(hair: RefCounted, data: Dictionary) -> bool:
	if not (data.has("guide_count") and data.has("points_per_guide") and data.has("rest")):
		return false
	var guides: int = int(data["guide_count"])
	var ppg: int = int(data["points_per_guide"])
	var flat: Array = data["rest"]
	if flat.size() != guides * ppg * 3:
		return false
	var rest := PackedVector3Array()
	var i: int = 0
	while i + 2 < flat.size():
		rest.append(Vector3(flat[i] as float, flat[i + 1] as float, flat[i + 2] as float))
		i += 3
	_push(hair)
	hair.set("guide_count", guides)
	hair.set("points_per_guide", ppg)
	hair.set("segments", int(data.get("segments", ppg - 1)))
	hair.set("seg_len", float(data.get("seg_len", hair.get("seg_len"))))
	hair.set("rest", rest)
	var pos: PackedVector3Array = rest.duplicate()
	hair.set("pos", pos)
	hair.set("prev", rest.duplicate())
	hair.call("_build_neighbors")
	return true
