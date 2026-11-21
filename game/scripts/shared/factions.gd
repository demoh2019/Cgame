extends RefCounted
## Faction warfare (Albion Online-style, original setting). Survivors enlist with one
## of three settlement factions at the hub. While FLAGGED, they may fight flagged
## members of rival factions outside safe settlements even in the yellow zone (which
## is otherwise PvE-only). Faction kills are lawful (no infamy, no full loot in yellow)
## and earn faction points, which are redeemed for silver and enchanting materials.

const FACTIONS := {
	"wardens": "Ashen Wardens",
	"compact": "Iron Compact",
	"circle": "Verdant Circle",
}
const MIN_ZONE := 1 # Yellow and riskier; never the green starter ring.
const UNFLAG_SECONDS := 10.0 # You cannot drop the flag instantly to escape a fight.
const POINTS_PLAYER_KILL := 50
const POINTS_INFECTED_KILL := 2
const POINTS_ELITE_KILL := 10
const REDEEM_COST := 100
const REDEEM_REWARD := {"silver": 60, "rune": 3}
const MAX_POINTS := 1000000


static func valid_faction(id: String) -> bool:
	return FACTIONS.has(id)


## True when two players may fight as faction enemies at these zones.
static func can_fight(a_faction: String, a_flagged: bool, b_faction: String, b_flagged: bool,
		a_zone: int, b_zone: int, a_safe: bool, b_safe: bool) -> bool:
	if not (a_flagged and b_flagged):
		return false
	if not valid_faction(a_faction) or not valid_faction(b_faction) or a_faction == b_faction:
		return false
	if a_safe or b_safe:
		return false
	return a_zone >= MIN_ZONE and b_zone >= MIN_ZONE


static func valid_points(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 \
		and float(value) <= float(MAX_POINTS) and float(value) == floor(float(value))
