extends RefCounted
## Short-lived PvE pursuit pressure. Combat stress is NOT a damage-over-time
## effect, does not alter combat energy, and never exposes hidden enemy IDs.
## Only living infected actively targeting a survivor can raise this meter.

const Zombie = preload("res://scripts/shared/zombie.gd")

const MAX_STRESS := 100.0
const THREAT_RADIUS := 22.0
const SUPPORT_RADIUS := 12.0
const SCAN_SECONDS := 0.5
const HUD_THRESHOLD := 10.0
const RISE_PER_SECOND := 5.0
const FIELD_RECOVERY_PER_SECOND := 2.0
const SHELTER_RECOVERY_PER_SECOND := 5.0
const HUB_RECOVERY_PER_SECOND := 10.0
const ALLY_RISE_MULTIPLIER := 0.6
const MAX_PRESSURE := 2.5
const MAX_REGEN_PENALTY := 0.40


## Iterate server-owned, instantiated infected only. No client-provided
## target coordinates, enemies or claimed visibility are accepted.
static func pressure(zombies: Dictionary, peer_id: int, position: Vector3) -> float:
	if peer_id <= 0 or not position.is_finite():
		return 0.0
	var near: float = 0.0
	var at := Vector2(position.x, position.z)
	for infected in zombies.values():
		if infected == null or not infected.is_alive() or infected.target_id != peer_id:
			continue
		if infected.state != Zombie.State.CHASE and infected.state != Zombie.State.ATTACK:
			continue
		if not infected.position.is_finite():
			continue
		var source := Vector2(infected.position.x, infected.position.z)
		var distance_squared: float = at.distance_squared_to(source)
		if not is_finite(distance_squared) or distance_squared > THREAT_RADIUS * THREAT_RADIUS:
			continue
		var weight: float = 2.0 if infected.raid_boss else (
			1.5 if infected.elite else 1.0)
		near = minf(MAX_PRESSURE, near + weight)
		if near >= MAX_PRESSURE:
			break
	return near


## Nearby and actually living party allies help avoid a solo stamina spiral.
## Group membership is verified via the authoritative party registry.
static func has_live_companion(peer_id: int, position: Vector3,
		players: Dictionary, parties) -> bool:
	if peer_id <= 0 or not position.is_finite():
		return false
	for member_id in parties.members_of(peer_id):
		if int(member_id) == peer_id:
			continue
		var member = players.get(int(member_id))
		if member == null or not member.survival.alive or not member.position.is_finite():
			continue
		var gap := Vector2(position.x - member.position.x,
			position.z - member.position.z)
		var distance_squared: float = gap.length_squared()
		if is_finite(distance_squared) and distance_squared <= SUPPORT_RADIUS * SUPPORT_RADIUS:
			return true
	return false


## No bonus is granted for fleeing fights by relogging: ephemeral pressure
## simply goes to zero, as with respawning. No recoverable XP or currency.
static func advance(current: float, delta: float, pressure_value: float,
		safe_hub: bool, shelter: bool, supported: bool) -> float:
	if not is_finite(delta) or delta <= 0.0:
		return clampf(current, 0.0, MAX_STRESS) if is_finite(current) else 0.0
	var value: float = clampf(current, 0.0, MAX_STRESS) if is_finite(current) else 0.0
	if safe_hub:
		return maxf(0.0, value - HUB_RECOVERY_PER_SECOND * delta)
	var real_pressure: float = clampf(pressure_value, 0.0, MAX_PRESSURE) if is_finite(pressure_value) else 0.0
	if real_pressure > 0.0:
		var rally: float = ALLY_RISE_MULTIPLIER if supported else 1.0
		return minf(MAX_STRESS, value + RISE_PER_SECOND * real_pressure * rally * delta)
	var recovery: float = SHELTER_RECOVERY_PER_SECOND if shelter else FIELD_RECOVERY_PER_SECOND
	return maxf(0.0, value - recovery * delta)


static func regen_multiplier(value: float) -> float:
	if not is_finite(value):
		return 1.0
	return 1.0 - MAX_REGEN_PENALTY * clampf(value / MAX_STRESS, 0.0, 1.0)
