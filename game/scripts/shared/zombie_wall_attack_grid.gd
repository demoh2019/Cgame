extends RefCounted
## Server-side broadphase for infected that are stuck chasing a survivor.
## Build once per busy infected tick, only when there is a wall attack query.
## Candidate results preserve the exact original barricade insertion order,
## so overlapping walls still take damage in the same deterministic sequence.

const HousePieces = preload("res://scripts/shared/house_pieces.gd")
const CELL_SIZE := 8.0


static func build(barricades: Dictionary) -> Dictionary:
	var ids: Array[int] = []
	var positions: Array[Vector2] = []
	var cells: Dictionary = {}
	for raw_id in barricades:
		var wall: Dictionary = barricades[raw_id]
		var piece: String = str(wall.get("piece", ""))
		if piece != "" and not HousePieces.blocks(piece):
			continue # Floors and roofs are not physical attack targets.
		var x: float = float(wall["x"])
		var z: float = float(wall["z"])
		if not is_finite(x) or not is_finite(z):
			continue
		var at := Vector2(x, z)
		var slot: int = ids.size()
		ids.append(int(raw_id))
		positions.append(at)
		var cell := Vector2i(floori(x / CELL_SIZE), floori(z / CELL_SIZE))
		var bucket: Array = cells.get(cell, [])
		bucket.append(slot)
		cells[cell] = bucket
	return {"ids": ids, "positions": positions, "cells": cells}


## Keep original test: distance <= reach and obstacle strictly in the
## forward half-plane toward the server-verified chase target.
static func candidates(index: Dictionary, here: Vector2, toward: Vector2,
		reach: float) -> Array[int]:
	var result: Array[int] = []
	if not here.is_finite() or not toward.is_finite() or not is_finite(reach) 			or reach < 0.0 or toward.length_squared() <= 0.01:
		return result
	var cells: Dictionary = index.get("cells", {})
	var positions: Array = index.get("positions", [])
	var ids: Array = index.get("ids", [])
	var low := Vector2i(floori((here.x - reach) / CELL_SIZE),
		floori((here.y - reach) / CELL_SIZE))
	var high := Vector2i(floori((here.x + reach) / CELL_SIZE),
		floori((here.y + reach) / CELL_SIZE))
	var selected: Array[int] = []
	var reach_sq: float = reach * reach
	for cx in range(low.x, high.x + 1):
		for cz in range(low.y, high.y + 1):
			var slots: Array = cells.get(Vector2i(cx, cz), [])
			for raw_slot in slots:
				var slot: int = int(raw_slot)
				var offset: Vector2 = positions[slot] - here
				if offset.length_squared() <= reach_sq and offset.dot(toward) > 0.0:
					selected.append(slot)
	# Cell traversal is spatial, not source-order. Restore original wall
	# order before choosing the first eligible blocker to attack.
	selected.sort()
	for slot in selected:
		result.append(int(ids[slot]))
	return result
