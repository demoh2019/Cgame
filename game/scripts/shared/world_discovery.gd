extends RefCounted
## Server-verified once-per-POI exploration and seeded save recovery.
const WorldPoi = preload("res://scripts/shared/world_poi.gd")
const SaveValidation = preload("res://scripts/shared/save_validation.gd")
const MAX_DISCOVERIES := 384
const MAX_REGION := 15
const MAX_SITE_ID := 9999999
const SCAN_EVERY_TICKS := 20


static func key_for(site: Dictionary) -> Vector2i:
	return Vector2i(floori(float(site["x"]) / WorldPoi.REGION_SIZE),
		floori(float(site["z"]) / WorldPoi.REGION_SIZE))


static func reveal(world, position: Vector3, journal: Dictionary) -> Dictionary:
	if not position.is_finite() or journal.size() >= MAX_DISCOVERIES:
		return {}
	var site: Dictionary = world.poi.site_at(position.x, position.z)
	if site.is_empty() or not site.has("id") or not site.has("x") or not site.has("z"):
		return {}
	# Even a broken procedural world record must not enter persisted player
	# progress or award discovery rewards without a valid region and site ID.
	var raw_id: Variant = site["id"]
	var raw_x: Variant = site["x"]
	var raw_z: Variant = site["z"]
	if typeof(raw_id) != TYPE_INT or int(raw_id) < 0 or int(raw_id) > MAX_SITE_ID:
		return {}
	if not (raw_x is float or raw_x is int) or not (raw_z is float or raw_z is int):
		return {}
	if not is_finite(float(raw_x)) or not is_finite(float(raw_z)):
		return {}
	var region: Vector2i = key_for(site)
	if journal.has(region):
		return {}
	journal[region] = int(site["id"])
	return site


static func explorer_xp(zone: int) -> float:
	return 20.0 + float(clampi(zone, 0, 3)) * 15.0


static func renown(zone: int) -> int:
	return clampi(zone + 1, 1, 4)


static func ids(journal: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for site_id in journal.values():
		result.append(int(site_id))
	result.sort()
	return result


static func to_saved(journal: Dictionary) -> Array:
	var result: Array = []
	for region in journal:
		var key: Vector2i = region
		result.append({"rx": key.x, "rz": key.y, "id": int(journal[region])})
	# A canonical tie-breaker keeps saves identical even if insertion order
	# differs (e.g. merging recovered journals with duplicate site IDs).
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["id"]) != int(b["id"]):
			return int(a["id"]) < int(b["id"])
		if int(a["rx"]) != int(b["rx"]):
			return int(a["rx"]) < int(b["rx"])
		return int(a["rz"]) < int(b["rz"]))
	return result


## Returns {"journal": Dictionary} on success, including empty legacy
## journals. All records match real sites in the current world seed.
static func from_saved(raw: Variant, world) -> Dictionary:
	if not (raw is Array) or raw.size() > MAX_DISCOVERIES:
		return {}
	var journal: Dictionary = {}
	for entry in raw:
		if not (entry is Dictionary) or entry.size() != 3 or \
				not entry.has("rx") or not entry.has("rz") or not entry.has("id"):
			return {}
		var x: Variant = entry["rx"]
		var z: Variant = entry["rz"]
		var id: Variant = entry["id"]
		if not SaveValidation.finite_number(x, -MAX_REGION, MAX_REGION) or \
				not SaveValidation.finite_number(z, -MAX_REGION, MAX_REGION) or \
				not SaveValidation.finite_number(id, 0, MAX_SITE_ID):
			return {}
		if float(x) != floor(float(x)) or float(z) != floor(float(z)) or \
				float(id) != floor(float(id)):
			return {}
		var key := Vector2i(int(x), int(z))
		if journal.has(key):
			return {}
		var sites: Array = world.poi.sites_in_region(key.x, key.y)
		if sites.size() != 1 or int(sites[0]["id"]) != int(id):
			return {}
		journal[key] = int(id)
	return {"journal": journal}
