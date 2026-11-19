extends RefCounted
## Shared local/online HUD presentation of authoritative fishing actions.
## This script only formats state; never modifies catches or progress.

const Defs = preload("res://scripts/shared/defs.gd")


static func progress(action: Variant) -> String:
	if not (action is Dictionary) or not bool(action.get("fish", false)):
		return ""
	var item_id: String = str(action.get("catch_id", "raw_fish"))
	var item_name: String = str(Defs.item(item_id).get("name", item_id))
	var total: float = float(action.get("total", 5.0))
	var remaining: float = float(action.get("remaining", 0.0))
	if not is_finite(total) or total <= 0.0:
		total = 5.0
	if not is_finite(remaining):
		remaining = 0.0
	remaining = clampf(remaining, 0.0, total)
	return "Fishing %s: %.1fs remaining (moving cancels)" % [item_name, remaining]
