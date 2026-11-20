extends RefCounted
## Verified Nakama guild identity attached to session-based outpost ownership.
## A banner is *derived* from live server-owned party membership on each read.
## It is never persisted, and a client cannot submit a banner or guild name.

const MIN_VERIFIED_MEMBERS := 2


static func party_banner(group_id: int, players: Dictionary, parties) -> Dictionary:
	if group_id <= 0 or parties == null or not parties.groups.has(group_id):
		return {}
	var members: Array = parties.groups[group_id].get("members", [])
	if members.size() < MIN_VERIFIED_MEMBERS:
		return {}
	var guild_id := ""
	var guild_name := ""
	for peer_id in members:
		var player = players.get(int(peer_id))
		if player == null or player.user_id.is_empty() or player.guild_id.is_empty() \
				or player.guild_name.is_empty() or player.guild_rank < 0 or player.guild_rank > 2:
			return {}
		if guild_id.is_empty():
			guild_id = player.guild_id
			guild_name = player.guild_name
		elif guild_id != player.guild_id or guild_name != player.guild_name:
			return {} # Mixed parties cannot claim a verified clan banner.
	return {"id": guild_id, "name": guild_name}


static func owner_banner(site: Dictionary, players: Dictionary, parties) -> Dictionary:
	return party_banner(int(site.get("owner", 0)), players, parties)


static func same_owner_guild(site: Dictionary, player, players: Dictionary, parties) -> bool:
	if player == null or player.user_id.is_empty() or player.guild_id.is_empty():
		return false
	var banner: Dictionary = owner_banner(site, players, parties)
	return not banner.is_empty() and player.guild_id == str(banner["id"])


## A verified guildmate defending the flag belongs to the same presence side
## as the owning party. Unverified parties/guests retain old PvP rules.
static func occupancy_side(site: Dictionary, player, players: Dictionary, parties) -> int:
	if same_owner_guild(site, player, players, parties):
		return int(site["owner"])
	return parties.group_of(player.id)
