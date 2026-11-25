extends RefCounted
## Infected prey choice scored with Utility AI instead of "nearest wins":
## proximity still dominates, but a wounded straggler, the survivor already
## being chased, and a noisy survivor each tip the balance — the horde hunts
## the weak and does not flip-flop between two equally close players.

const UtilityAI = preload("res://scripts/shared/utility_ai.gd")

const WOUNDED_BONUS := 0.35
const STICKY_BONUS := 0.25
const NOISE_BONUS := 0.15


static func score(distance: float, leash: float, health_fraction: float,
		is_current: bool, noisy: bool) -> float:
	if not is_finite(distance) or distance < 0.0 or not is_finite(leash) or leash <= 0.0:
		return 0.0
	if distance > leash:
		# The leash itself is enforced by the chase state; an existing focus is never dropped here.
		return 0.01 if is_current else 0.0
	var proximity: float = UtilityAI.curve(UtilityAI.Response.INVERSE_QUADRATIC, 1.0 - distance / leash)
	# Never fully zero at the leash edge: perception already gated the candidate.
	proximity = maxf(proximity, 0.02)
	var weakness: float = 1.0 - clampf(health_fraction if is_finite(health_fraction) else 1.0, 0.0, 1.0)
	var appetite: float = 1.0 + WOUNDED_BONUS * UtilityAI.curve(UtilityAI.Response.QUADRATIC, weakness)
	var focus: float = 1.0 + (STICKY_BONUS if is_current else 0.0)
	var lure: float = 1.0 + (NOISE_BONUS if noisy else 0.0)
	return proximity * appetite * focus * lure
