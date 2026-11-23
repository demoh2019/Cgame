@tool
extends RefCounted
## Connects the existing non-destructive TerrainEditLayers authoring data to
## ChunkedTerrain3D's new sparse native patch API. No full-grid rebuild on
## strokes, undo/redo, or layer opacity changes. The game server remains the
## authority for character/world collision during online play.


static func _normal_patch(edit: RefCounted, terrain: ChunkedTerrain3D,
		rect: Rect2i) -> PackedVector3Array:
	var result := PackedVector3Array()
	if terrain.get_normal_data().is_empty():
		return result
	var sx: float = terrain.size.x / float(edit.width - 1)
	var sz: float = terrain.size.y / float(edit.height - 1)
	var scale_y: float = terrain.height_scale
	result.resize(rect.size.x * rect.size.y)
	var k: int = 0
	for z in range(rect.position.y, rect.end.y):
		var za: int = maxi(z - 1, 0)
		var zb: int = mini(z + 1, edit.height - 1)
		for x in range(rect.position.x, rect.end.x):
			var xa: int = maxi(x - 1, 0)
			var xb: int = mini(x + 1, edit.width - 1)
			var dx: float = (edit.composite_height(xa, z) - edit.composite_height(xb, z)) * scale_y / (float(xb - xa) * sx)
			var dz: float = (edit.composite_height(x, za) - edit.composite_height(x, zb)) * scale_y / (float(zb - za) * sz)
			result[k] = Vector3(dx, 1.0, dz).normalized()
			k += 1
	return result


## A single editor brush may dirty more than one terrain cell at borders.
## Each affected cell is submitted with a 1-sample halo so normal derivatives
## and mesh skirts agree across streamed chunk seams. False never clears
## unsupported/mismatched data; no network gameplay values are modified.
static func flush_dirty(edit: RefCounted, terrain: ChunkedTerrain3D) -> Dictionary:
	if edit == null or terrain == null or not is_instance_valid(terrain):
		return {"ok": false, "reason": "no_terrain"}
	if not terrain.has_method("apply_height_patch"):
		return {"ok": false, "reason": "engine_patch_unavailable"}
	var dimensions: Vector2i = terrain.get_height_dimensions()
	if dimensions != Vector2i(int(edit.width), int(edit.height)):
		return {"ok": false, "reason": "dimensions_mismatch"}
	var dirty: Array[Vector2i] = edit.take_dirty_chunks()
	var applied: int = 0
	var full: Rect2i = Rect2i(Vector2i.ZERO, dimensions)
	for coord in dirty:
		var origin: Vector2i = coord * int(edit.chunk_size)
		var rect: Rect2i = Rect2i(origin, Vector2i(int(edit.chunk_size) + 1, int(edit.chunk_size) + 1))
		rect = rect.grow(1).intersection(full)
		if rect.size.x < 1 or rect.size.y < 1:
			continue
		var heights: PackedFloat32Array = edit.composite_region(rect)
		var normals: PackedVector3Array = _normal_patch(edit, terrain, rect)
		if not terrain.apply_height_patch(rect, heights, normals):
			return {"ok": false, "reason": "native_patch_rejected", "applied": applied}
		applied += 1
	return {"ok": true, "applied": applied}
