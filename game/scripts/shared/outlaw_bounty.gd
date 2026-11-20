extends RefCounted
## Small, server-funded rewards for taking down wanted criminals in red/black zones.
## The existing PvP honor ledger throttles repeated kills of the same account.

const PvpInfamy = preload("res://scripts/shared/pvp_infamy.gd")

const RED_BASE_SILVER := 15
const BLACK_BASE_SILVER := 30
const SILVER_PER_INFAMY_BRACKET := 10
const INFAMY_BRACKET_SIZE := 25.0
const MAX_BRACKETS := 2


## Rewards scale with risk and the victim's verified server-owned infamy.
## No payout for lawful self-defense against a non-outlaw.
static func silver_for(zone: int, infamy: float) -> int:
	if zone < 2 or zone > 3 or not PvpInfamy.is_outlaw(infamy):
		return 0
	var base: int = BLACK_BASE_SILVER if zone == 3 else RED_BASE_SILVER
	var brackets: int = clampi(floori((infamy - PvpInfamy.OUTLAW_THRESHOLD) /
		INFAMY_BRACKET_SIZE), 0, MAX_BRACKETS)
	return base + brackets * SILVER_PER_INFAMY_BRACKET


## Only authenticated, distinct accounts may earn currency. A genuinely
## confirmed PvP kill with a fresh honor-ledger entry is also required.
## Guests can still fight and earn normal noncurrency PvP honor.
static func reward_for_kill(attacker, victim, zone: int,
		honor_result: Dictionary) -> int:
	if attacker == null or victim == null or attacker == victim:
		return 0
	if attacker.user_id.is_empty() or victim.user_id.is_empty() or 			attacker.user_id == victim.user_id:
		return 0
	if not bool(honor_result.get("ok", false)) or int(honor_result.get("awarded", 0)) <= 0:
		return 0
	return silver_for(zone, victim.pvp_infamy)
