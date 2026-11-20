extends RefCounted
## Bike travel permissions. Only the server decides mount speed and eligibility.

const BikeCargo = preload("res://scripts/shared/bike_cargo.gd")
const BikeIntegrity = preload("res://scripts/shared/bike_integrity.gd")

const ITEM_ID := "salvage_bike"
const SPEED_FACTOR := 1.9
const MANUAL_COOLDOWN := 2.0
const HIT_COOLDOWN := 12.0
# Bike travel is quick but noisy: infected hear the actual rolling displacement.
const NOISE_RADIUS := 27.0
const NOISE_SECONDS := 0.9
const MIN_NOISY_MOVEMENT := 0.01


static func noise_for_distance(meters: float) -> float:
	if not is_finite(meters) or meters <= MIN_NOISY_MOVEMENT:
		return 0.0
	return NOISE_RADIUS



static func refusal(player, now: float) -> String:
	if player.inventory.count(ITEM_ID) <= 0:
		return "missing_bike"
	if not BikeIntegrity.can_ride(player.bike_integrity):
		return "broken_bike"
	if player.mount_cooldown > 0.0:
		return "cooldown"
	if BikeCargo.movement_factor(player.inventory, player.skills.bonus("carry_capacity"), true) < 0.9999:
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
