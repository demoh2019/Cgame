extends RefCounted
## Rust-like resource interaction rules shared by the client and authoritative server.
## The server owns all depletion, strike progress, cooldowns and inventory rewards.

const Defs = preload("res://scripts/shared/defs.gd")
const PROGRESS_EXPIRE_SECONDS := 45.0

static func is_pickup(kind: String) -> bool:
	return kind in ["pebble", "branch", "bush", "berry"]


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
## Interaction reach extends to the edge of large fallen logs and rocks.
## Normal upright trees keep their short centre-based reach.
static func reach_margin(node: Dictionary) -> float:
	var radius: float = float(node.get("radius", 0.0))
	if node.has("solid_model"):
		return minf(radius, 3.0)
	if str(node.get("kind", "")) in ["rock", "ore", "pebble"]:
		return minf(radius, 1.8)
	return 0.0


static func aimed_at(player_pos: Vector3, node: Dictionary, direction: Vector2, reach: float = Defs.REACH + 0.5) -> bool:
	if not player_pos.is_finite() or not direction.is_finite() or direction.length_squared() < 0.01:
		return false
	var offset := Vector2(float(node.get("x", INF)) - player_pos.x,
		float(node.get("z", INF)) - player_pos.z)
	if not offset.is_finite():
		return false
	var margin: float = reach_margin(node)
	if offset.length() > reach + margin:
		return false
	return offset.length() <= 0.8 + margin or offset.normalized().dot(direction.normalized()) >= 0.35


## Weak spots rotate around a node after each confirmed hit. The position is
## reproducible from its stable world id + strike count; the client never
## supplies coordinates, damage or bonus values to the server.
static func weakspot_position(node: Dictionary, completed_hits: int) -> Vector3:
	var id: int = int(node.get("id", 0))
	var index: int = maxi(0, completed_hits)
	# Reduce first: world-node IDs can be near int64 limits. Multiplying the
	# full ID would overflow and move the client/server weak spot marker.
	var angle_degrees: int = posmod(posmod(id, 360) * 37 + posmod(index, 360) * 107, 360)
	var angle: float = deg_to_rad(float(angle_degrees))
	var kind: String = str(node.get("kind", ""))
	var radius: float = clampf(float(node.get("radius", 0.5)) * (0.6 if kind == "tree" else 0.72), 0.22, 1.1)
	var height: float = 1.05 if kind == "tree" else clampf(float(node.get("radius", 0.6)) * 0.85, 0.38, 1.2)
	return Vector3(float(node.get("x", 0.0)) + cos(angle) * radius,
		float(node.get("y", 0.0)) + height,
		float(node.get("z", 0.0)) + sin(angle) * radius)


## The extra resource goes only to a real, aimed, in-range hit. This check
## derives the target from the server's own progress, not a client hit flag.
static func precise_strike(player_pos: Vector3, node: Dictionary,
		direction: Vector2, completed_hits: int) -> bool:
	if not aimed_at(player_pos, node, direction):
		return false
	var target: Vector3 = weakspot_position(node, completed_hits)
	var to_target := Vector2(target.x - player_pos.x, target.z - player_pos.z)
	if not to_target.is_finite() or to_target.length_squared() < 0.01:
		return false
	return to_target.normalized().dot(direction.normalized()) >= 0.985
