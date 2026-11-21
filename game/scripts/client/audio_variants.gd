extends RefCounted
## Unreal Sound Cue-style weighted variation without replacement.
## One externally supplied uniform draw per event; no RNG calls here.
## Custom engines use WeightedChoiceTable.sample_excluding(), while stock
## Godot and older binaries use the same deterministic fallback.

var _weights: PackedFloat64Array = PackedFloat64Array()
var _played: PackedInt32Array = PackedInt32Array()
var _positive_count: int = 0
var _native: Object = null


func _init(weights: PackedFloat64Array, prefer_native: bool = true) -> void:
	if weights.is_empty() or weights.size() > 4096:
		return
	var total: float = 0.0
	for weight in weights:
		if not is_finite(weight) or weight < 0.0 or weight > 1000000000000.0 - total:
			_positive_count = 0
			return
		total += weight
		if weight > 0.0:
			_positive_count += 1
	if _positive_count == 0:
		return
	_weights = weights.duplicate()
	if prefer_native and ClassDB.class_exists("WeightedChoiceTable"):
		var table: Object = ClassDB.instantiate("WeightedChoiceTable")
		if table != null and table.has_method("sample_excluding") and bool(table.call("configure", _weights)):
			_native = table


## Each positive-weight clip appears once per cycle. A rejected roll
## neither consumes a clip nor resets the completed cycle.
func choose(unit: float) -> int:
	if _positive_count == 0 or not is_finite(unit) or unit < 0.0 or unit >= 1.0:
		return -1
	if _played.size() == _positive_count:
		_played.clear()
	var index: int = -1
	if _native != null:
		index = int(_native.call("sample_excluding", unit, _played))
	else:
		index = _fallback(unit)
	if index >= 0:
		_played.append(index)
	return index


func _fallback(unit: float) -> int:
	var remaining: float = 0.0
	for i in _weights.size():
		if not _played.has(i):
			remaining += _weights[i]
	if remaining <= 0.0:
		return -1
	var target: float = unit * remaining
	var accumulated: float = 0.0
	var last_valid: int = -1
	for i in _weights.size():
		if _played.has(i) or _weights[i] <= 0.0:
			continue
		last_valid = i
		accumulated += _weights[i]
		if target < accumulated:
			return i
	return last_valid # Same near-1 rounding behavior as native.


func get_played_count() -> int:
	return _played.size()


func reset() -> void:
	_played.clear()
