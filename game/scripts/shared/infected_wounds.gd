extends RefCounted
## Low-health infected respond visibly and mechanically to actual server damage.
## Ordinary walkers/spitters limp; runners make a dangerous last sprint.
## Brutes and raid bosses keep their established combat timings.

const WOUND_THRESHOLD := 0.35
const LIMP_SPEED_FACTOR := 0.65
const ELITE_LIMP_SPEED_FACTOR := 0.82
const FRENZY_SPEED_FACTOR := 1.18
const ELITE_FRENZY_SPEED_FACTOR := 1.09


static func phase(infected) -> String:
	if infected == null or not infected.is_alive() or infected.raid_boss:
		return ""
	var maximum: float = float(infected.data.get("health", 0.0))
	var current: float = infected.health
	if not is_finite(maximum) or maximum <= 0.0 or not is_finite(current) or current <= 0.0:
		return ""
	if current / maximum > WOUND_THRESHOLD:
		return ""
	match infected.type:
		"walker", "spitter":
			return "limping"
		"runner":
			return "frenzied"
	return ""


static func speed_factor(infected) -> float:
	match phase(infected):
		"limping":
			return ELITE_LIMP_SPEED_FACTOR if infected.elite else LIMP_SPEED_FACTOR
		"frenzied":
			return ELITE_FRENZY_SPEED_FACTOR if infected.elite else FRENZY_SPEED_FACTOR
	return 1.0
