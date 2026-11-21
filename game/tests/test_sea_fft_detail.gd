extends RefCounted
## FFT chop textures for the sea shader.

const SeaFftDetail = preload("res://scripts/client/sea_fft_detail.gd")


func run(t) -> void:
	t.current = "sea fft detail"
	t.eq(SeaFftDetail.strength_for(0), 0.0, "Performance keeps pure Gerstner")
	t.check(SeaFftDetail.strength_for(3) > SeaFftDetail.strength_for(2), "Ultra chops harder than High")
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/water.gdshader")
	var node: Node = SeaFftDetail.new()
	node.setup(material, 3, 7)
	var tex_a: Texture2D = material.get_shader_parameter("fft_height_a")
	t.check(tex_a != null and tex_a.get_width() == SeaFftDetail.GRID, "height tile bound to the shader")
	t.near(float(material.get_shader_parameter("fft_strength")), 0.26, 0.0001, "strength follows the preset")
	var before: Image = tex_a.get_image()
	node.set("_level_poll", -1000.0) # Do not poll the full graphics stack in this test.
	node._process(0.12)
	var after: Image = (material.get_shader_parameter("fft_height_a") as Texture2D).get_image()
	# The headless dummy renderer does not store texture updates; check the clock instead.
	t.near(float(node.get("_t0")), 0.1, 0.0001, "the spectrum advanced one step")
	t.check(before.get_size() == after.get_size(), "tile size is stable")
	var blend: float = float(material.get_shader_parameter("fft_blend"))
	t.check(blend >= 0.0 and blend <= 1.0, "cross-fade weight is bounded")
	var peak := 0.0
	for y in after.get_height():
		for x in after.get_width():
			peak = maxf(peak, absf(after.get_pixel(x, y).r))
	t.near(peak, 1.0, 0.0001, "tiles are normalised to unit height")
	node.free()
