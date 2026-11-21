extends RefCounted
## The world-map water ramp produces the same colors as direct Color.lerp
## on native Cgame and on unmodified Godot.

const GradientBatch = preload("res://scripts/client/gradient_batch.gd")


func run(t) -> void:
	t.current = "gradient batch fallback"
	var shallow := Color("#6e909a")
	var deep := Color("#3f5e6e")
	var gradient: Gradient = GradientBatch.make_gradient(shallow, deep)
	var offsets := PackedFloat32Array([1.0, 0.0, 0.25, 0.7, 0.5, 0.25, 0.9, 0.0])
	var scalar: PackedColorArray = GradientBatch.sample_many(gradient, offsets, true)
	var auto: PackedColorArray = GradientBatch.sample_many(gradient, offsets)
	t.eq(scalar.size(), offsets.size(), "scalar sample count")
	t.eq(auto.size(), scalar.size(), "native or fallback sample count")
	for i in offsets.size():
		var expected: Color = shallow.lerp(deep, offsets[i])
		t.check(scalar[i].is_equal_approx(expected), "scalar ramp matches original chart water colors")
		t.check(auto[i].is_equal_approx(scalar[i]), "native ramp matches scalar on every offset")
	t.eq(GradientBatch.sample_many(gradient, PackedFloat32Array()).size(), 0, "empty offsets produce empty colors")
	t.eq(GradientBatch.sample_many(null, offsets).size(), 0, "missing gradient produces no colors")

	t.current = "gradient batch interpolation modes"
	gradient.set_offsets(PackedFloat32Array([0.0, 0.37, 1.0]))
	gradient.set_colors(PackedColorArray([Color.RED, Color.GREEN, Color.BLUE]))
	for mode in [Gradient.GRADIENT_INTERPOLATE_LINEAR, Gradient.GRADIENT_INTERPOLATE_CONSTANT, Gradient.GRADIENT_INTERPOLATE_CUBIC]:
		gradient.interpolation_mode = mode
		for space in [Gradient.GRADIENT_COLOR_SPACE_SRGB, Gradient.GRADIENT_COLOR_SPACE_LINEAR_SRGB, Gradient.GRADIENT_COLOR_SPACE_OKLAB]:
			gradient.interpolation_color_space = space
			var colors: PackedColorArray = GradientBatch.sample_many(gradient, offsets)
			for i in offsets.size():
				t.check(colors[i].is_equal_approx(gradient.sample(offsets[i])), "native samples honor interpolation and colorspace")
