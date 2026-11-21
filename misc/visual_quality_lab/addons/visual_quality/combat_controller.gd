extends Node
class_name WorldCombatDirector3D
## Local combat orchestration over *loaded nearby* streamed cells.
## Scene-free selector is independently testable; no global actor scans.

signal combat_message(message: String)
signal attack_landed(target: Node3D, amount: float)

@export_range(1.0, 8.0, 0.25) var melee_range: float = 4.0
@export_range(2.0, 10.0, 0.5) var pulse_range: float = 5.5
@export_range(0.0, 1.0, 0.05) var min_facing_dot: float = 0.25
@export_range(1.0, 100.0, 1.0) var melee_damage: float = 36.0
@export_range(1.0, 80.0, 1.0) var pulse_damage: float = 18.0
@export_range(1, 12, 1) var max_pulse_targets: int = 8

var streamer: WorldStreamer3D
var player: Node3D
var camera: Camera3D
var player_combatant: WorldCombatant3D
var player_attributes: WorldAttributes3D
var strike_cooldown: float = 0.0
var pulse_cooldown: float = 0.0


func _physics_process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	strike_cooldown = maxf(strike_cooldown - delta, 0.0)
	pulse_cooldown = maxf(pulse_cooldown - delta, 0.0)


func strike() -> bool:
	if strike_cooldown > 0.0 or not _can_player_attack(12.0):
		combat_message.emit("Удар недоступен: выносливость или перезарядка")
		return false
	var candidates: Array[Dictionary] = _nearby_hostiles(melee_range)
	var selected: Dictionary = choose_facing_target(candidates, camera.global_position,
		-camera.global_basis.z, melee_range, min_facing_dot)
	if selected.is_empty():
		combat_message.emit("Нет врага перед вами на расстоянии удара")
		return false
	var enemy: WorldHostileSentry3D = selected["actor"]
	if not is_instance_valid(enemy) or not enemy.combatant.can_receive_hit(player_combatant.team_id):
		return false
	if not player_attributes.try_spend_stamina(12.0):
		return false
	var dealt: float = enemy.combatant.receive_damage(melee_damage, player_combatant.team_id)
	if dealt > 0.0:
		strike_cooldown = 0.55
		attack_landed.emit(enemy, dealt)
		combat_message.emit("Удар: -%.0f здоровья стражу" % dealt)
		return true
	return false


func shockwave() -> int:
	if pulse_cooldown > 0.0 or not _can_player_attack(35.0):
		combat_message.emit("Импульс недоступен: выносливость или перезарядка")
		return 0
	var candidates: Array[Dictionary] = _nearby_hostiles(pulse_range)
	var eligible: Array[Dictionary] = []
	for candidate in candidates:
		var enemy: WorldHostileSentry3D = candidate["actor"]
		if is_instance_valid(enemy) and enemy.combatant.can_receive_hit(player_combatant.team_id):
			eligible.append(candidate)
	eligible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ad: float = camera.global_position.distance_squared_to(a["position"])
		var bd: float = camera.global_position.distance_squared_to(b["position"])
		if not is_equal_approx(ad, bd):
			return ad < bd
		return str(a["uid"]) < str(b["uid"])
	)
	if eligible.is_empty():
		combat_message.emit("Рядом нет врагов для импульса")
		return 0
	if not player_attributes.try_spend_stamina(35.0):
		return 0
	var hits: int = 0
	for candidate in eligible:
		if hits >= max_pulse_targets:
			break
		var enemy: WorldHostileSentry3D = candidate["actor"]
		var dealt: float = enemy.combatant.receive_damage(pulse_damage,
			player_combatant.team_id, 2.5)
		if dealt > 0.0:
			hits += 1
			attack_landed.emit(enemy, dealt)
	if hits > 0:
		pulse_cooldown = 7.0
		combat_message.emit("Импульс оглушил стражей: %d" % hits)
	return hits


func _can_player_attack(cost: float) -> bool:
	return is_instance_valid(player) and is_instance_valid(camera) \
		and is_instance_valid(player_combatant) and player_combatant.is_alive() \
		and not player_combatant.is_stunned() and is_instance_valid(player_attributes) \
		and player_attributes.stamina >= cost and is_instance_valid(streamer)


func _nearby_hostiles(radius: float) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if not is_instance_valid(streamer) or not is_instance_valid(camera) or streamer.cell_size <= 0.0:
		return found
	var center: Vector2i = streamer.cell_at_local_position(
		streamer.to_local(camera.global_position), streamer.cell_size)
	var neighborhood: int = clampi(ceili(radius / streamer.cell_size) + 1, 1, 3)
	for z in range(center.y - neighborhood, center.y + neighborhood + 1):
		for x in range(center.x - neighborhood, center.x + neighborhood + 1):
			var cell: Node3D = streamer.get_active_cell(Vector2i(x, z))
			if not is_instance_valid(cell) or not cell.has_method("get_hostile_sentry"):
				continue
			var enemy: WorldHostileSentry3D = cell.call("get_hostile_sentry")
			if not is_instance_valid(enemy) or not enemy.combatant.is_alive():
				continue
			found.append({"actor": enemy, "position": enemy.global_position + Vector3.UP,
				"uid": "%d:%d" % [x, z]})
	return found


## Pure selector: stable ties and distance/cone validation. It doesn't store
## actor references once the action returns, so streaming can evict safely.
static func choose_facing_target(candidates: Array[Dictionary], origin: Vector3,
		forward: Vector3, maximum_distance: float, minimum_dot: float) -> Dictionary:
	if maximum_distance <= 0.0 or forward.length_squared() < 0.001:
		return {}
	var facing: Vector3 = forward.normalized()
	var best: Dictionary = {}
	var lowest: float = INF
	for target in candidates:
		if typeof(target.get("position")) != TYPE_VECTOR3:
			continue
		var pos: Vector3 = target["position"]
		if not is_finite(pos.x) or not is_finite(pos.y) or not is_finite(pos.z):
			continue
		var toward: Vector3 = pos - origin
		var distance: float = toward.length()
		if distance > maximum_distance or distance < 0.001:
			continue
		if facing.dot(toward / distance) < minimum_dot:
			continue
		if distance < lowest - 0.0001 or (absf(distance - lowest) <= 0.0001 \
				and str(target.get("uid", "")) < str(best.get("uid", "~"))):
			lowest = distance
			best = target
	return best.duplicate()
