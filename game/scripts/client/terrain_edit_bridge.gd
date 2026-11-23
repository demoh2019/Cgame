@tool
extends RefCounted
## Applies the existing TerrainEditLayers dirty regions to a real large-world
## ChunkedTerrain3D. The native engine owns normal recomputation and local
## collision/LOD invalidation; the online game's world physics stay server-owned.

const TerrainEditLayers = preload("res://scripts/shared/terrain_edit_layers.gd")


const MAX_PATCH_SIDE := 60 # 3600 height samples, below the native 4096 cap.


## Re-queue all dirty chunks after any native rejection: successful early
## subregions can be safely replayed because identical patches are no-ops.
static func _restore_dirty(edit: TerrainEditLayers, chunks: Array[Vector2i]) -> void:
	for coord in chunks:
		var origin: Vector2i = coord * edit.chunk_size
		edit._mark_rect_dirty(Rect2i(origin,
			Vector2i(edit.chunk_size + 1, edit.chunk_size + 1)))


static func flush_dirty(edit: TerrainEditLayers, terrain: ChunkedTerrain3D) -> Dictionary:
	if edit == null or terrain == null or not is_instance_valid(terrain):
		return {"ok": false, "reason": "no_terrain"}
	if not terrain.has_method("apply_height_patch"):
		return {"ok": false, "reason": "engine_patch_unavailable"}
	var dimensions: Vector2i = terrain.get_height_dimensions()
	if dimensions != Vector2i(edit.width, edit.height):
		return {"ok": false, "reason": "dimensions_mismatch"}
	var changed_chunks: Array[Vector2i] = edit.take_dirty_chunks()
	var applied: int = 0
	var full: Rect2i = Rect2i(Vector2i.ZERO, dimensions)
	for coord in changed_chunks:
		var origin: Vector2i = coord * edit.chunk_size
		var rect: Rect2i = Rect2i(origin,
			Vector2i(edit.chunk_size + 1, edit.chunk_size + 1))
		rect = rect.grow(1).intersection(full)
		if rect.size.x <= 0 or rect.size.y <= 0:
			continue
		# Keep every atomic native transaction below its 4096-sample cap
		# even if an editor terrain chunk spans 128 or 256 quads.
		for z in range(rect.position.y, rect.end.y, MAX_PATCH_SIDE):
			for x in range(rect.position.x, rect.end.x, MAX_PATCH_SIDE):
				var subregion := Rect2i(x, z,
					mini(MAX_PATCH_SIDE, rect.end.x - x),
					mini(MAX_PATCH_SIDE, rect.end.y - z))
				if not terrain.apply_height_patch(subregion, edit.composite_region(subregion)):
					_restore_dirty(edit, changed_chunks)
					return {"ok": false, "reason": "native_patch_rejected", "applied": applied}
				applied += 1
	return {"ok": true, "applied": applied}
