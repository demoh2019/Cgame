extends Node
class_name WorldAbilitySystem3D
## Small, reusable ability executor with stamina costs, cooldowns and effects.
## No multiplayer prediction, effects replication or animation tasks implied.

signal ability_activated(ability_id: String)
signal ability_rejected(ability_id: String)

const DEFINITIONS: Dictionary = {
	"dash": {"stamina_cost": 30.0, "cooldown": 3.0, "duration": 0.65,
		"modifiers": {"move_speed": 0.85}},
	"focus": {"stamina_cost": 10.0, "cooldown": 12.0, "duration": 5.0,
		"modifiers": {"stamina_regen": 25.0}}
}

var attributes: WorldAttributes3D
var _cooldowns: Dictionary = {}


func _physics_process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	for ability_id in _cooldowns.keys():
		var left: float = maxf(float(_cooldowns[ability_id]) - delta, 0.0)
		if left <= 0.0:
			_cooldowns.erase(ability_id)
		else:
			_cooldowns[ability_id] = left


func get_cooldown(ability_id: String) -> float:
	return float(_cooldowns.get(ability_id, 0.0))


func can_activate(ability_id: String) -> bool:
	if not DEFINITIONS.has(ability_id) or not is_instance_valid(attributes):
		return false
	var definition: Dictionary = DEFINITIONS[ability_id]
	return get_cooldown(ability_id) <= 0.0 \
		and attributes.health > 0.0 \
		and attributes.stamina >= float(definition["stamina_cost"])


func activate(ability_id: String) -> bool:
	if not can_activate(ability_id):
		ability_rejected.emit(ability_id)
		return false
	var definition: Dictionary = DEFINITIONS[ability_id]
	if not attributes.apply_timed_effect(ability_id, definition["modifiers"],
			float(definition["duration"])):
		ability_rejected.emit(ability_id)
		return false
	if not attributes.try_spend_stamina(float(definition["stamina_cost"])):
		attributes.remove_timed_effect(ability_id)
		ability_rejected.emit(ability_id)
		return false
	_cooldowns[ability_id] = float(definition["cooldown"])
	ability_activated.emit(ability_id)
	return true


func cooldowns_snapshot() -> Dictionary:
	return _cooldowns.duplicate(true)


static func get_definition(ability_id: String) -> Dictionary:
	return DEFINITIONS.get(ability_id, {}).duplicate(true)
