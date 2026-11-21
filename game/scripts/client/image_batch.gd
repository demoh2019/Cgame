extends RefCounted
## CPU image subrectangle updates shared by world atlas and procedural sky LUTs.
## Cgame's native packed write avoids a script/native crossing for every pixel.
## Stock Godot uses the original pixel-by-pixel equivalent.


static func set_rect(image: Image, rect: Rect2i, colors: PackedColorArray,
		force_scalar: bool = false) -> bool:
	if image == null or image.is_empty() or image.is_compressed():
		return false
	if rect.position.x < 0 or rect.position.y < 0 or rect.size.x <= 0 or rect.size.y <= 0:
		return false
	if rect.size.x > image.get_width() or rect.size.y > image.get_height():
		return false
	if rect.position.x > image.get_width() - rect.size.x or 			rect.position.y > image.get_height() - rect.size.y:
		return false
	if colors.size() != rect.size.x * rect.size.y:
		return false
	if not force_scalar and image.has_method("set_pixels_rect"):
		image.call("set_pixels_rect", rect, colors)
		return true
	for y in rect.size.y:
		for x in rect.size.x:
			image.set_pixel(rect.position.x + x, rect.position.y + y,
					colors[y * rect.size.x + x])
	return true


static func set_row(image: Image, y: int, colors: PackedColorArray,
		force_scalar: bool = false) -> bool:
	if image == null:
		return false
	return set_rect(image, Rect2i(0, y, image.get_width(), 1), colors, force_scalar)
