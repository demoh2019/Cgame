extends RefCounted
## Pure validation of server-generated siege victories before writing a
## permanent Nakama guild score. Never trust an ENet-supplied victory or tag.
const GuildTerritory = preload("res://scripts/shared/guild_territory.gd")


static func eligible_victory(event: Variant, sim) -> Dictionary:
	if typeof(event) != TYPE_DICTIONARY or event.get("type") != "siege_contract_result" \
			or event.get("result") != "won":
		return {}
	if typeof(event.get("site")) != TYPE_INT or typeof(event.get("attacker")) != TYPE_INT:
		return {}
	var site_id: int = event["site"]
	var team_id: int = event["attacker"]
	if site_id < 1 or team_id <= 0:
		return {}
	var site: Dictionary = sim.territory.site_by_id(site_id)
	if site.is_empty() or int(site.get("owner", 0)) != team_id:
		return {}
	var clan: Dictionary = GuildTerritory.party_banner(team_id, sim.players, sim.parties)
	if clan.is_empty():
		return {}
	return {
		"guild_id": clan["id"],
		"guild_name": clan["name"],
		"site": site_id,
		"world_seed": int(sim.world.world_seed),
	}
