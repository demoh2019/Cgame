extends RefCounted
## A short PvE-only follow-up for a server-confirmed frontal melee parry.
## The impact target and weapon are session-only; clients cannot fabricate them.

const MeleeParry = preload("res://scripts/shared/melee_parry.gd")
const WINDOW_SECONDS := 2.25
const DAMAGE_FACTOR := 1.40


static func clear(player) -> void:
	if player == null:
		return
	player.riposte_seconds = 0.0
	player.riposte_target_id = -1
	player.riposte_weapon = ""


## Called only at the actual server-owned impact, never at F8 activation.
static func arm(player, infected) -> bool:
	if player == null:
		return false
	clear(player)
	if infected == null or not infected.is_alive() or infected.raid_boss:
		return false
	if not player.survival.alive or player.mounted or not MeleeParry.equipped(player.inventory):
		return false
	player.riposte_seconds = WINDOW_SECONDS
	player.riposte_target_id = infected.id
	player.riposte_weapon = player.inventory.weapon
	return true


## Normal hit resolution and reach are enforced by GameServer._find_hit.
static func can_strike(player, infected, weapon: String) -> bool:
	if player == null or infected == null or not infected.is_alive() or infected.raid_boss:
		return false
	var remaining: float = player.riposte_seconds
	if not is_finite(remaining) or remaining <= 0.0 or remaining > WINDOW_SECONDS:
		return false
	if player.riposte_target_id != infected.id or weapon.is_empty() or weapon != player.riposte_weapon:
		return false
	if not player.survival.alive or player.mounted or not MeleeParry.equipped(player.inventory):
		return false
	return player.inventory.weapon == weapon and player.inventory.count(weapon) > 0


static func tick(player, delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		clear(player)
		return
	if player.riposte_seconds <= 0.0:
		return
	if not player.survival.alive or player.mounted or not MeleeParry.equipped(player.inventory) or (
			player.inventory.weapon != player.riposte_weapon):
		clear(player)
		return
	player.riposte_seconds = maxf(0.0, player.riposte_seconds - delta)
	if player.riposte_seconds == 0.0:
		clear(player)
