extends RefCounted
## Fish shoals: quality budget and deep-water placement.
const FishShoals = preload("res://scripts/client/fish_shoals.gd")
const Defs = preload("res://scripts/shared/defs.gd")


class FakeWorld:
	var lake_floor: float
	func _init(floor_height: float) -> void:
		lake_floor = floor_height
	func height_at(x: float, _z: float) -> float:
		return lake_floor if x < 100.0 else Defs.WATER_LEVEL + 3.0


func run(t) -> void:
	t.current = "fish shoals: budget and water depth"
	t.eq(FishShoals.shoal_size(0), 0, "Performance draws no fish")
	t.check(FishShoals.shoal_size(3) > FishShoals.shoal_size(1), "Ultra has the bigger shoal")
	var lake := FakeWorld.new(Defs.WATER_LEVEL - 3.0)
	t.check(FishShoals.deep_enough(lake, 0.0, 0.0), "deep lake fits a shoal")
	t.check(not FishShoals.deep_enough(lake, 97.0, 0.0), "shoal never touches the shore")
	var puddle := FakeWorld.new(Defs.WATER_LEVEL - 0.5)
	t.check(not FishShoals.deep_enough(puddle, 0.0, 0.0), "shallow water has no fish")
