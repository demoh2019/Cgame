extends RefCounted
## Read-only per-survivor RAID threat awareness. This is NOT a shared hate
## table: clients cannot set, transmit, or use these values for targeting.
## All peer identifiers in this view belong to the viewer's own party.
const Threat = preload("res://scripts/shared/threat.gd")

const DISPLAY_RANGE := 42.0
const DISPLAY_HEIGHT := 7.0


static func _same_encounter(boss, player, world) -> bool:
	if player == null or not player.survival.alive or not player.position.is_finite():
		return false
	if world.is_safe(player.position.x, player.position.z):
		return false
	if world.zone_at(player.position.x, player.position.z) != \
			world.zone_at(boss.position.x, boss.position.z):
		return false
	if absf(player.position.y - boss.position.y) > DISPLAY_HEIGHT:
		return false
	var offset := Vector2(player.position.x - boss.position.x, \
		player.position.z - boss.position.z)
	return offset.length_squared() <= DISPLAY_RANGE * DISPLAY_RANGE


## Only members of an active party close to the boss get a summary.
## Never serialize raw threat entries, outside-group IDs or session tokens.
static func for_viewer(boss, viewer, players: Dictionary, parties, world) -> Dictionary:
	if boss == null or not boss.raid_boss or not boss.is_alive() or \
			not boss.position.is_finite() or viewer == null or world == null:
		return {}
	var party_id: int = parties.group_of(viewer.id)
	if party_id <= 0 or not _same_encounter(boss, viewer, world):
		return {}
	var member_ids: Array = parties.members_of(viewer.id)
	if member_ids.size() < 2:
		return {}
	var top_id: int = 0
	var top_value: float = 0.0
	var viewer_value: float = 0.0
	var engaged: bool = false
	for id in member_ids:
		var member = players.get(int(id))
		if not _same_encounter(boss, member, world):
			continue
		var value: float = float(boss.threat.get(int(id), 0.0))
		if not is_finite(value) or value < 0.0:
			continue
		if int(id) == viewer.id:
			viewer_value = value
		if int(id) == boss.target_id or value > 0.0:
			engaged = true
		if value > top_value or (value == top_value and value > 0.0 and \
				(top_id == 0 or int(id) < top_id)):
			top_id = int(id)
			top_value = value
	if not engaged:
		return {}
	var target_id: int = 0
	var target = players.get(boss.target_id)
	if member_ids.has(boss.target_id) and _same_encounter(boss, target, world):
		target_id = boss.target_id
	var target_value: float = float(boss.threat.get(target_id, 0.0))
	if not is_finite(target_value) or target_value < 0.0:
		target_value = 0.0
	var pull_pct: int = -1
	if target_id > 0 and target_id != viewer.id and target_value > 0.0:
		# Divide before scaling to percent: 100 * huge finite threat can
		# overflow, and rounding INF can corrupt a networked HUD integer.
		var pull_ratio: float = (viewer_value / target_value) / Threat.SWITCH_MARGIN
		pull_pct = 999 if not is_finite(pull_ratio) else clampi(
			roundi(minf(pull_ratio, 9.99) * 100.0), 0, 999)
	var forced_seconds: float = float(boss.forced_target_seconds)
	var forced: bool = target_id > 0 and boss.forced_target_id == target_id and \
		is_finite(forced_seconds) and forced_seconds > 0.0
	var share: float = viewer_value / maxf(top_value, 1.0)
	return {
		"boss": boss.id,
		"target": target_id,
		"top": top_id,
		"your_pct": clampi(roundi(minf(share, 1.0) * 100.0), 0, 100),
		"pull_pct": pull_pct,
		"targeted": target_id == viewer.id,
		"taunted": forced,
		"taunt_seconds": minf(10.0, forced_seconds) if forced else 0.0
	}
