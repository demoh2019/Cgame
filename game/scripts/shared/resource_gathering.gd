extends RefCounted
## Rust-like resource interaction rules shared by the client and authoritative server.
## The server owns all depletion, strike progress, cooldowns and inventory rewards.

const Defs = preload("res://scripts/shared/defs.gd")
const PROGRESS_EXPIRE_SECONDS := 45.0

static func is_pickup(kind: String) -> bool:
	return kind == "pebble" or kind == "branch"


static func is_strike(kind: String) -> bool:
	return kind == "tree" or kind == "rock" or kind == "ore"


static func strikes_needed(kind: String) -> int:
	match kind:
		"tree", "rock":
			return 4
		"ore":
			return 3
	return 0


static func swing_cooldown(tool_tier: int) -> float:
	return 0.75 if tool_tier <= 0 else maxf(0.28, 0.48 - float(tool_tier - 1) * 0.05)


## Distribute a node's existing base yield over its strikes, without duplicating items.
static func strike_yield(kind: String, strike: int) -> int:
	var count: int = strikes_needed(kind)
	if count <= 0 or strike < 1 or strike > count:
		return 0
	var amount: int = int(Defs.node_info(kind).get("amount", 0))
	return floori(float(amount * strike) / float(count)) - floori(float(amount * (strike - 1)) / float(count))


## Reject remote hits through walls of distance and hits aimed behind the player.
## A very close target is forgiving so touching a stone is not frustrating.
static func aimed_at(player_pos: Vector3, node: Dictionary, direction: Vector2, reach: float = Defs.REACH + 0.5) -> bool:
	if not player_pos.is_finite() or not direction.is_finite() or direction.length_squared() < 0.01:
		return false
	var offset := Vector2(float(node.get("x", INF)) - player_pos.x,
		float(node.get("z", INF)) - player_pos.z)
	if not offset.is_finite() or offset.length() > reach:
		return false
	return offset.length() <= 0.8 or offset.normalized().dot(direction.normalized()) >= 0.35
