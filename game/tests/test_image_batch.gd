extends RefCounted
## CPU packed pixel writes must preserve exactly the same bytes as repeated
## Image.set_pixel calls on both Cgame and stock Godot.

const ImageBatch = preload("res://scripts/client/image_batch.gd")


func run(t) -> void:
	t.current = "image batch pixel parity"
	for format in [Image.FORMAT_L8, Image.FORMAT_RGB8, Image.FORMAT_RGBA8, Image.FORMAT_RGBAF]:
		var packed := Image.create(7, 5, false, format)
		var scalar := Image.create(7, 5, false, format)
		packed.fill(Color(0.16, 0.24, 0.39, 0.6))
		scalar.fill(Color(0.16, 0.24, 0.39, 0.6))
		var colors := PackedColorArray()
		for y in 3:
			for x in 4:
				colors.append(Color(float(x + 1) / 5.0, float(y + 1) / 4.0, 0.62, float(x + y) / 6.0))
		var rect := Rect2i(2, 1, 4, 3)
		t.check(ImageBatch.set_rect(packed, rect, colors), "packed write accepts rectangle")
		t.check(ImageBatch.set_rect(scalar, rect, colors, true), "stock-Godot fallback accepts rectangle")
		t.eq(packed.get_data(), scalar.get_data(), "all pixels match scalar bytes for this format")

		var before: PackedByteArray = packed.get_data()
		t.check(not ImageBatch.set_rect(packed, Rect2i(-1, 1, 4, 3), colors), "negative offset rejected")
		t.check(not ImageBatch.set_rect(packed, Rect2i(4, 3, 4, 3), colors), "overflowing rectangle rejected")
		t.check(not ImageBatch.set_rect(packed, rect, PackedColorArray([Color.WHITE])), "incomplete rectangle data rejected")
		t.eq(packed.get_data(), before, "invalid writes never partially modify the image")

	t.current = "map and cloud row helper"
	var chart := Image.create(8, 3, false, Image.FORMAT_RGB8)
	var old := Image.create(8, 3, false, Image.FORMAT_RGB8)
	var row := PackedColorArray()
	for x in 8:
		row.append(Color(float(x) / 8.0, 0.4, 0.7))
	t.check(ImageBatch.set_row(chart, 2, row), "last row can be written")
	t.check(ImageBatch.set_row(old, 2, row, true), "last-row fallback can be written")
	t.eq(chart.get_data(), old.get_data(), "chart row upload matches scalar")
	t.check(not ImageBatch.set_row(chart, 3, row), "out-of-range row rejected")
	t.eq(chart.get_data(), old.get_data(), "out-of-range row leaves chart unchanged")
