extends Node
class_name WorldCombatant3D
## A reusable health/damage/status component for players and streamed actors.
## Deterministic armor, teams, i-frames and stun; no scene-tree dependencies.

signal damage_taken(amount: float, health_left: float)
signal defeated()
signal stun_changed(stunned: bool)

const TEAM_NEUTRAL: int = 0
const TEAM_PLAYER: int = 1
const TEAM_HOSTILE: int = 2

@export_range(0.0, 500.0, 1.0) var armor: float = 12.0
@export_range(0.0, 2.0, 0.05) var hit_immunity_seconds: float = 0.15
@export var team_id: int = TEAM_NEUTRAL

var attributes: WorldAttributes3D
var immunity_remaining: float = 0.0
var stun_remaining: float = 0.0
var _defeat_reported: bool = false


func _physics_process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	immunity_remaining = maxf(immunity_remaining - delta, 0.0)
	if stun_remaining > 0.0:
		stun_remaining = maxf(stun_remaining - delta, 0.0)
		if stun_remaining == 0.0:
			stun_changed.emit(false)


func is_alive() -> bool:
	return is_instance_valid(attributes) and attributes.health > 0.0


func can_receive_hit(source_team: int) -> bool:
	return is_alive() and immunity_remaining <= 0.0 and not (
		source_team != TEAM_NEUTRAL and source_team == team_id)


func receive_damage(raw_damage: float, source_team: int,
		stun_seconds: float = 0.0) -> float:
	if not is_finite(raw_damage) or raw_damage <= 0.0 or not can_receive_hit(source_team):
		return 0.0
	var actual: float = compute_damage(raw_damage, armor)
	var before: float = attributes.health
	if not attributes.apply_damage(actual):
		return 0.0
	actual = before - attributes.health
	immunity_remaining = hit_immunity_seconds
	if is_finite(stun_seconds) and stun_seconds > 0.0 and attributes.health > 0.0:
		apply_stun(stun_seconds)
	damage_taken.emit(actual, attributes.health)
	if attributes.health <= 0.0 and not _defeat_reported:
		_defeat_reported = true
		defeated.emit()
	return actual


func apply_stun(seconds: float) -> bool:
	if not is_alive() or not is_finite(seconds) or seconds <= 0.0:
		return false
	var already: bool = stun_remaining > 0.0
	stun_remaining = maxf(stun_remaining, minf(seconds, 10.0))
	if not already:
		stun_changed.emit(true)
	return true


func is_stunned() -> bool:
	return stun_remaining > 0.0


func restore_health(value: float, stored_stun: float = 0.0) -> void:
	if not is_instance_valid(attributes) or not is_finite(value):
		return
	attributes.restore_vitals({"health": value, "stamina": attributes.stamina})
	immunity_remaining = 0.0
	stun_remaining = clampf(stored_stun, 0.0, 10.0) if is_finite(stored_stun) else 0.0
	_defeat_reported = attributes.health <= 0.0
	stun_changed.emit(is_stunned())


static func compute_damage(raw_damage: float, armor_value: float) -> float:
	if not is_finite(raw_damage) or not is_finite(armor_value) or raw_damage <= 0.0:
		return 0.0
	return raw_damage * 100.0 / (100.0 + clampf(armor_value, 0.0, 500.0))
