@tool
extends Resource
class_name WaterProfile
## A bounded wave field shared by CPU queries and GPU water displacement.

const MAX_WAVES := 4

@export var waves: Array[WaterWave] = []


static func make_default() -> WaterProfile:
	var result := WaterProfile.new()
	var first := WaterWave.new()
	first.direction = Vector2(1, 0)
	first.amplitude = 0.35
	first.wavelength = 14.0
	first.angular_speed = 1.1
	var second := WaterWave.new()
	second.direction = Vector2(0.6, 0.8)
	second.amplitude = 0.14
	second.wavelength = 8.0
	second.angular_speed = 1.6
	second.phase = 1.0
	var third := WaterWave.new()
	third.direction = Vector2(-1, 0.2)
	third.amplitude = 0.07
	third.wavelength = 4.0
	third.angular_speed = 2.0
	third.phase = 2.0
	result.waves.assign([first, second, third])
	return result


func validation_error() -> String:
	if waves.size() > MAX_WAVES:
		return "WaterProfile supports at most 4 waves"
	for index in waves.size():
		var wave := waves[index]
		if wave == null:
			return "Null wave at index %d" % index
		var error := wave.validation_error()
		if not error.is_empty():
			return "Wave %d: %s" % [index, error]
	return ""


func sample(world_xz: Vector2, time_seconds: float) -> Dictionary:
	var problem := validation_error()
	if not problem.is_empty():
		return {"ok": false, "error": problem, "height": 0.0, "normal": Vector3.UP}
	if not world_xz.is_finite() or not is_finite(time_seconds):
		return {"ok": false, "error": "Nonfinite sample position or time", "height": 0.0, "normal": Vector3.UP}
	var height := 0.0
	var slope_x := 0.0
	var slope_z := 0.0
	for wave in waves:
		var value := wave.evaluate(world_xz, time_seconds)
		height += value.x
		slope_x += value.y
		slope_z += value.z
	var normal := Vector3(-slope_x, 1, -slope_z).normalized()
	return {"ok": true, "error": "", "height": height, "normal": normal}


func wave_parameters(index: int) -> Dictionary:
	# Four slots are always provided, disabled slots have zero amplitude.
	if index < 0 or index >= MAX_WAVES or index >= waves.size() or waves[index] == null:
		return {"wave": Vector4(1, 0, 0, 1), "motion": Vector2.ZERO}
	var w: WaterWave = waves[index]
	if not w.validation_error().is_empty():
		return {"wave": Vector4(1, 0, 0, 1), "motion": Vector2.ZERO}
	var direction := w.direction.normalized()
	return {
		"wave": Vector4(direction.x, direction.y, w.amplitude, w.wavelength),
		"motion": Vector2(w.angular_speed, w.phase)
	}
