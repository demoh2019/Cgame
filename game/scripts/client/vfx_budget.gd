extends RefCounted
## Global VFX budget: per-category effect and particle caps scaled by quality tier, with
## priority/distance based admission and eviction of the lowest-value live effects.
## Original design; no third-party code.

signal evicted(id: int, category: String)

enum Tier { LOW, MEDIUM, HIGH, ULTRA }

## category -> [max_effects, max_particles] for the MEDIUM tier; other tiers scale it.
const CATEGORY_BASE := {
	"combat": [24, 2400],
	"ambient": [16, 1600],
	"weather": [6, 3000],
	"environment": [12, 2000],
	"ui": [8, 400],
}
const TIER_SCALE := [0.4, 1.0, 1.75, 3.0]
const TIER_MAX_DISTANCE := [40.0, 70.0, 110.0, 160.0]
const GLOBAL_PARTICLE_BASE := 6000

var tier: int = Tier.MEDIUM
var distance_falloff: float = 0.05

var _next_id: int = 1
var _live: Dictionary = {}  ## id -> {category, cost, priority, value}
var _cat_effects: Dictionary = {}
var _cat_particles: Dictionary = {}
var _particles_total: int = 0
var stats: Dictionary = {"accepted": 0, "rejected": 0, "evicted": 0, "released": 0}
var last_id: int = 0


func _init(quality_tier: int = Tier.MEDIUM) -> void:
	tier = clampi(quality_tier, 0, Tier.ULTRA)


func set_tier(quality_tier: int) -> void:
	tier = clampi(quality_tier, 0, Tier.ULTRA)


func max_effects(category: String) -> int:
	var base: Array = CATEGORY_BASE.get(category, [8, 800])
	@warning_ignore("unsafe_call_argument")
	return maxi(1, roundi(float(base[0]) * float(TIER_SCALE[tier])))


func max_particles(category: String) -> int:
	var base: Array = CATEGORY_BASE.get(category, [8, 800])
	@warning_ignore("unsafe_call_argument")
	return maxi(1, roundi(float(base[1]) * float(TIER_SCALE[tier])))


func max_total_particles() -> int:
	return roundi(float(GLOBAL_PARTICLE_BASE) * float(TIER_SCALE[tier]))


func max_distance() -> float:
	return float(TIER_MAX_DISTANCE[tier])


## Higher is more worth keeping: priority, discounted by distance to the camera.
func value_of(priority: float, position: Vector3, camera_pos: Vector3) -> float:
	return priority / (1.0 + position.distance_to(camera_pos) * distance_falloff)


func request(category: String, cost: int, priority: float, position: Vector3, camera_pos: Vector3) -> bool:
	return request_id(category, cost, priority, position, camera_pos) > 0


## Like request() but returns the id of the admitted effect (0 when rejected).
func request_id(category: String, cost: int, priority: float, position: Vector3, camera_pos: Vector3) -> int:
	last_id = 0
	var c := maxi(0, cost)
	if position.distance_to(camera_pos) > max_distance() or c > max_particles(category) or c > max_total_particles():
		stats["rejected"] = int(stats["rejected"]) + 1
		return 0
	var value := value_of(priority, position, camera_pos)
	var victims: Variant = _plan_evictions(category, c, value)
	if victims == null:
		stats["rejected"] = int(stats["rejected"]) + 1
		return 0
	for vid in victims as Array:
		var v: Dictionary = _live[vid]
		var vcat: String = v["category"]
		_remove(int(vid))
		stats["evicted"] = int(stats["evicted"]) + 1
		evicted.emit(int(vid), vcat)
	var id := _next_id
	_next_id += 1
	_live[id] = {"category": category, "cost": c, "priority": priority, "value": value}
	_cat_effects[category] = int(_cat_effects.get(category, 0)) + 1
	_cat_particles[category] = int(_cat_particles.get(category, 0)) + c
	_particles_total += c
	stats["accepted"] = int(stats["accepted"]) + 1
	last_id = id
	return id


## Returns the ids to evict (possibly empty), or null when the request cannot fit.
func _plan_evictions(category: String, cost: int, value: float) -> Variant:
	var effects := int(_cat_effects.get(category, 0)) + 1
	var cat_particles := int(_cat_particles.get(category, 0)) + cost
	var total := _particles_total + cost
	var cap_e := max_effects(category)
	var cap_p := max_particles(category)
	var cap_t := max_total_particles()
	if effects <= cap_e and cat_particles <= cap_p and total <= cap_t:
		return []
	var candidates: Array = []
	for id in _live:
		var e: Dictionary = _live[id]
		if float(e["value"]) < value:
			candidates.append(id)
	candidates.sort_custom(func(a, b) -> bool: return float(_live[a]["value"]) < float(_live[b]["value"]))
	var victims: Array = []
	for id in candidates:
		var e: Dictionary = _live[id]
		var same: bool = e["category"] == category
		var over_cat := effects > cap_e or cat_particles > cap_p
		var over_total := total > cap_t
		if not (same and over_cat) and not over_total:
			continue
		victims.append(id)
		var ecost: int = e["cost"]
		total -= ecost
		if same:
			effects -= 1
			cat_particles -= ecost
		if effects <= cap_e and cat_particles <= cap_p and total <= cap_t:
			return victims
	return null


func release(id: int) -> void:
	if _live.has(id):
		_remove(id)
		stats["released"] = int(stats["released"]) + 1


func _remove(id: int) -> void:
	var e: Dictionary = _live[id]
	var cat: String = e["category"]
	var cost: int = e["cost"]
	_cat_effects[cat] = int(_cat_effects.get(cat, 0)) - 1
	_cat_particles[cat] = int(_cat_particles.get(cat, 0)) - cost
	_particles_total -= cost
	_live.erase(id)


func is_live(id: int) -> bool:
	return _live.has(id)


func active_effects(category: String = "") -> int:
	if category == "":
		return _live.size()
	return int(_cat_effects.get(category, 0))


func active_particles(category: String = "") -> int:
	if category == "":
		return _particles_total
	return int(_cat_particles.get(category, 0))


func clear() -> void:
	_live.clear()
	_cat_effects.clear()
	_cat_particles.clear()
	_particles_total = 0


func get_stats() -> Dictionary:
	var out := stats.duplicate()
	out["active_effects"] = _live.size()
	out["active_particles"] = _particles_total
	out["tier"] = tier
	return out
