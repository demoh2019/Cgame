extends RefCounted
## Short, recipient-specific world labels based on server snapshot values.
## No client-side permission decisions: this is display-only.


static func for_bag(bag: Dictionary) -> String:
	if bool(bag.get("supply_drop", false)):
		return "SUPPLY DROP - public"
	var raid: bool = bool(bag.get("raid", false))
	var reserved: bool = bool(bag.get("reserved", false))
	var seconds: float = float(bag.get("reserved_seconds", 0.0))
	if not is_finite(seconds):
		seconds = 0.0
	# Expired raid caches remain recognizable after priority ends.
	if not reserved or seconds <= 0.0:
		return "RAID CACHE - public" if raid else ""
	var prefix: String = "RAID CACHE" if raid else "PARTY LOOT"
	var permission: String = "your pickup" if bool(bag.get("can_loot", false)) else "locked"
	return "%s - %s (%ds)" % [prefix, permission, ceili(seconds)]
