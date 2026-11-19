@tool
extends Resource
class_name WaterWave
## One analytic travelling sine wave. Speed is angular phase radians/second.

@export var direction: Vector2 = Vector2.RIGHT
@export_range(0.0, 1000.0, 0.01) var amplitude: float = 0.25
@export_range(0.01, 10000.0, 0.1) var wavelength: float = 12.0
@export_range(-100.0, 100.0, 0.01) var angular_speed: float = 1.0
@export_range(-6.283185, 6.283185, 0.01) var phase: float = 0.0


func validation_error() -> String:
	if not direction.is_finite() or direction.length_squared() < 0.000001:
		return "Wave direction must be finite and nonzero"
	if not is_finite(amplitude) or amplitude < 0.0:
		return "Wave amplitude must be finite and nonnegative"
	if not is_finite(wavelength) or wavelength < 0.01:
		return "Wave wavelength must be finite and >= 0.01"
	if not is_finite(angular_speed) or not is_finite(phase):
		return "Wave speed and phase must be finite"
	return ""


func evaluate(world_xz: Vector2, time_seconds: float) -> Vector3:
	# Returns (height, d(height)/dx, d(height)/dz).
	# Caller validates parameters and finite position/time.
	var direction_unit := direction.normalized()
	var wavenumber := TAU / wavelength
	var theta := wavenumber * direction_unit.dot(world_xz) + phase - angular_speed * time_seconds
	var value := amplitude * sin(theta)
	var slope := amplitude * wavenumber * cos(theta)
	return Vector3(value, slope * direction_unit.x, slope * direction_unit.y)
