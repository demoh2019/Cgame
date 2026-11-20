extends RefCounted
## Defenders' tier-one watchtower. Only a live owner with a fortified banner
## can receive a signal; no enemy IDs, counts or stealth state are exposed.
const MIN_FORTIFICATION := 1
const ALERT_COOLDOWN := 90.0


static func ready(site: Dictionary, owner: int, now: float, occupants: Dictionary) -> bool:
	if owner <= 0 or int(site.get("owner", 0)) != owner or not is_finite(now):
		return false
	if int(site.get("fortification", 0)) < MIN_FORTIFICATION:
		return false
	if now >= float(site.get("until", 0.0)) or now < float(site.get("watch_ready_at", 0.0)):
		return false
	for side in occupants:
		if int(side) != owner:
			return true
	return false


static func activate(site: Dictionary, now: float) -> Dictionary:
	site["watch_ready_at"] = now + ALERT_COOLDOWN
	return {"type": "outpost_watch", "id": int(site["id"]),
		"owner": int(site["owner"]), "x": float(site["x"]),
		"z": float(site["z"]), "level": int(site["fortification"])}
