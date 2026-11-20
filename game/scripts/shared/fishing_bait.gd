extends RefCounted
## Optional, item-paid shoreline bait. One unit is spent only if the server
## can deliver the bonus fish on a completed, valid cast. The client cannot
## choose fish tier, reward count or cast duration.

const ITEM_ID := "shore_bait"
const BONUS_FISH := 1


static func can_request(backpack) -> bool:
	return backpack != null and backpack.count(ITEM_ID) > 0


## Returns whether a real bait was consumed. Reserve enough fish capacity
## before deducting anything; unbaited and partially-full casts stay normal.
static func spend_for_bonus(backpack, fish_id: String, base_amount: int, requested: bool) -> bool:
	if not requested or not can_request(backpack) or base_amount < 1 or base_amount > 2:
		return false
	if backpack.free_space_for(fish_id) < base_amount + BONUS_FISH:
		return false
	return backpack.remove(ITEM_ID, 1)
