extends RefCounted
## Cheap CPU-baked contact-occlusion mask for streamed terrain. The mask is
## visual only: no collisions, server data or extra shadow-map passes.
## One 64x64 L8 texture (4 KiB of raw pixels) per above-ground chunk.

const SIZE := 64
const EDGE_FADE_METERS := 2.5


static func mask_bytes(origin: Vector2, chunk_size: float,
		nodes: Array, structures: Array, hidden_ids: Dictionary = {}) -> PackedByteArray:
	var pixels := PackedByteArray()
	pixels.resize(SIZE * SIZE)
	pixels.fill(255) # White means no contact shadow, including missing data.
	if not is_finite(chunk_size) or chunk_size <= 0.0:
		return pixels
	for entry in nodes:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = entry
		if node.has("id") and hidden_ids.has(node["id"]):
			continue
		var kind: String = str(node.get("kind", ""))
		match kind:
			"tree":
				_stamp(pixels, origin, chunk_size, node, 2.8, 0.46)
			"rock", "ore":
				_stamp(pixels, origin, chunk_size, node, 1.5, 0.34)
			"bush", "berry":
				_stamp(pixels, origin, chunk_size, node, 1.4, 0.22)
	for entry in structures:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var structure: Dictionary = entry
		if structure.has("id") and hidden_ids.has(structure["id"]):
			continue
		var kind: String = str(structure.get("kind", ""))
		if kind == "workbench":
			_stamp(pixels, origin, chunk_size, structure, 1.6, 0.36)
		elif kind == "windmill" or kind == "tower" or kind == "building":
			_stamp(pixels, origin, chunk_size, structure, 4.0, 0.5)
		else:
			_stamp(pixels, origin, chunk_size, structure, 2.8, 0.43)
	return pixels


## Local, bounded rasterization. Cost is proportional to the stamp footprint
## rather than evaluating every object for every pixel in the chunk.
static func _stamp(pixels: PackedByteArray, origin: Vector2, chunk_size: float,
		item: Dictionary, radius: float, depth: float) -> void:
	if not item.has("x") or not item.has("z"):
		return
	var center := Vector2(float(item["x"]), float(item["z"])) - origin
	if not is_finite(center.x) or not is_finite(center.y):
		return
	var step: float = chunk_size / float(SIZE)
	var left: int = clampi(floori((center.x - radius) / step - 0.5), 0, SIZE - 1)
	var right: int = clampi(ceili((center.x + radius) / step - 0.5), 0, SIZE - 1)
	var top: int = clampi(floori((center.y - radius) / step - 0.5), 0, SIZE - 1)
	var bottom: int = clampi(ceili((center.y + radius) / step - 0.5), 0, SIZE - 1)
	for z in range(top, bottom + 1):
		for x in range(left, right + 1):
			var point := (Vector2(float(x), float(z)) + Vector2.ONE * 0.5) * step
			var dist: float = point.distance_to(center)
			if dist >= radius:
				continue
			# Fade the imprint before the chunk boundary. Neighbour chunks do
			# not need to be loaded merely to reproduce this contact mask.
			var edge: float = minf(minf(point.x, chunk_size - point.x),
				minf(point.y, chunk_size - point.y))
			var border: float = smoothstep(0.0, EDGE_FADE_METERS, edge)
			var coverage: float = 1.0 - smoothstep(0.0, radius, dist)
			var shade: int = clampi(roundi(255.0 *
				(1.0 - depth * coverage * coverage * border)), 0, 255)
			var index: int = z * SIZE + x
			if shade < pixels[index]:
				pixels[index] = shade


static func create_texture(origin: Vector2, chunk_size: float,
		nodes: Array, structures: Array, hidden_ids: Dictionary = {}) -> ImageTexture:
	var pixels: PackedByteArray = mask_bytes(origin, chunk_size, nodes,
		structures, hidden_ids)
	var image: Image = Image.create_from_data(
		SIZE, SIZE, false, Image.FORMAT_L8, pixels)
	return ImageTexture.create_from_image(image)
