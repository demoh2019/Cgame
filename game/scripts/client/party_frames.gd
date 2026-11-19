extends RefCounted
## Compact party health frames for the networked HUD.
## Pure presentation of authoritative snapshot data; no guessed or client-
## writable health, roster membership, roles or combat rewards.

const MAX_VISIBLE_MEMBERS := 5
const MAX_NAME_CHARS := 20


static func describe(raw: Variant, local_peer: int) -> String:
	if not (raw is Dictionary):
		return ""
	var party: Dictionary = raw
	if int(party.get("id", 0)) <= 0:
		return ""
	var roster: Variant = party.get("roster", [])
	if not (roster is Array):
		return ""
	if roster.is_empty():
		return ""
	var leader: int = int(party.get("leader", 0))
	var lines: PackedStringArray = []
	var count: int = mini(roster.size(), MAX_VISIBLE_MEMBERS)
	lines.append("PARTY  %d/%d" % [count, MAX_VISIBLE_MEMBERS])
	for i in count:
		var row: Variant = roster[i]
		if not (row is Dictionary):
			continue
		var member: Dictionary = row
		var id: int = int(member.get("id", -1))
		var name: String = str(member.get("name", "Survivor")).replace("\n", " ").replace("\r", " ").substr(0, MAX_NAME_CHARS)
		var alive: bool = bool(member.get("alive", false))
		var health: float = float(member.get("health", 0.0))
		if not is_finite(health):
			health = 0.0
		var status: String = ("%d HP" % int(clampf(health, 0.0, 100.0))) if alive else "DOWN"
		var marker: String = "★ " if id == leader else "  "
		if id == local_peer:
			name += " (you)"
		lines.append("%s%s  %s" % [marker, name, status])
	return "\n".join(lines)
