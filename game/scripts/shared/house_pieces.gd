extends RefCounted
## House building: floors, walls, doorways, windows, roofs and pillars that snap to a 3 m grid so
## pieces line up into real houses. Shared by the server (validation, collision) and the client
## (ghost preview, rendering). A placed piece is an ordinary player structure (barricades), so
## repair, upgrade, upkeep, decay and dismantling work exactly as for the old walls.
##
## Grid: cells are GRID metres square. Floors and roofs sit on a cell centre; walls, doorways and
## windows on the middle of a cell edge; pillars on a cell corner. A wall's line runs along
## (sin(yaw), cos(yaw)): yaw 0 for edges facing +-X, PI/2 for edges facing +-Z.

const GRID := 3.0
const WALL_HEIGHT := 3.0
const BUILD_RANGE := 7.0
const PIECES := ["wall", "door", "window", "floor", "roof", "pillar", "bed", "lamp"]
const NAMES := {"wall": "Wall", "door": "Door", "window": "Window wall", "floor": "Floor", "roof": "Roof", "pillar": "Pillar",
	"bed": "Bed", "lamp": "Lamp"}
const DOOR_REACH := 3.0
const BED_RESPAWN_RANGE := 2.5
const COST := {
	"wall": {"wood_1": 4},
	"door": {"wood_1": 3},
	"window": {"wood_1": 3, "stone_1": 1},
	"floor": {"wood_1": 3},
	"roof": {"wood_1": 4, "stone_1": 1},
	"pillar": {"wood_1": 2},
	"bed": {"wood_1": 4, "cloth_1": 3},
	"lamp": {"wood_1": 2, "stone_1": 2},
}


static func valid(piece: String) -> bool:
	return piece in PIECES


## Which pieces compete for the same spot: one wall-type per edge, one floor, one roof, one pillar.
static func slot(piece: String) -> String:
	if piece in ["wall", "door", "window"]:
		return "edge"
	return "furniture" if piece in ["bed", "lamp"] else piece


static func elevation(piece: String) -> float:
	return WALL_HEIGHT if piece == "roof" else 0.0


static func blocks(piece: String) -> bool:
	return piece in ["wall", "door", "window", "pillar", "bed", "lamp"]


## The snapped position and facing for a piece aimed at `point` (x, z, yaw).
static func snap(piece: String, point: Vector2) -> Vector3:
	var cell := Vector2(floorf(point.x / GRID), floorf(point.y / GRID))
	var center := (cell + Vector2(0.5, 0.5)) * GRID
	match piece:
		"floor", "roof", "bed", "lamp":
			return Vector3(center.x, center.y, 0.0)
		"pillar":
			var corner := Vector2(roundf(point.x / GRID), roundf(point.y / GRID)) * GRID
			return Vector3(corner.x, corner.y, 0.0)
	# Walls: the nearest of the cell's four edge midpoints.
	var local := point - center
	if absf(local.x) >= absf(local.y):
		return Vector3(center.x + signf(local.x if local.x != 0.0 else 1.0) * GRID * 0.5, center.y, 0.0)
	return Vector3(center.x, center.y + signf(local.y if local.y != 0.0 else 1.0) * GRID * 0.5, PI * 0.5)


## Movement blockers (x, z, radius) of a placed piece. Doorways leave the middle open.
static func blockers(piece: String, x: float, z: float, yaw: float, closed: bool = false) -> Array:
	var along := Vector2(sin(yaw), cos(yaw))
	var at := Vector2(x, z)
	var result: Array = []
	match piece:
		"wall", "window":
			for k in [-1.0, 0.0, 1.0]:
				var p: Vector2 = at + along * float(k)
				result.append([p.x, p.y, 0.55])
		"door":
			for k in [-1.15, 1.15]:
				var p: Vector2 = at + along * float(k)
				result.append([p.x, p.y, 0.4])
			if closed:
				result.append([x, z, 0.5]) # A shut door fills the gap.
		"pillar":
			result.append([x, z, 0.3])
		"bed":
			result.append([x, z, 0.6])
		"lamp":
			result.append([x, z, 0.25])
	return result


## "" when the piece may go there (terrain, range, hub), otherwise the reason. Overlap with other
## pieces, people and materials are checked by the server.
static func placement_reason(world, piece: String, snapped: Vector3, from: Vector2) -> String:
	if not valid(piece):
		return "invalid_piece"
	var point := Vector2(snapped.x, snapped.y)
	if not point.is_finite() or not from.is_finite():
		return "invalid_position"
	if point.distance_to(from) > BUILD_RANGE:
		return "out_of_range"
	if point.length() < 50.0:
		return "safe_zone"
	if world.is_water(point.x, point.y) or world.normal_at(point.x, point.y).y < 0.72:
		return "bad_terrain"
	if blocks(piece):
		for circle in blockers(piece, snapped.x, snapped.y, snapped.z):
			for blocker in world.blockers_near(float(circle[0]), float(circle[1]), float(circle[2]) + 1.0):
				if str(blocker.get("piece_owner", "")) != "":
					continue # Other house pieces are checked by slot, not by circles.
				var offset := Vector2(float(circle[0]) - float(blocker["x"]), float(circle[1]) - float(blocker["z"]))
				if offset.length() < float(circle[2]) + float(blocker["radius"]) + 0.05:
					return "blocked"
	return ""


## Movement blockers of a stored piece record (doors use their open state).
static func blockers_of(item: Dictionary) -> Array:
	var piece: String = str(item.get("piece", ""))
	var closed: bool = piece == "door" and not bool(item.get("open", true))
	return blockers(piece, float(item["x"]), float(item["z"]), float(item.get("yaw", 0.0)), closed)
