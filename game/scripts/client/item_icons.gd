extends RefCounted
## Item icons: one white silhouette per item (game-icons.net, CC BY 3.0, see docs/ASSETS.md), shared by every tier of
## the item and tinted by the interface. Unknown items fall back to a neutral crate.

const DIR := "res://assets/icons/items/"
const FALLBACK := "scrap"

static var _cache: Dictionary = {}


## The item without its tier suffix: "wood_3" -> "wood".
static func base_id(item_id: String) -> String:
	var cut: int = item_id.rfind("_")
	if cut > 0 and item_id.substr(cut + 1).is_valid_int():
		return item_id.substr(0, cut)
	return item_id


static func icon(item_id: String) -> Texture2D:
	var base: String = base_id(item_id)
	if _cache.has(base):
		return _cache[base]
	var path: String = DIR + base + ".svg"
	if not ResourceLoader.exists(path):
		path = DIR + FALLBACK + ".svg"
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[base] = texture
	return texture


## Icon tint by what the item is for, so the backpack reads at a glance: weapons warm, medicine red, food green ...
static func kind_color(kind: String) -> Color:
	match kind:
		"weapon", "ammo":
			return Color(0.98, 0.84, 0.62)
		"armor", "armor_plate", "carry_pack", "siege_brace", "head", "cape", "hands", "feet":
			return Color(0.72, 0.84, 1.0)
		"medical", "party_medical", "stimulant":
			return Color(1.0, 0.62, 0.6)
		"food", "drink":
			return Color(0.7, 0.95, 0.6)
		"resource", "material":
			return Color(0.86, 0.8, 0.7)
		"currency":
			return Color(0.92, 0.92, 0.98)
		"tool", "mount", "bike_service", "bike_frame_repair", "bike_light", "bike_cargo", "bike_wrap", "tire_grips":
			return Color(0.82, 0.88, 0.9)
	return Color(0.9, 0.82, 1.0)
