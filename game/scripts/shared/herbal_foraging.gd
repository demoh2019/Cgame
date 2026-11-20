extends RefCounted
## Secondary, bounded medicinal foraging from genuine server-spawned plants.
## Only an actual completed gather may call roll(); no user-submitted loot
## tables, professions or biome labels are accepted by the game server.

const ITEM_ID := "wild_herbs"
const FOREST_CHANCE := 0.24
const SWAMP_CHANCE := 0.42
const MIN_ZONE := 1
const MAX_ZONE := 3


static func chance(kind: String, biome: String, zone: int) -> float:
	if kind not in ["bush", "berry"] or zone < MIN_ZONE or zone > MAX_ZONE:
		return 0.0
	match biome:
		"forest":
			return FOREST_CHANCE
		"swamp":
			return SWAMP_CHANCE
	return 0.0


## Called once when a depleted world plant actually yields its primary item.
## Consumes no RNG draws if the world node is ineligible.
static func roll(kind: String, biome: String, zone: int,
		rng: RandomNumberGenerator) -> String:
	var probability: float = chance(kind, biome, zone)
	if probability <= 0.0:
		return ""
	return ITEM_ID if rng.randf() < probability else ""
