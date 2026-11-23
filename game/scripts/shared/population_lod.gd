extends RefCounted
## Simulation LOD for large populations outside the players' active zone.
##
## Far from every player the crowd is not simulated agent by agent. It lives as
## abstract "herds" on a coarse region grid: a herd is {id, region, count,
## composition by type, heading, state}. Herds keep moving (migrating along the
## gradient of attractors such as noise, corpses, loot and night, plus a seeded
## random wander), merge when they meet, split when they grow too big and
## decay/respawn by simple rules. When a player comes close, promote() turns a
## region's herds into concrete spawn specs (conserving counts, bounded by an
## agent budget) and demote() folds despawned agents back into a herd.
##
## Design references (concepts only, no code copied):
##  - Mass Entity simulation LOD / representation LOD (Epic Games, concept
##    only; engine code is under the UE EULA and was NOT read or copied).
##  - Ubisoft "systemic AI" talks and the "Days Gone" horde simulation talks
##    (GDC) for the abstract-herd-on-a-graph + promote/demote idea.
## All logic here is an original implementation written for this project and is
## released with the rest of the project.
##
## Everything is deterministic: one seeded RandomNumberGenerator, herds visited
## in ascending id order, no wall-clock input.

const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
]

## Relative pull of each attractor kind.
var kind_weight: Dictionary = {"noise": 1.0, "corpse": 0.6, "loot": 0.5, "night": 0.3}

var cols: int = 0
var rows: int = 0
var cell_size: float = 64.0
var origin: Vector2 = Vector2.ZERO

var herds: Dictionary = {}                 ## id -> herd Dictionary
var max_herd_size: int = 40
var herd_speed: float = 8.0                ## world units per second, daytime
var night_speed_mult: float = 1.5
var dwell_time: float = 4.0                ## seconds idling in a region before moving on
var randomness: float = 0.6                ## weight of the random wander term
var momentum: float = 0.25                 ## preference for keeping the heading
var promote_radius: float = 120.0
var max_concrete_agents: int = 128         ## budget for simultaneously promoted agents
var night: bool = false

var concrete_count: int = 0                ## agents currently promoted and not yet demoted
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_id: int = 1
var _time: float = 0.0
var _attractors: Array[Dictionary] = []
# Server-owned moving sources update one signal in place instead of
# accumulating dozens of noise/night impulses per player each population pass.
var _attractor_sources: Dictionary = {}    ## "kind:peer" -> shared attractor Dictionary
var _attr: PackedFloat32Array = PackedFloat32Array()
var _attr_dirty: bool = true
var _blocked: Dictionary = {}              ## region -> true
var _decay: Dictionary = {}                ## region -> decay rate (agents per second per herd)
var _spawners: Array[Dictionary] = []
var _players: PackedVector2Array = PackedVector2Array()
var _stats: Dictionary = {
	"migrations": 0, "merges": 0, "splits": 0, "promotions": 0, "demotions": 0,
	"spawned": 0, "decayed": 0, "promote_denied": 0,
}


func setup(p_cols: int, p_rows: int, p_cell_size: float, seed_value: int, p_origin: Vector2 = Vector2.ZERO) -> void:
	cols = maxi(1, p_cols)
	rows = maxi(1, p_rows)
	cell_size = maxf(1.0, p_cell_size)
	origin = p_origin
	_rng.seed = seed_value
	herds.clear()
	_attractors.clear()
	_attractor_sources.clear()
	_blocked.clear()
	_decay.clear()
	_spawners.clear()
	_next_id = 1
	_time = 0.0
	concrete_count = 0
	for key in _stats.keys():
		_stats[key] = 0
	_attr = PackedFloat32Array()
	_attr.resize(cols * rows)
	_attr_dirty = true


# --- Grid -------------------------------------------------------------------

func region_count() -> int:
	return cols * rows


func region_of(pos: Vector2) -> int:
	var local := (pos - origin) / cell_size
	var cx := clampi(int(floorf(local.x)), 0, cols - 1)
	var cy := clampi(int(floorf(local.y)), 0, rows - 1)
	return cy * cols + cx


func region_cell(region: int) -> Vector2i:
	@warning_ignore("integer_division")
	var cy: int = region / cols
	return Vector2i(region % cols, cy)


func region_center(region: int) -> Vector2:
	var c := region_cell(region)
	return origin + (Vector2(c) + Vector2(0.5, 0.5)) * cell_size


func set_blocked(region: int, blocked: bool) -> void:
	if blocked:
		_blocked[region] = true
	else:
		_blocked.erase(region)


func is_blocked(region: int) -> bool:
	return _blocked.has(region)


# --- Attractors, hazards, spawners ----------------------------------------

## kind: "noise" | "corpse" | "loot" | "night" (or any key of kind_weight).
## ttl < 0 means permanent.
func add_attractor(kind: String, pos: Vector2, strength: float, radius: float, ttl: float = -1.0) -> void:
	_attractors.append({"kind": kind, "pos": pos, "strength": strength, "radius": maxf(1.0, radius), "ttl": ttl})
	_attr_dirty = true


## Dynamic signals from one authoritative source (such as a player) replace
## their old values instead of stacking a new copy every server population pass.
## Different types and different players are independent; ordinary event
## attractors created by add_attractor() retain their original semantics.
func set_source_attractor(kind: String, source_id: int, pos: Vector2,
		strength: float, radius: float, ttl: float) -> void:
	if not pos.is_finite() or not is_finite(strength) or not is_finite(radius) or \
			not is_finite(ttl) or radius <= 0.0 or ttl <= 0.0:
		return
	var key: String = "%s:%d" % [kind, source_id]
	var source_signal: Dictionary = _attractor_sources.get(key, {})
	if source_signal.is_empty():
		source_signal = {"kind": kind, "pos": pos, "strength": strength,
			"radius": maxf(1.0, radius), "ttl": ttl, "source": key}
		_attractor_sources[key] = source_signal
		_attractors.append(source_signal)
	else:
		# A moving gunshot/noise source follows the player and reflects their
		# current volume. TTL only changes lifetime, not attraction strength.
		if source_signal["pos"] != pos or float(source_signal["strength"]) != strength or \
				float(source_signal["radius"]) != maxf(1.0, radius):
			source_signal["pos"] = pos
			source_signal["strength"] = strength
			source_signal["radius"] = maxf(1.0, radius)
			_attr_dirty = true
		source_signal["ttl"] = ttl
		return
	_attr_dirty = true


func active_attractor_count() -> int:
	return _attractors.size()


func clear_attractors() -> void:
	_attractors.clear()
	_attractor_sources.clear()
	_attr_dirty = true


func set_night(value: bool) -> void:
	if night == value:
		return
	night = value
	# Night-only attractors must take effect at the very next simulation tick.
	_attr_dirty = true


## Herds inside this region lose `rate` agents per second (e.g. fire, base defences).
func set_decay(region: int, rate: float) -> void:
	if rate <= 0.0:
		_decay.erase(region)
	else:
		_decay[region] = rate


## A nest: adds `rate` agents of `type` per second to the region while its
## abstract population stays below `cap`.
func add_spawner(region: int, type: String, rate: float, cap: int) -> void:
	_spawners.append({"region": region, "type": type, "rate": rate, "cap": cap, "acc": 0.0})


func attraction(region: int) -> float:
	_refresh_attraction()
	return _attr[region]


func _refresh_attraction() -> void:
	if not _attr_dirty:
		return
	_attr_dirty = false
	_attr.fill(0.0)
	for a in _attractors:
		var kind: String = a["kind"]
		if kind == "night" and not night:
			continue
		var w: float = kind_weight.get(kind, 1.0)
		var apos: Vector2 = a["pos"]
		var radius: float = a["radius"]
		var strength: float = a["strength"]
		# A short noise or loot event affects only nearby regions. Avoid
		# scanning the full island for every local attractor.
		# Conservative one-cell padding retains strict circle-boundary semantics.
		var low_x: int = maxi(0, floori((apos.x - radius - origin.x) / cell_size - 0.5))
		var high_x: int = mini(cols - 1, ceili((apos.x + radius - origin.x) / cell_size - 0.5))
		var low_y: int = maxi(0, floori((apos.y - radius - origin.y) / cell_size - 0.5))
		var high_y: int = mini(rows - 1, ceili((apos.y + radius - origin.y) / cell_size - 0.5))
		for cy in range(low_y, high_y + 1):
			for cx in range(low_x, high_x + 1):
				var r: int = cy * cols + cx
				var d: float = region_center(r).distance_to(apos)
				if d < radius:
					_attr[r] += strength * w * (1.0 - d / radius)


# --- Herd management ----------------------------------------------------------

## composition: {type: count}. Returns the herd id.
func add_herd(region: int, composition: Dictionary, heading: Vector2 = Vector2.RIGHT) -> int:
	var id := _next_id
	_next_id += 1
	var comp: Dictionary = {}
	var total := 0
	for key in composition.keys():
		var n: int = composition[key]
		if n > 0:
			comp[key] = n
			total += n
	var h: Dictionary = {
		"id": id, "region": region, "count": total, "comp": comp,
		"heading": heading.normalized() if heading.length_squared() > 0.0 else Vector2.RIGHT,
		"state": "idle", "pos": region_center(region), "from": region, "to": region,
		"t": 0.0, "travel": 1.0, "timer": _rng.randf_range(0.0, dwell_time),
		"decay_acc": 0.0,
	}
	herds[id] = h
	return id


func herd_ids() -> Array:
	var ids: Array = herds.keys()
	ids.sort()
	return ids


func herd_region_count(region: int) -> int:
	var n := 0
	for id in herds.keys():
		var h: Dictionary = herds[id]
		if int(h["region"]) == region:
			n += int(h["count"])
	return n


## Agents represented abstractly (in herds).
func abstract_count() -> int:
	var n := 0
	for id in herds.keys():
		var h: Dictionary = herds[id]
		n += int(h["count"])
	return n


## Everything: abstract plus promoted agents.
func total_population() -> int:
	return abstract_count() + concrete_count


func composition_total(type: String) -> int:
	var n := 0
	for id in herds.keys():
		var h: Dictionary = herds[id]
		var comp: Dictionary = h["comp"]
		n += int(comp.get(type, 0))
	return n


func stats() -> Dictionary:
	var s: Dictionary = _stats.duplicate()
	s["herds"] = herds.size()
	s["abstract"] = abstract_count()
	s["concrete"] = concrete_count
	s["total"] = total_population()
	s["budget_left"] = maxi(0, max_concrete_agents - concrete_count)
	return s


# --- Simulation -----------------------------------------------------------------

func tick(dt: float, player_positions: PackedVector2Array = PackedVector2Array()) -> void:
	_players = player_positions
	_time += dt
	_age_attractors(dt)
	_refresh_attraction()
	var ids := herd_ids()
	for id in ids:
		if herds.has(id):
			_step_herd(herds[id], dt)
	_merge_pass()
	_split_pass()
	_rules_pass(dt)


func _age_attractors(dt: float) -> void:
	var i := _attractors.size() - 1
	while i >= 0:
		var ttl: float = _attractors[i]["ttl"]
		if ttl >= 0.0:
			ttl -= dt
			if ttl <= 0.0:
				var source_signal: Dictionary = _attractors[i]
				if source_signal.has("source"):
					_attractor_sources.erase(source_signal["source"])
				_attractors.remove_at(i)
				_attr_dirty = true
			else:
				_attractors[i]["ttl"] = ttl
		i -= 1


func _step_herd(h: Dictionary, dt: float) -> void:
	var state: String = h["state"]
	if state == "moving":
		var t: float = h["t"]
		t += dt / maxf(0.001, float(h["travel"]))
		h["t"] = t
		var from_c := region_center(int(h["from"]))
		var to_c := region_center(int(h["to"]))
		h["pos"] = from_c.lerp(to_c, minf(t, 1.0))
		if t >= 0.5:
			h["region"] = h["to"]
		if t >= 1.0:
			h["state"] = "idle"
			h["region"] = h["to"]
			h["pos"] = to_c
			h["timer"] = dwell_time * _rng.randf_range(0.5, 1.5)
		return
	var timer: float = h["timer"]
	timer -= dt
	h["timer"] = timer
	if timer > 0.0:
		return
	var next := _choose_next(h)
	if next < 0:
		h["timer"] = dwell_time * _rng.randf_range(0.5, 1.5)
		return
	var cur: int = h["region"]
	var dir := (region_center(next) - region_center(cur))
	var dist := dir.length()
	var speed := herd_speed * (night_speed_mult if night else 1.0)
	h["heading"] = dir / maxf(0.001, dist)
	h["from"] = cur
	h["to"] = next
	h["t"] = 0.0
	h["travel"] = dist / maxf(0.001, speed)
	h["state"] = "moving"
	_stats["migrations"] = int(_stats["migrations"]) + 1


func _choose_next(h: Dictionary) -> int:
	var cur: int = h["region"]
	var cc := region_cell(cur)
	var heading: Vector2 = h["heading"]
	var cur_attr := _attr[cur]
	var best := -1
	var best_score := -INF
	var best_neighbour_attr := -INF
	for off in NEIGHBOURS:
		var n := cc + off
		if n.x < 0 or n.y < 0 or n.x >= cols or n.y >= rows:
			continue
		var r := n.y * cols + n.x
		if _blocked.has(r):
			continue
		best_neighbour_attr = maxf(best_neighbour_attr, _attr[r])
		var dir := Vector2(off).normalized()
		var score := (_attr[r] - cur_attr) * 2.0
		score += dir.dot(heading) * momentum
		score += _rng.randf_range(-1.0, 1.0) * randomness * (0.5 if night else 1.0)
		if score > best_score:
			best_score = score
			best = r
	# Sitting on the best attractor spot: stay until it fades.
	if best >= 0 and cur_attr > 0.0 and cur_attr >= best_neighbour_attr:
		return -1
	return best


func _merge_pass() -> void:
	var by_region: Dictionary = {}
	for id in herd_ids():
		var h: Dictionary = herds[id]
		var r: int = h["region"]
		if not by_region.has(r):
			by_region[r] = []
		var list: Array = by_region[r]
		list.append(id)
	var merge_dist := cell_size * 0.5
	var regions: Array = by_region.keys()
	regions.sort()
	for r in regions:
		var list: Array = by_region[r]
		var i := 0
		while i < list.size():
			var a_id: int = list[i]
			if not herds.has(a_id):
				i += 1
				continue
			var a: Dictionary = herds[a_id]
			var j := i + 1
			while j < list.size():
				var b_id: int = list[j]
				if not herds.has(b_id):
					j += 1
					continue
				var b: Dictionary = herds[b_id]
				var apos: Vector2 = a["pos"]
				var bpos: Vector2 = b["pos"]
				if int(a["count"]) + int(b["count"]) <= max_herd_size and apos.distance_to(bpos) <= merge_dist:
					_absorb(a, b)
					herds.erase(b_id)
					_stats["merges"] = int(_stats["merges"]) + 1
				j += 1
			i += 1


func _absorb(a: Dictionary, b: Dictionary) -> void:
	var ca: int = a["count"]
	var cb: int = b["count"]
	var comp_a: Dictionary = a["comp"]
	var comp_b: Dictionary = b["comp"]
	for key in comp_b.keys():
		comp_a[key] = int(comp_a.get(key, 0)) + int(comp_b[key])
	var total := ca + cb
	var apos: Vector2 = a["pos"]
	var bpos: Vector2 = b["pos"]
	var ah: Vector2 = a["heading"]
	var bh: Vector2 = b["heading"]
	if total > 0:
		a["pos"] = (apos * float(ca) + bpos * float(cb)) / float(total)
		var h := ah * float(ca) + bh * float(cb)
		if h.length_squared() > 0.0001:
			a["heading"] = h.normalized()
	a["count"] = total
	# The merged herd goes with whichever part is still moving, else stays idle.
	if str(b["state"]) == "moving" and str(a["state"]) != "moving":
		a["state"] = "idle"
		a["timer"] = 0.0


func _split_pass() -> void:
	for id in herd_ids():
		if not herds.has(id):
			continue
		var h: Dictionary = herds[id]
		var count: int = h["count"]
		if count <= max_herd_size or str(h["state"]) == "moving":
			continue
		var comp: Dictionary = h["comp"]
		var moved: Dictionary = {}
		var moved_total := 0
		var types: Array = comp.keys()
		types.sort()
		for type in types:
			var c: int = comp[type]
			@warning_ignore("integer_division")
			var half: int = c / 2
			if half > 0:
				moved[type] = half
				comp[type] = c - half
				moved_total += half
		if moved_total <= 0:
			continue
		h["count"] = count - moved_total
		var heading: Vector2 = h["heading"]
		var nid := add_herd(int(h["region"]), moved, heading.rotated(_rng.randf_range(0.8, 2.4)))
		var nh: Dictionary = herds[nid]
		nh["pos"] = h["pos"]
		nh["timer"] = 0.0
		h["timer"] = 0.0
		_stats["splits"] = int(_stats["splits"]) + 1


func _rules_pass(dt: float) -> void:
	# Decay.
	for id in herd_ids():
		var h: Dictionary = herds[id]
		var r: int = h["region"]
		if not _decay.has(r):
			continue
		var acc: float = h["decay_acc"]
		acc += float(_decay[r]) * dt
		var lose := int(floorf(acc))
		acc -= float(lose)
		h["decay_acc"] = acc
		if lose > 0:
			_remove_from_herd(h, lose)
	for id in herd_ids():
		var h: Dictionary = herds[id]
		if int(h["count"]) <= 0:
			herds.erase(id)
	# Count each region once after decay. Multiple nests in one region share
	# the same up-to-date cap, but no longer rescan every herd for every nest.
	var region_totals: Dictionary = {}
	if not _spawners.is_empty():
		for h in herds.values():
			var region: int = int(h["region"])
			region_totals[region] = int(region_totals.get(region, 0)) + int(h["count"])
	# Respawn. Iteration order and fractional accumulators are unchanged.
	for s in _spawners:
		var region: int = s["region"]
		var cap: int = s["cap"]
		var acc: float = s["acc"]
		acc += float(s["rate"]) * dt
		var add := int(floorf(acc))
		acc -= float(add)
		s["acc"] = acc
		if add <= 0:
			continue
		var room: int = cap - int(region_totals.get(region, 0))
		add = mini(add, room)
		if add <= 0:
			s["acc"] = 0.0
			continue
		_add_to_region(region, str(s["type"]), add)
		region_totals[region] = int(region_totals.get(region, 0)) + add
		_stats["spawned"] = int(_stats["spawned"]) + add


func _remove_from_herd(h: Dictionary, amount: int) -> void:
	var comp: Dictionary = h["comp"]
	var types: Array = comp.keys()
	types.sort()
	var left := amount
	for type in types:
		if left <= 0:
			break
		var c: int = comp[type]
		var take := mini(c, left)
		comp[type] = c - take
		left -= take
		if c - take <= 0:
			comp.erase(type)
	var removed := amount - left
	h["count"] = int(h["count"]) - removed
	_stats["decayed"] = int(_stats["decayed"]) + removed


func _add_to_region(region: int, type: String, amount: int) -> void:
	for id in herd_ids():
		var h: Dictionary = herds[id]
		if int(h["region"]) == region and str(h["state"]) != "moving" and int(h["count"]) + amount <= max_herd_size:
			var comp: Dictionary = h["comp"]
			comp[type] = int(comp.get(type, 0)) + amount
			h["count"] = int(h["count"]) + amount
			return
	add_herd(region, {type: amount})


# --- Promotion / demotion --------------------------------------------------------

## Regions whose centre is within promote_radius of any of `positions`.
## Iterate occupied herd regions rather than scanning every map cell and then
## scanning all herds again for each nearby region. Sorting preserves the
## ascending region order expected by server promotion and reproducible tests.
func regions_near(positions: PackedVector2Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	if positions.is_empty() or herds.is_empty():
		return out
	var population_by_region: Dictionary = {}
	var limit: int = region_count()
	for h in herds.values():
		var region: int = int(h["region"])
		if region < 0 or region >= limit:
			continue
		population_by_region[region] = int(population_by_region.get(region, 0)) + int(h["count"])
	var occupied: Array = population_by_region.keys()
	occupied.sort()
	for region in occupied:
		var r: int = int(region)
		if int(population_by_region[r]) > 0 and _near_player(region_center(r), positions):
			out.append(r)
	return out


func _near_player(pos: Vector2, positions: PackedVector2Array) -> bool:
	var reach := promote_radius + cell_size * 0.5
	for p in positions:
		if p.distance_to(pos) <= reach:
			return true
	return false


## Converts herds of `region` into concrete spawn specs {type, position, heading}.
## Only when a player (from the last tick() call) is within the promote radius
## and only as many agents as the remaining budget allows; the rest stays in the herd.
func promote(region: int, player_positions: PackedVector2Array = PackedVector2Array()) -> Array:
	var out: Array = []
	var players := player_positions if player_positions.size() > 0 else _players
	if region < 0 or region >= region_count() or not _near_player(region_center(region), players):
		return out
	var budget := max_concrete_agents - concrete_count
	if budget <= 0:
		_stats["promote_denied"] = int(_stats["promote_denied"]) + 1
		return out
	var spread := cell_size * 0.35
	for id in herd_ids():
		if budget <= 0:
			break
		var h: Dictionary = herds[id]
		if int(h["region"]) != region:
			continue
		var comp: Dictionary = h["comp"]
		var heading: Vector2 = h["heading"]
		var center: Vector2 = h["pos"]
		var types: Array = comp.keys()
		types.sort()
		for type in types:
			var c: int = comp[type]
			var take := mini(c, budget)
			for k in range(take):
				var offset := Vector2(_rng.randf_range(-spread, spread), _rng.randf_range(-spread, spread))
				out.append({"type": type, "position": center + offset, "heading": heading})
			comp[type] = c - take
			if c - take <= 0:
				comp.erase(type)
			budget -= take
			h["count"] = int(h["count"]) - take
			if budget <= 0:
				break
		if int(h["count"]) <= 0:
			herds.erase(id)
	concrete_count += out.size()
	if out.size() > 0:
		_stats["promotions"] = int(_stats["promotions"]) + out.size()
	return out


## Folds concrete agents (dictionaries with "type", or plain type strings) back
## into the abstract population of `region`.
func demote(agents: Array, region: int) -> void:
	if agents.is_empty():
		return
	var counts: Dictionary = {}
	var n := 0
	for a in agents:
		var type: String = a if a is String else str((a as Dictionary).get("type", "unknown"))
		counts[type] = int(counts.get(type, 0)) + 1
		n += 1
	var types: Array = counts.keys()
	types.sort()
	for type in types:
		_add_to_region(region, str(type), int(counts[type]))
	concrete_count = maxi(0, concrete_count - n)
	_stats["demotions"] = int(_stats["demotions"]) + n
