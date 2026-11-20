extends RefCounted
## Terrain noise LOD must preserve nearby authored biome transitions while
## reducing per-fragment procedural work on distant chunk terrain.

const Quality = preload("res://scripts/client/graphics_quality.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")


func run(t) -> void:
	t.current = "distance-aware terrain noise"
	t.eq(ChunkView.SAMPLES, 33, "terrain uses a predictable vertex grid for interpolated macro fields")
	var prev_radius: float = 0.0
	for quality in 4:
		var radius: float = float(Quality.profile(quality)["terrain_detail_radius"])
		t.check(radius > prev_radius, "higher quality preserves pixel noise farther away")
		prev_radius = radius
		# Same smooth transition used for the game's material normal/detail LOD.
		var near_weight: float = 1.0 - smoothstep(radius, radius + 24.0, 0.0)
		var edge_weight: float = 1.0 - smoothstep(radius, radius + 24.0, radius + 24.0)
		t.near(near_weight, 1.0, 0.000001, "near terrain keeps exact full-resolution procedural noise")
		t.near(edge_weight, 0.0, 0.000001, "far terrain uses interpolated vertex noise")
		var last: float = 1.0
		for step in 13:
			var d: float = radius + float(step) * 2.0
			var strength: float = 1.0 - smoothstep(radius, radius + 24.0, d)
			t.check(strength >= 0.0 and strength <= last + 0.000001,
				"noise detail fades monotonically, without jumps")
			last = strength

	t.current = "shader fragment work is gated behind existing LOD"
	var asset := load("res://assets/shaders/ground.gdshader") as Shader
	t.check(asset != null, "real PBR terrain shader loads")
	if asset == null:
		return
	var code: String = asset.code
	# The include also declares helper functions before fragment(); compare
	# the ordering only inside the actual per-pixel shader stage.
	var fragment_code: String = code.substr(code.find("void fragment() {"))
	t.check(code.contains("varying float aa_vertex_mid;"),
		"medium-scale noise is passed from vertex to fragment")
	t.check(code.contains("aa_vertex_mid = fbm(world_position.xz * 0.07 + 3.0);"),
		"original noise frequency and seed are retained")
	t.check(code.contains("float mid = aa_vertex_mid;"),
		"far distance defaults to cheap interpolated field")
	t.check(code.contains("if (detail_fade > 0.001) {"),
		"expensive per-pixel noise runs only within detail budget")
	t.check(code.contains("mid = mix(aa_vertex_mid, fbm(p * 0.07 + 3.0), detail_fade);"),
		"near pixels use identical original procedural noise, far pixels use vertex noise")
	t.check(code.contains("float mixer = 0.5;"),
		"subpixel texture mixer has deterministic inexpensive fallback")
	t.check(code.contains("mixer = smoothstep(0.3, 0.7, value_noise(p * 0.05 + 11.0));"),
		"near texture tiling preserves original noise function")
	t.check(fragment_code.find("vec2 lod_dx = dFdx(p / tile_meters);") <
		fragment_code.find("if (detail_fade > 0.001) {"),
		"texture gradients are calculated before conditional fragment work")
	t.check(code.contains("w[int(patch.w)] += paved") and code.contains("textureGrad(albedo_layers"),
		"ruins, roads and imported PBR texture sampling remain intact")
	t.check(code.contains("aa_weather_wetness") and code.contains("aa_puddle_ripple_tilt"),
		"wetness and nearby animated puddles remain intact")
	t.check(code.contains("aa_vertex_cloud_shadow = cloud_shadow(") and
		code.contains("aa_macro_broad = fbm("),
		"previous vertex-LOD cloud and broad color fields remain intact")
