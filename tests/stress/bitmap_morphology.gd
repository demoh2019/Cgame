extends RefCounted
## Benchmarks one-pixel morphology and larger disk-based grow/shrink.


func run(scale: int) -> Dictionary:
	const WIDTH := 192
	const HEIGHT := 160
	const MASK_RECT := Rect2i(0, 0, WIDTH, HEIGHT)
	var iterations := mini(10 * scale, 500)
	var one_pixel_ms := 0.0
	var disk_radius_ms := 0.0
	var checksum := 0

	for i in range(iterations):
		var bitmap := BitMap.new()
		bitmap.create(Vector2i(WIDTH, HEIGHT))
		bitmap.set_bit_rect(Rect2i(15 + i % 11, 13, 100, 90), true)
		var started := Time.get_ticks_usec()
		bitmap.grow_mask(1, MASK_RECT)
		bitmap.grow_mask(-1, MASK_RECT)
		one_pixel_ms += float(Time.get_ticks_usec() - started) / 1000.0

		started = Time.get_ticks_usec()
		bitmap.grow_mask(8, MASK_RECT)
		bitmap.grow_mask(-8, MASK_RECT)
		disk_radius_ms += float(Time.get_ticks_usec() - started) / 1000.0
		var count := bitmap.get_true_bit_count()
		if count <= 0 or count > WIDTH * HEIGHT:
			return {"error": "BitMap morphology returned invalid opaque pixel count"}
		checksum += count

	return {
		"iterations": iterations,
		"one_pixel_ms": one_pixel_ms,
		"disk_radius_ms": disk_radius_ms,
		"checksum": checksum,
	}
