extends RefCounted
## World Partition style scene baking: hierarchical grid cells, always-loaded
## actors, data layers, HLOD clusters, One-File-Per-Actor storage, incremental
## diffs and predictive streaming.
##
## Concepts follow Unreal Engine 5 World Partition (runtime grid with grid
## levels, Data Layers, One File Per Actor, HLOD). Only the publicly documented
## ideas are used; no Epic source code is copied.
##   https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-in-unreal-engine
## The implementation here is original code written for this project.
## Navmesh tile stitching lives in navmesh_stitching.gd (Recast/Detour, zlib).

## Seconds of travel simulated ahead of the streaming source.
var lookahead_seconds: float = 1.5
## Number of sample points along the look-ahead segment.
var lookahead_samples: int = 3

const MAX_LEVEL := 8
const DEFAULT_LAYER_KEY := "default"

var _baked: Dictionary = {}


## Deterministic GUID (UUID-shaped) from a seed string. Same seed, same GUID.
func stable_guid(seed_string: String) -> String:
	var h: String = seed_string.md5_text()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]


func _actor_bounds(actor: Dictionary) -> AABB:
	var pos: Vector3 = actor.get("position", Vector3.ZERO)
	if actor.has("bounds"):
		var b: AABB = actor["bounds"]
		return b
	return AABB(pos, Vector3.ZERO)


func _group_of(layers: PackedStringArray) -> String:
	var sorted: Array = Array(layers)
	sorted.sort()
	return "+".join(PackedStringArray(sorted))


func _level_for(extent: float, cell_size: float) -> int:
	var level := 0
	var size := cell_size
	while extent > size and level < MAX_LEVEL:
		size *= 2.0
		level += 1
	return level


func bake(actors: Array, cell_size: float, loading_range_by_layer: Dictionary) -> Dictionary:
	var cs: float = maxf(cell_size, 0.001)
	var cells: Dictionary = {}
	var always_loaded: Array = []
	var layer_members: Dictionary = {}
	var actor_info: Dictionary = {}
	var index := 0
	for item in actors:
		var actor: Dictionary = item
		var guid: String = actor.get("guid", "")
		if guid == "":
			guid = stable_guid("%s|%d" % [str(actor.get("position", Vector3.ZERO)), index])
		index += 1
		var layers: PackedStringArray = actor.get("layers", PackedStringArray())
		for layer in layers:
			if not layer_members.has(layer):
				layer_members[layer] = []
			(layer_members[layer] as Array).append(guid)
		var bounds: AABB = _actor_bounds(actor)
		var position: Vector3 = actor.get("position", bounds.get_center())
		var info: Dictionary = {
			"position": position,
			"bounds": bounds,
			"layers": layers,
			"data_hash": str(actor.get("data", {})).hash(),
			"cell": "",
		}
		if not bool(actor.get("spatially_loaded", true)):
			always_loaded.append(guid)
			actor_info[guid] = info
			continue
		var center: Vector3 = bounds.get_center() if bounds.size != Vector3.ZERO else position
		var level: int = _level_for(maxf(bounds.size.x, bounds.size.z), cs)
		var lsize: float = cs * pow(2.0, float(level))
		var cx: int = floori(center.x / lsize)
		var cz: int = floori(center.z / lsize)
		var group: String = _group_of(layers)
		var key: String = "%s|%d|%d|%d" % [group, level, cx, cz]
		if not cells.has(key):
			cells[key] = {
				"level": level, "x": cx, "z": cz, "group": group, "layers": layers,
				"bounds": bounds, "actors": [], "range": _range_for(layers, level, cs, loading_range_by_layer),
			}
		var cell: Dictionary = cells[key]
		var cb: AABB = cell["bounds"]
		if (cell["actors"] as Array).is_empty():
			cb = bounds
		else:
			cb = cb.merge(bounds)
		cell["bounds"] = cb
		(cell["actors"] as Array).append(guid)
		info["cell"] = key
		actor_info[guid] = info
	_baked = {
		"cell_size": cs, "cells": cells, "always_loaded": always_loaded,
		"layers": layer_members, "actors": actor_info,
	}
	return _baked


func _range_for(layers: PackedStringArray, level: int, cs: float, ranges: Dictionary) -> float:
	var best := -1.0
	for layer in layers:
		if ranges.has(layer):
			best = maxf(best, float(ranges[layer]))
	if best >= 0.0:
		return best
	if ranges.has(DEFAULT_LAYER_KEY):
		return float(ranges[DEFAULT_LAYER_KEY])
	return cs * 2.0 * pow(2.0, float(level))


## Groups baked cells into HLOD clusters of cluster_cells x cluster_cells cells
## (in each cell's own grid level), keeping layer groups separate.
func hlod_clusters(cells: Dictionary, cluster_cells: int) -> Array:
	var n: int = maxi(cluster_cells, 1)
	var by_key: Dictionary = {}
	var keys: Array = cells.keys()
	keys.sort()
	for k in keys:
		var cell_key: String = k
		var cell: Dictionary = cells[cell_key]
		var cx: int = int(cell["x"])
		var cz: int = int(cell["z"])
		var level: int = int(cell["level"])
		var key: String = "%s|%d|%d|%d" % [cell["group"], level, floori(float(cx) / float(n)), floori(float(cz) / float(n))]
		if not by_key.has(key):
			by_key[key] = {"key": key, "level": level, "group": cell["group"], "bounds": cell["bounds"], "cells": [], "actors": []}
		var cluster: Dictionary = by_key[key]
		var cb: AABB = cluster["bounds"]
		if (cluster["cells"] as Array).is_empty():
			cb = cell["bounds"]
		else:
			cb = cb.merge(cell["bounds"])
		cluster["bounds"] = cb
		(cluster["cells"] as Array).append(cell_key)
		(cluster["actors"] as Array).append_array(cell["actors"])
	var out: Array = []
	var ckeys: Array = by_key.keys()
	ckeys.sort()
	for k in ckeys:
		out.append(by_key[k])
	return out


# One File Per Actor ---------------------------------------------------------

func _actor_to_json(actor: Dictionary) -> Dictionary:
	var pos: Vector3 = actor.get("position", Vector3.ZERO)
	var b: AABB = _actor_bounds(actor)
	return {
		"guid": actor.get("guid", ""),
		"position": [pos.x, pos.y, pos.z],
		"bounds": [b.position.x, b.position.y, b.position.z, b.size.x, b.size.y, b.size.z],
		"layers": Array(actor.get("layers", PackedStringArray())),
		"spatially_loaded": bool(actor.get("spatially_loaded", true)),
		"data": actor.get("data", {}),
	}


func _actor_from_json(d: Dictionary) -> Dictionary:
	var p: Array = d.get("position", [0, 0, 0])
	var b: Array = d.get("bounds", [0, 0, 0, 0, 0, 0])
	return {
		"guid": String(d.get("guid", "")),
		"position": Vector3(float(p[0]), float(p[1]), float(p[2])),
		"bounds": AABB(Vector3(float(b[0]), float(b[1]), float(b[2])), Vector3(float(b[3]), float(b[4]), float(b[5]))),
		"layers": PackedStringArray(d.get("layers", [])),
		"spatially_loaded": bool(d.get("spatially_loaded", true)),
		"data": d.get("data", {}),
	}


## Writes one <guid>.json per actor (tmp file + rename). Returns files written.
func split_one_file_per_actor(actors: Array, dir_path: String) -> int:
	DirAccess.make_dir_recursive_absolute(dir_path)
	var written := 0
	for item in actors:
		var actor: Dictionary = item
		var guid: String = actor.get("guid", "")
		if guid == "":
			continue
		var final_path: String = dir_path.path_join(guid + ".json")
		var tmp_path: String = final_path + ".tmp"
		var f := FileAccess.open(tmp_path, FileAccess.WRITE)
		if f == null:
			continue
		f.store_string(JSON.stringify(_actor_to_json(actor)))
		f.close()
		var err: int = DirAccess.rename_absolute(tmp_path, final_path)
		if err != OK:
			DirAccess.remove_absolute(final_path)
			err = DirAccess.rename_absolute(tmp_path, final_path)
		if err == OK:
			written += 1
	return written


func load_actors(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	var names: Array = []
	for fname in dir.get_files():
		if fname.ends_with(".json"):
			names.append(fname)
	names.sort()
	for fname in names:
		var text: String = FileAccess.get_file_as_string(dir_path.path_join(fname))
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			out.append(_actor_from_json(parsed))
	return out


# Incremental rebake ------------------------------------------------------------

func diff_bakes(old_bake: Dictionary, new_bake: Dictionary) -> Dictionary:
	var old_actors: Dictionary = old_bake.get("actors", {})
	var new_actors: Dictionary = new_bake.get("actors", {})
	var added: Array = []
	var removed: Array = []
	var moved: Array = []
	var changed: Array = []
	var dirty: Dictionary = {}
	for k in new_actors:
		var guid: String = k
		var n: Dictionary = new_actors[guid]
		if not old_actors.has(guid):
			added.append(guid)
			dirty[String(n["cell"])] = true
			continue
		var o: Dictionary = old_actors[guid]
		var op: Vector3 = o["position"]
		var np: Vector3 = n["position"]
		var ob: AABB = o["bounds"]
		var nb: AABB = n["bounds"]
		if not op.is_equal_approx(np) or not ob.is_equal_approx(nb) or o["cell"] != n["cell"]:
			moved.append(guid)
			dirty[String(o["cell"])] = true
			dirty[String(n["cell"])] = true
		elif o["data_hash"] != n["data_hash"]:
			changed.append(guid)
			dirty[String(n["cell"])] = true
	for k in old_actors:
		var guid: String = k
		if not new_actors.has(guid):
			removed.append(guid)
			dirty[String((old_actors[guid] as Dictionary)["cell"])] = true
	dirty.erase("")
	added.sort()
	removed.sort()
	moved.sort()
	changed.sort()
	var dirty_cells: Array = dirty.keys()
	dirty_cells.sort()
	return {"added": added, "removed": removed, "moved": moved, "changed": changed, "dirty_cells": dirty_cells}


# Streaming -------------------------------------------------------------------------

func _dist_to_cell(p: Vector3, b: AABB) -> float:
	var dx: float = maxf(maxf(b.position.x - p.x, p.x - (b.position.x + b.size.x)), 0.0)
	var dz: float = maxf(maxf(b.position.z - p.z, p.z - (b.position.z + b.size.z)), 0.0)
	return sqrt(dx * dx + dz * dz)


## Cells to stream in for a source, also sampling points along its velocity
## (predictive look-ahead). Cells of disabled data layers are skipped.
## Sorted nearest-first, using the most recent bake().
func cells_to_load(source_pos: Vector3, velocity: Vector3, layers_enabled: PackedStringArray) -> Array:
	var cells: Dictionary = _baked.get("cells", {})
	var samples: Array = [source_pos]
	var count: int = maxi(lookahead_samples, 1)
	if velocity.length_squared() > 0.000001:
		for i in range(1, count + 1):
			samples.append(source_pos + velocity * (lookahead_seconds * float(i) / float(count)))
	var scored: Array = []
	for k in cells:
		var key: String = k
		var cell: Dictionary = cells[key]
		var layers: PackedStringArray = cell["layers"]
		if not layers.is_empty():
			var enabled := false
			for layer in layers:
				if layer in layers_enabled:
					enabled = true
					break
			if not enabled:
				continue
		var best := INF
		for s in samples:
			var p: Vector3 = s
			best = minf(best, _dist_to_cell(p, cell["bounds"]))
		if best <= float(cell["range"]):
			scored.append([best, key])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] == b[0]:
			return String(a[1]) < String(b[1])
		return float(a[0]) < float(b[0]))
	var out: Array = []
	for s in scored:
		out.append(s[1])
	return out
