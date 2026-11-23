extends RefCounted
## Spatial acceleration must return exactly the same blocker dictionaries as
## the old full-chunk scan, including depletion, boundaries and duplicate spans.

const StaticBlockerGrid = preload("res://scripts/shared/static_blocker_grid.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")


static func _legacy_chunk(data: Dictionary, x: float, z: float,
		radius: float, depleted: Dictionary) -> Array:
	var result: Array = []
	for group in ["nodes", "crates", "structures", "props"]:
		for item in data.get(group, []):
			if group == "nodes" and depleted.has(item["id"]):
				continue
			if bool(item["blocks"]) and absf(float(item["x"]) - x) < radius + float(item["radius"]) \
					and absf(float(item["z"]) - z) < radius + float(item["radius"]):
				result.append(item)
	return result


func run(t) -> void:
	t.current = "grid candidate parity and large overlapping rocks"
	var origin := Vector2(128.0, -64.0)
	var data: Dictionary = {
		"nodes": [
			{"id": 1, "x": 131.0, "z": -61.0, "radius": 0.5, "blocks": true, "kind": "tree"},
			{"id": 2, "x": 151.5, "z": -41.0, "radius": 6.0, "blocks": true, "kind": "rock"},
			{"id": 3, "x": 190.0, "z": -1.0, "radius": 3.0, "blocks": true, "kind": "rock"},
			{"id": 4, "x": 142.0, "z": -42.0, "radius": 2.0, "blocks": false, "kind": "pebble"},
		],
		"crates": [
			{"id": 5, "x": 167.0, "z": -28.0, "radius": 1.5, "blocks": true},
		],
		"structures": [
			{"id": 6, "x": 183.0, "z": -50.0, "radius": 8.0, "blocks": true},
		],
		"props": [
			{"id": 7, "x": 129.0, "z": -4.0, "radius": 3.0, "blocks": true},
		],
	}
	var grid: Dictionary = StaticBlockerGrid.build(data, origin)
	t.eq((grid["entries"] as Array).size(), 6,
		"broadphase indexes only collidable objects once each")
	var sample_tile: Array = grid["tiles"][0]
	t.check(sample_tile.size() < (grid["entries"] as Array).size(),
		"nearby queries skip unrelated far-away objects")
	for depleted in [{}, {2: true}, {1: true, 3: true}]:
		for xx in range(-2, 19):
			for zz in range(-2, 19):
				var x: float = origin.x + float(xx) * 4.0
				var z: float = origin.y + float(zz) * 4.0
				for r in [0.0, 1.5, 4.5]:
					t.eq(StaticBlockerGrid.query(grid, origin, x, z, r, depleted),
						_legacy_chunk(data, x, z, r, depleted),
						"exact broadphase parity even near tile borders")
	t.current = "live world broadphase matches complete chunk scan"
	var world := WorldGen.new(42)
	for i in 24:
		var x: float = 230.0 + float(i % 6) * 6.0
		var z: float = 290.0 + float(i / 6) * 6.0
		var radius := 1.8
		var previous: Array = []
		var from_cell: Vector2i = WorldGen.cell_of(x - radius, z - radius)
		var to_cell: Vector2i = WorldGen.cell_of(x + radius, z + radius)
		for cx in range(from_cell.x, to_cell.x + 1):
			for cz in range(from_cell.y, to_cell.y + 1):
				previous.append_array(_legacy_chunk(
					world.chunk(Vector2i(cx, cz)), x, z, radius, world.depleted_blockers))
		t.eq(world.blockers_near(x, z, radius), previous,
			"real generated scene preserves blocker ordering and content")
