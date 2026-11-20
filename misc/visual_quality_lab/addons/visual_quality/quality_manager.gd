extends Node
class_name VisualQualityManager
## Small, portable settings layer. Only affects its assigned Environment and
## adaptive resolution controller, never every viewport in the game.

signal settings_changed(profile: int, adaptive: bool)

enum Profile { ECO, BALANCED, CINEMATIC }

const DEFAULT_SAVE_PATH: String = "user://visual_quality_lab.cfg"

@export var save_path: String = DEFAULT_SAVE_PATH
@export var persist_settings: bool = true
@export var restore_environment_on_exit: bool = true

var target_environment: Environment
var adaptive_controller: AdaptiveResolution3D
var current_profile: int = Profile.BALANCED
var adaptive_enabled: bool = true
var _old_glow: bool = false
var _old_ssao: bool = false
var _old_ssil: bool = false
var _old_ssr: bool = false
var _has_old_environment: bool = false


func _ready() -> void:
	if target_environment != null:
		_old_glow = target_environment.glow_enabled
		_old_ssao = target_environment.ssao_enabled
		_old_ssil = target_environment.ssil_enabled
		_old_ssr = target_environment.ssr_enabled
		_has_old_environment = true
	load_settings()
	apply_settings()


func _exit_tree() -> void:
	if restore_environment_on_exit and _has_old_environment and target_environment != null:
		target_environment.glow_enabled = _old_glow
		target_environment.ssao_enabled = _old_ssao
		target_environment.ssil_enabled = _old_ssil
		target_environment.ssr_enabled = _old_ssr


static func validated_profile(value: Variant) -> int:
	if typeof(value) != TYPE_INT:
		return Profile.BALANCED
	if value < Profile.ECO or value > Profile.CINEMATIC:
		return Profile.BALANCED
	return value


static func profile_limits(profile: int) -> Vector2:
	match profile:
		Profile.ECO:
			return Vector2(0.60, 0.80)
		Profile.CINEMATIC:
			return Vector2(0.80, 1.00)
		_:
			return Vector2(0.67, 1.00)


func set_profile(value: int) -> void:
	current_profile = validated_profile(value)
	apply_settings()
	save_settings()


func set_adaptive_enabled(value: bool) -> void:
	adaptive_enabled = value
	apply_settings()
	save_settings()


func apply_settings() -> void:
	if adaptive_controller != null:
		var limits: Vector2 = profile_limits(current_profile)
		adaptive_controller.minimum_scale = limits.x
		adaptive_controller.maximum_scale = limits.y
		adaptive_controller.enabled = adaptive_enabled
		adaptive_controller.reset_to_maximum()
	if target_environment != null:
		var forward_plus: bool = RenderingServer.get_current_rendering_method() == "forward_plus"
		target_environment.glow_enabled = current_profile >= Profile.BALANCED and forward_plus
		target_environment.ssao_enabled = current_profile >= Profile.BALANCED and forward_plus
		target_environment.ssil_enabled = current_profile >= Profile.CINEMATIC and forward_plus
		target_environment.ssr_enabled = current_profile >= Profile.CINEMATIC and forward_plus
	settings_changed.emit(current_profile, adaptive_enabled)


func load_settings() -> void:
	if not persist_settings:
		return
	var file: ConfigFile = ConfigFile.new()
	if file.load(save_path) != OK:
		return
	current_profile = validated_profile(file.get_value("graphics", "profile", Profile.BALANCED))
	var stored_adaptive: Variant = file.get_value("graphics", "adaptive", true)
	adaptive_enabled = stored_adaptive if typeof(stored_adaptive) == TYPE_BOOL else true


func save_settings() -> void:
	if not persist_settings:
		return
	var file: ConfigFile = ConfigFile.new()
	file.set_value("graphics", "profile", int(current_profile))
	file.set_value("graphics", "adaptive", adaptive_enabled)
	var error: Error = file.save(save_path)
	if error != OK:
		push_warning("Visual Quality Lab: graphics settings not saved (%d)" % error)
