extends RefCounted
## Facade for the infected prey choice: same API as
## res://scripts/shared/infected_target_utility.gd (static score()). Delegates to
## the native CgameUtilityAI.infected_target_score when available.

const UtilityAIFacade = preload("utility_ai.gd")

const WOUNDED_BONUS := 0.35
const STICKY_BONUS := 0.25
const NOISE_BONUS := 0.15


static func score(distance: float, leash: float, health_fraction: float,
		is_current: bool, noisy: bool) -> float:
	return UtilityAIFacade.infected_target_score(distance, leash, health_fraction, is_current, noisy)
