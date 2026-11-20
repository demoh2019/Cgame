extends SceneTree

const Interest = preload("res://addons/visual_quality/ai_interest_manager.gd")


func _initialize() -> void:
	assert(Interest.should_simulate(20.0 * 20.0, false, 24.0, 6.0))
	assert(not Interest.should_simulate(26.0 * 26.0, false, 24.0, 6.0))
	assert(Interest.should_simulate(26.0 * 26.0, true, 24.0, 6.0))
	assert(not Interest.should_simulate(32.0 * 32.0, true, 24.0, 6.0))
	assert(not Interest.should_simulate(NAN, true, 24.0, 6.0))
	assert(not Interest.should_simulate(-1.0, true, 24.0, 6.0))
	var ai = Interest.new()
	ai.set_quality_profile(0)
	assert(ai.simulation_radius == 18.0 and ai.max_cells_per_update == 6)
	ai.set_quality_profile(1)
	assert(ai.simulation_radius == 28.0 and ai.max_cells_per_update == 8)
	ai.set_quality_profile(2)
	assert(ai.simulation_radius == 42.0 and ai.max_cells_per_update == 12)
	ai.set_global_enabled(false)
	assert(not ai.globally_enabled)
	ai.free()
	print("World AI interest LOD: 12 validation checks passed")
	quit(0)
