extends RefCounted
## Persistent survivor renown: earned only by verified server gameplay.
## Rank determines modest NPC survival-supply discounts, not PvP power,
## loot duplication, player-to-player prices or global market taxes.

const SaveValidation = preload("res://scripts/shared/save_validation.gd")

const MAX_RENOWN := 10000
const RANK_POINTS := [0, 40, 160, 500]
const RANK_NAMES := ["Newcomer", "Settler", "Ranger", "Warden"]
const SHOP_DISCOUNTS := [0, 10, 15, 20]
const CONTRACT_RENOWN := 8


static func valid_points(raw: Variant) -> bool:
	return SaveValidation.valid_counter(raw) and int(raw) <= MAX_RENOWN


static func rank(points: int) -> int:
	var bounded: int = clampi(points, 0, MAX_RENOWN)
	for index in range(RANK_POINTS.size() - 1, -1, -1):
		if bounded >= int(RANK_POINTS[index]):
			return index
	return 0


static func title(points: int) -> String:
	return str(RANK_NAMES[rank(points)])


static func discount_percent(points: int) -> int:
	return int(SHOP_DISCOUNTS[rank(points)])


static func next_threshold(points: int) -> int:
	var current: int = rank(points)
	if current + 1 >= RANK_POINTS.size():
		return MAX_RENOWN
	return int(RANK_POINTS[current + 1])


static func apply_earned(current: int, earned: int) -> int:
	# The server awards only known, bounded events, never submitted XP.
	if earned <= 0:
		return clampi(current, 0, MAX_RENOWN)
	return mini(MAX_RENOWN, maxi(0, current) + mini(100, earned))


static func kill_points(zombie_type: String, elite: bool, raid_boss: bool) -> int:
	var basic := 0
	match zombie_type:
		"walker": basic = 1
		"runner": basic = 2
		"brute": basic = 4
		"spitter": basic = 3
		_: return 0
	if elite:
		basic += 5
	if raid_boss:
		basic += 35
	return basic


static func buy_price(base_price: int, quantity: int, renown: int) -> int:
	if base_price <= 0 or quantity <= 0 or quantity > 50:
		return -1
	# Round upward: a discount never creates free items, and only BUY
	# prices are reduced; NPC resale and market quotes are unchanged.
	var unit_price: int = maxi(1,
		ceili(float(base_price) * (100.0 - discount_percent(renown)) / 100.0))
	return unit_price * quantity
