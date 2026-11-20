extends SceneTree

const Atmosphere = preload("res://addons/visual_quality/atmosphere_controller.gd")


func _initialize() -> void:
	# Noon and midnight must be reproducible, including wrapped times.
	assert(is_equal_approx(Atmosphere.sunlight_factor(12.0), 1.0))
	assert(is_equal_approx(Atmosphere.sunlight_factor(0.0), 0.0))
	assert(is_equal_approx(Atmosphere.sunlight_factor(24.0), 0.0))
	assert(is_equal_approx(Atmosphere.sunlight_factor(-12.0), 1.0))
	assert(is_equal_approx(Atmosphere.sunlight_factor(36.0), 1.0))
	assert(Atmosphere.sunlight_factor(6.0) < 0.3)
	assert(Atmosphere.sunlight_factor(18.0) < 0.3)
	assert(is_equal_approx(Atmosphere.fog_density_for(0.0), 0.005))
	assert(is_equal_approx(Atmosphere.fog_density_for(1.0), 0.035))
	assert(is_equal_approx(Atmosphere.fog_density_for(2.0), 0.035))
	assert(is_equal_approx(Atmosphere.fog_density_for(-1.0), 0.005))
	var atmosphere = Atmosphere.new()
	atmosphere.set_overcast(2.0)
	assert(is_equal_approx(atmosphere.overcast, 1.0))
	atmosphere.set_overcast(-1.0)
	assert(is_equal_approx(atmosphere.overcast, 0.0))
	atmosphere.set_hour(26.0)
	assert(is_equal_approx(atmosphere.hour, 2.0))
	atmosphere.set_auto_cycle(true)
	assert(atmosphere.auto_cycle)
	atmosphere.free()
	print("AtmosphereController3D: 15 checks passed")
	quit(0)
