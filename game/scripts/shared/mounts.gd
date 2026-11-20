extends RefCounted
## Bike travel permissions. Only the server decides mount speed and eligibility.

const ITEM_ID := "salvage_bike"
const SPEED_FACTOR := 1.9
const MANUAL_COOLDOWN := 2.0
const HIT_COOLDOWN := 12.0


static func refusal(player, now: float) -> String:
	if player.inventory.count(ITEM_ID) <= 0:
		return "missing_bike"
	if player.mount_cooldown > 0.0:
		return "cooldown"
	if player.inventory.movement_factor(player.skills.bonus("carry_capacity")) < 0.9999:
		return "overweight"
	if player.survival.fracture > 0.0:
		return "fracture"
	if player.survival.hunger <= 5.0 or player.survival.thirst <= 5.0:
		return "exhausted"
	if (player.combat_tag_until > now or player.attack_timer > 0.0
			or player.skill_timer > 0.0 or player.dodge_timer > 0.0
			or player.noise_timer > 0.0):
		return "in_combat"
	if not player.action.is_empty():
		return "busy"
	return ""
