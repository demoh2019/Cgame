extends RefCounted
## Data Layers: named sets of world content switched on and off at runtime for the whole server
## (seasons and events), without touching the seed-generated world. The server decides which are
## active - by the calendar, or forced with `--layers winter,festival` (or `--layers none`) - and
## sends the list to every client; clients add or remove the layer's content as it changes.
##   winter   - snow settles on all low ground (ground shader), Dec-Feb.
##   festival - lanterns and harvest decorations in settlements and camps, late Oct-early Nov
##              and over the year-end holidays.

const LAYERS := ["winter", "festival"]


## Layers the calendar turns on at this moment (UTC date).
static func scheduled(unix_time: float) -> Array:
	var date: Dictionary = Time.get_datetime_dict_from_unix_time(int(unix_time))
	var month: int = int(date["month"])
	var day: int = int(date["day"])
	var active: Array = []
	if month == 12 or month <= 2:
		active.append("winter")
	if (month == 10 and day >= 20) or (month == 11 and day <= 10) or (month == 12 and day >= 20) or (month == 1 and day <= 7):
		active.append("festival")
	return active


## Parse a `--layers` value: comma list of known layers, "none" for an empty set, "" = calendar.
static func parse_override(value: String) -> Variant:
	if value.strip_edges().is_empty():
		return null
	var active: Array = []
	for part in value.split(",", false):
		var name: String = part.strip_edges().to_lower()
		if LAYERS.has(name) and not active.has(name):
			active.append(name)
	return active
