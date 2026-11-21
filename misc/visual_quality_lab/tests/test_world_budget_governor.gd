extends SceneTree

const Governor = preload("res://addons/visual_quality/world_budget_governor.gd")
const Streamer = preload("res://addons/visual_quality/world_streamer.gd")
const Interest = preload("res://addons/visual_quality/ai_interest_manager.gd")


func _initialize() -> void:
	assert(Governor.next_budget(2, -1, 1, 4) == 1)
	assert(Governor.next_budget(1, -1, 1, 4) == 1)
	assert(Governor.next_budget(4, 1, 1, 4) == 4)
	var streamer = Streamer.new()
	var interest = Interest.new()
	var governor = Governor.new()
	governor.streamer = streamer
	governor.ai_interest = interest
	governor.set_quality_profile(1)
	assert(governor.current_spawn_budget() == 2)
	assert(governor.current_ai_budget() == 8)
	governor.evaluate_cpu_sample(NAN)
	governor.evaluate_cpu_sample(0.0)
	assert(governor.current_spawn_budget() == 2, "Invalid samples cannot throttle")
	for i in range(2):
		governor.evaluate_cpu_sample(30.0)
	assert(governor.current_spawn_budget() == 2, "Requires sustained overload")
	governor.evaluate_cpu_sample(30.0)
	assert(governor.current_spawn_budget() == 1)
	assert(governor.current_ai_budget() == 6)
	governor.evaluate_cpu_sample(16.0)
	assert(governor.current_spawn_budget() == 1, "Dead zone prevents oscillation")
	for i in range(5):
		governor.evaluate_cpu_sample(5.0)
	assert(governor.current_spawn_budget() == 2)
	assert(governor.current_ai_budget() == 8)
	governor.set_quality_profile(0)
	assert(governor.current_spawn_budget() == 1)
	assert(governor.current_ai_budget() == 6)
	governor.set_quality_profile(2)
	assert(governor.current_spawn_budget() == 4)
	assert(governor.current_ai_budget() == 12)
	governor.set_automatic_enabled(false)
	for i in range(10):
		governor.evaluate_cpu_sample(999.0)
	assert(governor.current_spawn_budget() == 4)
	assert(governor.current_ai_budget() == 12)
	governor.free()
	streamer.free()
	interest.free()
	print("WorldBudgetGovernor3D: 20 checks passed")
	quit(0)
