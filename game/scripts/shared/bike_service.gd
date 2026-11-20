extends RefCounted
## Paid maintenance of a bicycle drive chain, measured from actual server travel.
## This is a survivor-owned service buff, not arbitrary item metadata. No client RPC
## can supply remaining metres, repair quantity, wear or sound radius.

const ITEM_ID := "bike_service_kit"
const BIKE_ID := "salvage_bike"
const MAX_METERS := 800.0
const SERVICED_NOISE_RADIUS := 17.0

static func valid_remaining(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) \
		and float(value) >= 0.0 and float(value) <= MAX_METERS


static func repair_reason(inventory, remaining: float) -> String:
	if inventory.count(BIKE_ID) < 1:
		return "missing_bike"
	if not valid_remaining(remaining):
		return "invalid_state"
	if remaining > 0.0:
		return "already_serviced"
	if inventory.count(ITEM_ID) < 1:
		return "not_carried"
	return ""


static func wear_for_distance(biome: String, actual_meters: float) -> float:
	if not is_finite(actual_meters) or actual_meters <= 0.0:
		return 0.0
	var wear_factor := 1.0
	match biome:
		"swamp":
			wear_factor = 2.0
		"beach":
			wear_factor = 1.6
		"mountain":
			wear_factor = 1.5
		"forest":
			wear_factor = 1.3
		"water":
			wear_factor = 2.0
	return minf(MAX_METERS, actual_meters * wear_factor)


static func remaining_after_move(remaining: float, biome: String, moved: float) -> float:
	if not valid_remaining(remaining):
		return 0.0
	return maxf(0.0, remaining - wear_for_distance(biome, moved))


static func riding_noise_radius(remaining: float, wrapped_radius: float) -> float:
	# An existing quiet chain wrap (9 m) always wins over the serviced drive
	# (17 m). With no service the original rattling bike (27 m) is unchanged.
	var serviced := SERVICED_NOISE_RADIUS if valid_remaining(remaining) and remaining > 0.0 else 27.0
	return minf(serviced, wrapped_radius)
