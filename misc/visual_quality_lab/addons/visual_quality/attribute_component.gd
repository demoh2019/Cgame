extends Node
class_name WorldAttributes3D
## Reusable attributes: base values + equipment + temporary gameplay effects.
## All modifying methods validate finite numbers and emit change signals.

signal attributes_changed()
signal vitals_changed(health: float, stamina: float)
signal effect_expired(effect_id: String)

const BASE: Dictionary = {
	"max_health": 100.0, "max_stamina": 100.0,
	"move_speed": 1.0, "stamina_regen": 16.0
}
const MAX_EFFECTS: int = 16

@export_range(0.0, 3.0, 0.1) var regen_delay_after_use: float = 0.8

var health: float = 100.0
var stamina: float = 100.0
var _regen_pause: float = 0.0
var _equipment: Dictionary = {}  # slot -> validated stat modifiers
var _effects: Dictionary = {}    # effect ID -> {modifiers, remaining}


func _physics_process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	var expired: Array[String] = []
	for effect_id in _effects.keys():
		_effects[effect_id]["remaining"] = float(_effects[effect_id]["remaining"]) - delta
		if float(_effects[effect_id]["remaining"]) <= 0.0:
			expired.append(effect_id)
	for effect_id in expired:
		_effects.erase(effect_id)
		effect_expired.emit(effect_id)
	if not expired.is_empty():
		_on_attributes_changed()
	_regen_pause = maxf(_regen_pause - delta, 0.0)
	if _regen_pause <= 0.0 and stamina < get_stat("max_stamina"):
		set_stamina(stamina + get_stat("stamina_regen") * delta)


func get_stat(stat_id: String) -> float:
	if not BASE.has(stat_id):
		return 0.0
	var value: float = float(BASE[stat_id])
	for modifiers in _equipment.values():
		value += float((modifiers as Dictionary).get(stat_id, 0.0))
	for effect in _effects.values():
		value += float((effect["modifiers"] as Dictionary).get(stat_id, 0.0))
	match stat_id:
		"move_speed":
			return clampf(value, 0.25, 4.0)
		"max_health", "max_stamina":
			return clampf(value, 1.0, 10000.0)
		"stamina_regen":
			return clampf(value, 0.0, 1000.0)
	return value


func set_equipment(slot: String, modifiers: Dictionary) -> bool:
	if slot.is_empty() or slot.length() > 40:
		return false
	var clean: Dictionary = validate_modifiers(modifiers)
	if clean.is_empty():
		return false
	_equipment[slot] = clean
	_on_attributes_changed()
	return true


func remove_equipment(slot: String) -> void:
	if _equipment.erase(slot):
		_on_attributes_changed()


func apply_timed_effect(effect_id: String, modifiers: Dictionary, seconds: float) -> bool:
	if effect_id.is_empty() or effect_id.length() > 64 or not is_finite(seconds) \
			or seconds <= 0.0 or seconds > 300.0:
		return false
	if not _effects.has(effect_id) and _effects.size() >= MAX_EFFECTS:
		return false
	var clean: Dictionary = validate_modifiers(modifiers)
	if clean.is_empty():
		return false
	_effects[effect_id] = {"modifiers": clean, "remaining": seconds}
	_on_attributes_changed()
	return true


func remove_timed_effect(effect_id: String) -> void:
	if _effects.erase(effect_id):
		_on_attributes_changed()


func effect_remaining(effect_id: String) -> float:
	return float(_effects.get(effect_id, {}).get("remaining", 0.0))


func try_spend_stamina(cost: float) -> bool:
	if not is_finite(cost) or cost <= 0.0 or stamina + 0.0001 < cost:
		return false
	set_stamina(maxf(stamina - cost, 0.0))
	_regen_pause = regen_delay_after_use
	return true


func set_stamina(value: float) -> void:
	if not is_finite(value):
		return
	var new_value: float = clampf(value, 0.0, get_stat("max_stamina"))
	if not is_equal_approx(new_value, stamina):
		stamina = new_value
		vitals_changed.emit(health, stamina)


func apply_damage(amount: float) -> bool:
	if not is_finite(amount) or amount <= 0.0 or health <= 0.0:
		return false
	health = maxf(health - amount, 0.0)
	vitals_changed.emit(health, stamina)
	return true


func heal(amount: float) -> bool:
	if not is_finite(amount) or amount <= 0.0 or health <= 0.0:
		return false
	health = minf(health + amount, get_stat("max_health"))
	vitals_changed.emit(health, stamina)
	return true


func vitals_snapshot() -> Dictionary:
	return {"health": health, "stamina": stamina}


func restore_vitals(snapshot: Dictionary) -> void:
	if typeof(snapshot.get("health")) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(snapshot["health"])):
		health = clampf(float(snapshot["health"]), 0.0, get_stat("max_health"))
	if typeof(snapshot.get("stamina")) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(snapshot["stamina"])):
		stamina = clampf(float(snapshot["stamina"]), 0.0, get_stat("max_stamina"))
	vitals_changed.emit(health, stamina)


func _on_attributes_changed() -> void:
	health = minf(health, get_stat("max_health"))
	stamina = minf(stamina, get_stat("max_stamina"))
	attributes_changed.emit()
	vitals_changed.emit(health, stamina)


static func validate_modifiers(modifiers: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in modifiers.keys():
		if typeof(key) != TYPE_STRING or not BASE.has(key):
			return {}
		var value: Variant = modifiers[key]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) \
				or absf(float(value)) > 500.0:
			return {}
		out[key] = float(value)
	return out
