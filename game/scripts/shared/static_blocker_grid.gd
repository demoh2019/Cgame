extends RefCounted
## Per-chunk broadphase for static, generated movement obstacles.
## A node's footprint is indexed into each overlapping 8 m tile once;
## hot movement queries test only tile candidates, not every tree/rock/prop.
## No physics resources, no per-frame rebuild, and no changed chunk data.

const TILE_SIZE := 8.0
const TILES_PER_AXIS := 8
const TILE_COUNT := TILES_PER_AXIS * TILES_PER_AXIS


static func build(data: Dictionary, origin: Vector2) -> Dictionary:
	var entries: Array = [] # Original blocker dictionary and whether it is a depletable node.
	var tiles: Array = []
	tiles.resize(TILE_COUNT)
	for i in TILE_COUNT:
		tiles[i] = []
	for group in ["nodes", "crates", "structures", "props"]:
		for blocker in data.get(group, []):
			if not bool(blocker.get("blocks", false)):
				continue
			var at_x: float = float(blocker["x"])
			var at_z: float = float(blocker["z"])
			var r: float = float(blocker["radius"])
			var min_x: int = clampi(floori((at_x - r - origin.x) / TILE_SIZE), 0, TILES_PER_AXIS - 1)
			var max_x: int = clampi(floori((at_x + r - origin.x) / TILE_SIZE), 0, TILES_PER_AXIS - 1)
			var min_z: int = clampi(floori((at_z - r - origin.y) / TILE_SIZE), 0, TILES_PER_AXIS - 1)
			var max_z: int = clampi(floori((at_z + r - origin.y) / TILE_SIZE), 0, TILES_PER_AXIS - 1)
			var entry_id: int = entries.size()
			entries.append({"value": blocker, "node": group == "nodes"})
			for iz in range(min_z, max_z + 1):
				for ix in range(min_x, max_x + 1):
					var tile: Array = tiles[iz * TILES_PER_AXIS + ix]
					tile.append(entry_id)
	return {"entries": entries, "tiles": tiles}


## Exact previous collision predicate. The tile grid is only a broadphase;
## all candidate radii and strict boundaries remain unchanged.
static func query(index: Dictionary, origin: Vector2, x: float, z: float,
		radius: float, depleted: Dictionary = {}) -> Array:
	var result: Array = []
	if radius < 0.0 or not is_finite(x) or not is_finite(z) or not is_finite(radius):
		return result
	var entries: Array = index["entries"]
	var tiles: Array = index["tiles"]
	var min_x: int = clampi(floori((x - radius - origin.x) / TILE_SIZE), 0, TILES_PER_AXIS - 1)
	var max_x: int = clampi(floori((x + radius - origin.x) / TILE_SIZE), 0, TILES_PER_AXIS - 1)
	var min_z: int = clampi(floori((z - radius - origin.y) / TILE_SIZE), 0, TILES_PER_AXIS - 1)
	var max_z: int = clampi(floori((z + radius - origin.y) / TILE_SIZE), 0, TILES_PER_AXIS - 1)
	var visited: Dictionary = {}
	var matched: Array[int] = []
	for iz in range(min_z, max_z + 1):
		for ix in range(min_x, max_x + 1):
			for raw_id in tiles[iz * TILES_PER_AXIS + ix]:
				var entry_id: int = int(raw_id)
				if visited.has(entry_id):
					continue
				visited[entry_id] = true
				var entry: Dictionary = entries[entry_id]
				var node: Dictionary = entry["value"]
				if bool(entry["node"]) and depleted.has(node["id"]):
					continue
				var reach: float = radius + float(node["radius"])
				if absf(float(node["x"]) - x) < reach and absf(float(node["z"]) - z) < reach:
					matched.append(entry_id)
	# Multiple tiles may overlap the search; preserve the original stable
	# category/source order for deterministic movement and test parity.
	matched.sort()
	for entry_id in matched:
		result.append(entries[entry_id]["value"])
	return result
