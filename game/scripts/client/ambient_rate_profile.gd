extends RefCounted
## Data-only significance profile for optional Albion After cosmetic systems.
## The thresholds mirror each effect's visibility rules. No gameplay state,
## physics or network updates are ever scheduled through this profile.
const DRAGONFLIES := 1
const DUST_DEVILS := 2
const TUMBLEWEEDS := 4
const DUSK_BATS := 8
const ACTIVE_RATE := 1.5
const INACTIVE_RATE := 0.75


static func active_flags(level: int, biome: String, wind: Vector2,
		daylight: float, storm: float, underground: bool) -> int:
	if underground or not wind.is_finite() or not is_finite(daylight) or not is_finite(storm):
		return 0
	var flags: int = 0
	if level >= 2 and daylight >= 0.5 and storm <= 0.2:
		flags |= DRAGONFLIES
	if level >= 1 and biome == "plains" and wind.length() > 0.35 \
			and storm < 0.1 and daylight > 0.45:
		flags |= DUST_DEVILS
	if level >= 1 and biome == "plains" and wind.length() >= 0.25:
		flags |= TUMBLEWEEDS
	if level >= 1 and daylight <= 0.45 and storm <= 0.4:
		flags |= DUSK_BATS
	return flags


static func scales_for_flags(flags: int) -> Dictionary:
	return {
		"dragonflies": ACTIVE_RATE if (flags & DRAGONFLIES) != 0 else INACTIVE_RATE,
		"dust_devils": ACTIVE_RATE if (flags & DUST_DEVILS) != 0 else INACTIVE_RATE,
		"tumbleweeds": ACTIVE_RATE if (flags & TUMBLEWEEDS) != 0 else INACTIVE_RATE,
		"dusk_bats": ACTIVE_RATE if (flags & DUSK_BATS) != 0 else INACTIVE_RATE,
	}
