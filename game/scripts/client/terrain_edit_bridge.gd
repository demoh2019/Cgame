@tool
extends RefCounted
## Applies the existing TerrainEditLayers dirty regions to a real large-world
## ChunkedTerrain3D. The native engine owns normal recomputation and local
## collision/LOD invalidation; the online game's world physics stay server-owned.

const TerrainEditLayers = preload("res://scripts/shared/terrain_edit_layers.gd")


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
		# The engine caps an atomic height patch at 4096 values.
		# Typical editor chunks (16 or 32 quads plus halo) remain below it.
		if rect.get_area() > 4096:
			edit._mark_rect_dirty(rect)
			return {"ok": false, "reason": "patch_too_large", "applied": applied}
		if not terrain.apply_height_patch(rect, edit.composite_region(rect)):
			# A refused native update must remain retryable, not lost.
			edit._mark_rect_dirty(rect)
			return {"ok": false, "reason": "native_patch_rejected", "applied": applied}
		applied += 1
	return {"ok": true, "applied": applied}
