extends RefCounted
## Homestead farming (Albion Online island farming, adapted to the open world).
## Survivors plant seeds on up to 9 personal plots in the green zone. Crops grow in
## real server time, persist with the world and can only be harvested by their owner.
## Harvests yield food (or wheat for bread) and sometimes seeds back.

const CROPS := {
	"carrot": {"seed": "carrot_seeds", "seconds": 900.0, "min": 2, "max": 4},
	"potato": {"seed": "potato_seeds", "seconds": 1200.0, "min": 2, "max": 5},
	"wheat": {"seed": "wheat_seeds", "seconds": 1500.0, "min": 3, "max": 6},
}
const MAX_PLOTS := 9
const MAX_PLOTS_TOTAL := 600
const MIN_SPACING := 1.4
const PLANT_REACH := 3.0
const SEED_RETURN_CHANCE := 0.35


static func crop_for_seed(seed_id: String) -> String:
	for crop in CROPS:
		if str(CROPS[crop]["seed"]) == seed_id:
			return crop
	return ""


## Growth 0..1 at server time `now`.
static func progress(plot: Dictionary, now: float) -> float:
	var planted: float = float(plot.get("planted", now))
	var total: float = float(plot.get("grow", 1.0))
	# Clock and crop records are persisted; corrupt/rewound time cannot
	# make a crop instantly ripe or send NaN growth to client snapshots.
	if not is_finite(now) or not is_finite(planted) or not is_finite(total) or total <= 0.0:
		return 0.0
	if now <= planted:
		return 0.0
	return clampf((now - planted) / total, 0.0, 1.0)


static func is_ripe(plot: Dictionary, now: float) -> bool:
	return progress(plot, now) >= 1.0


## Why a plot cannot be placed here ("" when it can).
static func placement_refusal(zone: int, water: bool, spot: Vector2, plots: Dictionary, own_count: int) -> String:
	if not spot.is_finite():
		return "invalid_position"
	if zone != 0:
		return "green_zone_only"
	if water:
		return "water"
	if own_count >= MAX_PLOTS:
		return "too_many_plots"
	if plots.size() >= MAX_PLOTS_TOTAL:
		return "world_full"
	for plot in plots.values():
		var existing := Vector2(float(plot.get("x", NAN)), float(plot.get("z", NAN)))
		if existing.is_finite() and existing.distance_squared_to(spot) < MIN_SPACING * MIN_SPACING:
			return "too_close"
	return ""


## Harvest: {crop: n} plus maybe seeds back.
static func harvest_yield(crop: String, rng: RandomNumberGenerator) -> Dictionary:
	var info: Dictionary = CROPS.get(crop, {})
	if info.is_empty():
		return {}
	var result: Dictionary = {crop: rng.randi_range(int(info["min"]), int(info["max"]))}
	if rng.randf() < SEED_RETURN_CHANCE:
		result[str(info["seed"])] = rng.randi_range(1, 2)
	return result
