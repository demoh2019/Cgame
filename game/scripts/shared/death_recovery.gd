extends RefCounted
## Tracks only the current survivor's own full-loot death bag. The world bag
## stays public and lootable by everyone: this provides a private route, not
## protection, restoration of contents or a second copy of the items.
const RaidLoot = preload("res://scripts/shared/raid_loot.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const TravelNavigation = preload("res://scripts/shared/travel_navigation.gd")


## Called only during the real server-authoritative full-loot death path.
## The token identifies an authenticated account across same-server reconnects,
## or an original RefCounted guest session (not its recyclable peer number).
static func tag(bag: Dictionary, player) -> void:
	if player == null or bag.is_empty() or not (bag.get("items", {}) is Dictionary) or \
			(bag.get("items", {}) as Dictionary).is_empty():
		return
	bag["death_recovery_owner"] = RaidLoot.token(player)


## Newest *surviving* owner bag is the navigable destination. The marker has no
## ID, item list, owner token, guild information or loot permissions. It cannot
## outlive its real public bag, including when other players loot everything.
static func public_mark(bags: Dictionary, player, now: float) -> Dictionary:
	if player == null or not is_finite(now):
		return {}
	var identity: String = RaidLoot.token(player)
	var latest_id: int = -1
	var marker: Dictionary = {}
	for key in bags:
		var bag: Variant = bags[key]
		if not (bag is Dictionary):
			continue
		var record: Dictionary = bag
		if str(record.get("death_recovery_owner", "")) != identity or \
				not (record.get("items", {}) is Dictionary) or \
				(record.get("items", {}) as Dictionary).is_empty():
			continue
		if not (record.get("id", null) is int) or \
				not (record.get("expires", null) is float or record.get("expires", null) is int):
			continue
		var id: int = int(record["id"])
		var left: float = float(record["expires"]) - now
		if id <= latest_id or not is_finite(left) or left <= 0.0:
			continue
		if not (record.get("x", null) is float or record.get("x", null) is int) or \
				not (record.get("z", null) is float or record.get("z", null) is int):
			continue
		var point: Vector2 = TravelNavigation.target(record, "x", "z")
		if not TravelNavigation.valid_destination(point, WorldGen.WORLD_RADIUS):
			continue
		latest_id = id
		marker = {"x": point.x, "z": point.y, "remaining": left}
	return marker
