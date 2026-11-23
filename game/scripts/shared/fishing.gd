extends RefCounted
## Shore fishing rules shared by server and tests. The client may only ask
## the server to start casting: it cannot choose catch, tier or duration.
## The rod is a carried tool, not an equippable weapon.

const Defs = preload("res://scripts/shared/defs.gd")
const FishingBait = preload("res://scripts/shared/fishing_bait.gd")

const CAST_SECONDS := 5.0
const COOLDOWN_SECONDS := 2.0
const CATCH_ID := "raw_fish"
const WATER_DISTANCES := [2.0, 2.8, 3.6]
const WATER_SAMPLES := 16
const MAX_CATCH := 2
# The bite: at a random moment of the cast (counted as seconds still left) the bobber dips for BITE_WINDOW seconds;
# casting again inside that window hooks the fish for HOOK_BONUS more. Too early or too late, the fish slips away
# (the cast still pays as an ordinary one). The server rolls the moment; the client only shows it.
const BITE_WINDOW := 0.9
const BITE_EARLIEST := 1.2 # Seconds after the cast starts.
const BITE_LATEST_LEFT := 1.4 # Seconds left at the latest bite, so the window always fits in the cast.
const HOOK_BONUS := 1


## Seconds left on the cast when the fish bites, from a roll in 0..1.
static func bite_at(cast_seconds: float, roll: float) -> float:
	if not is_finite(cast_seconds) or cast_seconds <= BITE_WINDOW or not is_finite(roll):
		return 0.0
	var latest: float = maxf(cast_seconds - BITE_EARLIEST, BITE_LATEST_LEFT)
	return lerpf(BITE_LATEST_LEFT, latest, clampf(roll, 0.0, 1.0))


## Whether `remaining` seconds left on the cast fall inside the bite window.
static func biting(remaining: float, bite_left: float) -> bool:
	return is_finite(remaining) and is_finite(bite_left) and remaining >= 0.0 \
		and bite_left >= BITE_LATEST_LEFT and remaining <= bite_left \
		and remaining > bite_left - BITE_WINDOW


static func water_near(world, position: Vector3) -> Vector2:
	if world == null or not position.is_finite() or world.is_water(position.x, position.z):
		return Vector2.INF # No casting from deep water or forged coordinates.
	for distance in WATER_DISTANCES:
		for sample in WATER_SAMPLES:
			var radians := TAU * float(sample) / float(WATER_SAMPLES)
			var point := Vector2(position.x, position.z) + Vector2.from_angle(radians) * float(distance)
			if world.is_water(point.x, point.y):
				return point
	return Vector2.INF


## A region never produces fish above its own zone tier, the carried
## fishing tool tier, or the survivor's server-owned profession tier.
static func catch_tier(zone: int, rod_tier: int, skill_tier: int) -> int:
	return clampi(mini(zone + 1, mini(rod_tier, skill_tier)), 1, Defs.MAX_TIER)


static func catch_item(tier: int) -> String:
	if tier < 1 or tier > Defs.MAX_TIER:
		return ""
	return CATCH_ID if tier == 1 else "raw_fish_%d" % tier


static func validate_start(world, player_position: Vector3, backpack, skill_tier: int = 1,
		baited: bool = false) -> Dictionary:
	if world == null or backpack == null or not player_position.is_finite():
		return {"ok": false, "reason": "invalid_position"}
	var rod_id: String = backpack.best_tool("fishing")
	if rod_id == "":
		return {"ok": false, "reason": "need_rod"}
	var water := water_near(world, player_position)
	if water == Vector2.INF:
		return {"ok": false, "reason": "need_water"}
	var zone_tier: int = int(world.zone_at(player_position.x, player_position.z))
	var tier: int = catch_tier(zone_tier, Defs.tier_of(rod_id), skill_tier)
	var item_id: String = catch_item(tier)
	if backpack.free_space_for(item_id) <= 0:
		return {"ok": false, "reason": "no_space"}
	if baited and not FishingBait.can_request(backpack):
		return {"ok": false, "reason": "need_bait"}
	return {"ok": true, "water_x": water.x, "water_z": water.y,
		"seconds": CAST_SECONDS, "tier": tier, "item": item_id,
		"baited": baited}
