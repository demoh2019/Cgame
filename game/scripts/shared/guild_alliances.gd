extends RefCounted
## Albion-style guild alliances. Guild leaders (verified Nakama rank 0) invite another
## guild's leader at the hub; on acceptance both guilds share an alliance, and allied
## members never hit or intercept each other's attacks in PvP. A leader can leave at
## any time. Guild ids come only from the server-side identity check.

const MAX_GUILDS := 4
const INVITE_SECONDS := 120.0
const LEADER_RANK := 0


static func is_leader(rank: int) -> bool:
	return rank == LEADER_RANK


## True when two verified guild ids are the same guild or share an alliance.
static func friendly(guild_a: String, guild_b: String, guild_to_alliance: Dictionary) -> bool:
	if guild_a.is_empty() or guild_b.is_empty():
		return false
	if guild_a == guild_b:
		return true
	var alliance_a: int = int(guild_to_alliance.get(guild_a, -1))
	return alliance_a >= 0 and alliance_a == int(guild_to_alliance.get(guild_b, -2))
