extends SceneTree

const Manager = preload("res://addons/visual_quality/quality_manager.gd")


func _initialize() -> void:
	assert(Manager.validated_profile(0) == Manager.Profile.ECO)
	assert(Manager.validated_profile(1) == Manager.Profile.BALANCED)
	assert(Manager.validated_profile(2) == Manager.Profile.CINEMATIC)
	assert(Manager.validated_profile(-1) == Manager.Profile.BALANCED)
	assert(Manager.validated_profile(3) == Manager.Profile.BALANCED)
	assert(Manager.validated_profile("bad") == Manager.Profile.BALANCED)
	assert(Manager.profile_limits(Manager.Profile.ECO) == Vector2(0.60, 0.80))
	assert(Manager.profile_limits(Manager.Profile.BALANCED) == Vector2(0.67, 1.0))
	assert(Manager.profile_limits(Manager.Profile.CINEMATIC) == Vector2(0.80, 1.0))
	var manager = Manager.new()
	manager.save_path = "user://visual_quality_lab_test.cfg"
	manager.set_profile(Manager.Profile.CINEMATIC)
	manager.set_adaptive_enabled(false)
	var other = Manager.new()
	other.save_path = manager.save_path
	other.load_settings()
	assert(other.current_profile == Manager.Profile.CINEMATIC)
	assert(not other.adaptive_enabled)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(manager.save_path))
	print("VisualQualityManager: 11 checks passed")
	quit(0)
