extends RefCounted
## Identity returned by server-key-only Nakama RPC. Never accept a guild ID
## originating in an ENet client command or in a saved character document.
const MAX_NAME := 24
const MAX_ROLE := 2
const UUID_PATTERN := "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"


static func normalize(info: Variant) -> Dictionary:
	if typeof(info) != TYPE_DICTIONARY or not info.get("ok", false):
		return {}
	var guild_id: Variant = info.get("guild_id")
	var guild_name: Variant = info.get("guild_name")
	var rank: Variant = info.get("rank")
	if typeof(guild_id) != TYPE_STRING or typeof(guild_name) != TYPE_STRING or typeof(rank) != TYPE_INT:
		return {}
	if guild_id == "" and guild_name == "" and rank == -1:
		return {"guild_id": "", "guild_name": "", "rank": -1}
	var matcher := RegEx.new()
	if matcher.compile(UUID_PATTERN) != OK or matcher.search(guild_id) == null:
		return {}
	if guild_name.is_empty() or guild_name.length() > MAX_NAME or guild_name != guild_name.strip_edges():
		return {}
	if rank < 0 or rank > MAX_ROLE:
		return {} # Pending invitations and requests are never guild memberships.
	return {"guild_id": guild_id.to_lower(), "guild_name": guild_name, "rank": rank}


static func same_guild(first, second) -> bool:
	return first != null and second != null and not first.user_id.is_empty() \
		and not second.user_id.is_empty() and not first.guild_id.is_empty() \
		and first.guild_id == second.guild_id
