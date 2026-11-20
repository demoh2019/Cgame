extends Node3D
## Short-lived particle effects (hits, deaths, pickups, level ups, dust), the rain that follows the camera, and the life
## of the wilds around the player: pollen drifting in the sun, butterflies, leaves falling in the forest, fireflies at night.

var _rain: CPUParticles3D
var _rain_amount := 0.0
var _dust_timer := 0.0
var _pollen: CPUParticles3D
var _butterflies: CPUParticles3D
var _leaves: CPUParticles3D
var _fireflies: CPUParticles3D

const BUTTERFLY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D wings : source_color, filter_linear_mipmap;
void vertex() {
	// Wings beat: the quad (lying flat, seen from above) folds toward its body line and opens again.
	float beat = abs(sin(TIME * 17.0 + MODEL_MATRIX[3].x * 1.7 + MODEL_MATRIX[3].z * 2.3));
	VERTEX.x *= mix(0.2, 1.0, beat);
	VERTEX.y += abs(VERTEX.x) * (1.0 - beat) * 0.8;
}
void fragment() {
	vec4 t = texture(wings, UV);
	ALBEDO = t.rgb * COLOR.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""


func _ready() -> void:
	_rain = CPUParticles3D.new()
	_rain.amount = 700
	_rain.lifetime = 0.9
	_rain.preprocess = 0.9
	_rain.emitting = false
	_rain.local_coords = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(26.0, 0.5, 26.0)
	_rain.direction = Vector3(0.12, -1.0, 0.05)
	_rain.spread = 3.0
	_rain.gravity = Vector3.ZERO
	_rain.initial_velocity_min = 30.0
	_rain.initial_velocity_max = 38.0
	var streak := BoxMesh.new()
	streak.size = Vector3(0.012, 0.9, 0.012)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.75, 0.82, 0.92, 0.5)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak.material = material
	_rain.mesh = streak
	add_child(_rain)
	_build_ambience()


## A soft round dot, white with an alpha falloff, for pollen and fireflies.
static func _dot_texture() -> ImageTexture:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d: float = Vector2(float(x) - 15.5, float(y) - 15.5).length() / 15.5
			image.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 1.6))
	return ImageTexture.create_from_image(image)


## Two pairs of rounded wings around a dark body, white so the particle colour tints them.
static func _wing_texture() -> ImageTexture:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var p := Vector2(float(x) - 31.5, float(y) - 31.5)
			var upper: float = Vector2((absf(p.x) - 14.0) / 13.0, (p.y + 7.0) / 12.0).length()
			var lower: float = Vector2((absf(p.x) - 11.0) / 9.0, (p.y - 10.0) / 9.0).length()
			var color := Color(0, 0, 0, 0)
			if upper < 1.0 or lower < 1.0:
				var edge: float = 1.0 - minf(upper, lower)
				color = Color(1, 1, 1, 1).lerp(Color(0.25, 0.2, 0.18, 1), 0.0 if edge > 0.18 else 0.7)
			if absf(p.x) < 2.0 and absf(p.y) < 16.0:
				color = Color(0.15, 0.12, 0.1, 1)
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


static func _glow_material(texture: Texture2D, color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	material.albedo_color = color
	return material


func _ambient_emitter(amount: int, lifetime: float, extents: Vector3) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.preprocess = lifetime
	particles.local_coords = false
	particles.emitting = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = extents
	particles.gravity = Vector3.ZERO
	add_child(particles)
	return particles


func _build_ambience() -> void:
	var dot := _dot_texture()
	# Pollen and seeds drifting in the sunlight: tiny, warm, slowly rising and falling.
	_pollen = _ambient_emitter(160, 9.0, Vector3(28.0, 2.5, 22.0))
	var pollen_quad := QuadMesh.new()
	pollen_quad.size = Vector2(0.09, 0.09)
	pollen_quad.material = _glow_material(dot, Color(1.0, 0.95, 0.75, 0.75))
	_pollen.mesh = pollen_quad
	_pollen.direction = Vector3(1.0, 0.15, 0.4)
	_pollen.spread = 60.0
	_pollen.initial_velocity_min = 0.15
	_pollen.initial_velocity_max = 0.5
	_pollen.color_ramp = _fade_ramp(Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.9))
	# Butterflies over the meadows: flat wings seen from above, beating, in a handful of colours.
	_butterflies = _ambient_emitter(16, 7.0, Vector3(24.0, 0.6, 18.0))
	var wing_quad := PlaneMesh.new()
	wing_quad.size = Vector2(0.34, 0.34)
	var wing_material := ShaderMaterial.new()
	var wing_shader := Shader.new()
	wing_shader.code = BUTTERFLY_SHADER
	wing_material.shader = wing_shader
	wing_material.set_shader_parameter("wings", _wing_texture())
	wing_quad.material = wing_material
	_butterflies.mesh = wing_quad
	_butterflies.particle_flag_rotate_y = true
	_butterflies.angle_min = -180.0
	_butterflies.angle_max = 180.0
	_butterflies.direction = Vector3(1.0, 0.1, 0.0)
	_butterflies.spread = 180.0
	_butterflies.initial_velocity_min = 0.6
	_butterflies.initial_velocity_max = 1.4
	_butterflies.tangential_accel_min = -1.2
	_butterflies.tangential_accel_max = 1.2
	var palette := Gradient.new()
	palette.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	palette.colors = PackedColorArray([Color(1.0, 0.95, 0.85), Color(1.0, 0.8, 0.3), Color(0.55, 0.75, 1.0), Color(1.0, 0.55, 0.35), Color(0.95, 0.95, 0.6)])
	_butterflies.color_initial_ramp = palette
	# Leaves drifting down in the forest, turning as they fall.
	_leaves = _ambient_emitter(50, 7.0, Vector3(26.0, 1.0, 20.0))
	var leaf := QuadMesh.new()
	leaf.size = Vector2(0.16, 0.11)
	var leaf_material := StandardMaterial3D.new()
	leaf_material.albedo_texture = dot
	leaf_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	leaf_material.alpha_scissor_threshold = 0.3
	leaf_material.vertex_color_use_as_albedo = true
	leaf_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaf.material = leaf_material
	_leaves.mesh = leaf
	_leaves.direction = Vector3(0.3, -1.0, 0.2)
	_leaves.spread = 25.0
	_leaves.initial_velocity_min = 0.5
	_leaves.initial_velocity_max = 0.9
	_leaves.angular_velocity_min = -160.0
	_leaves.angular_velocity_max = 160.0
	_leaves.angle_min = -180.0
	_leaves.angle_max = 180.0
	var autumn := Gradient.new()
	autumn.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	autumn.colors = PackedColorArray([Color(0.45, 0.6, 0.2), Color(0.75, 0.62, 0.22), Color(0.6, 0.38, 0.18)])
	_leaves.color_initial_ramp = autumn
	# Fireflies at night: green-gold sparks that pulse, bright enough to catch the glow.
	_fireflies = _ambient_emitter(70, 6.0, Vector3(24.0, 1.4, 18.0))
	var spark := QuadMesh.new()
	spark.size = Vector2(0.16, 0.16)
	spark.material = _glow_material(dot, Color(1.0, 1.0, 1.0, 1.0))
	_fireflies.mesh = spark
	_fireflies.direction = Vector3(0.0, 0.3, 1.0)
	_fireflies.spread = 180.0
	_fireflies.initial_velocity_min = 0.2
	_fireflies.initial_velocity_max = 0.6
	var blink := Gradient.new()
	blink.offsets = PackedFloat32Array([0.0, 0.15, 0.3, 0.45, 0.6, 0.75, 1.0])
	blink.colors = PackedColorArray([Color(1.6, 1.8, 0.6, 0.0), Color(1.6, 1.8, 0.6, 1.0), Color(1.6, 1.8, 0.6, 0.15), Color(1.6, 1.8, 0.6, 1.0), Color(1.6, 1.8, 0.6, 0.2), Color(1.6, 1.8, 0.6, 0.9), Color(1.6, 1.8, 0.6, 0.0)])
	_fireflies.color_ramp = blink


static func _fade_ramp(edge: Color, middle: Color) -> Gradient:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	ramp.colors = PackedColorArray([edge, middle, middle, edge])
	return ramp


## The life around the player: `ground` is where they stand, `daylight` 0..1, `storm` 0..1, `biome` where they are.
func update_ambience(ground: Vector3, daylight: float, storm: float, biome: String) -> void:
	var calm: bool = storm < 0.3
	var wild: bool = biome != "beach" and biome != "mountain"
	_pollen.emitting = calm and daylight > 0.35
	_pollen.global_position = ground + Vector3(0, 2.0, 0)
	_butterflies.emitting = calm and daylight > 0.45 and (biome == "plains" or biome == "forest")
	_butterflies.global_position = ground + Vector3(0, 1.0, 0)
	_leaves.emitting = biome == "forest" or biome == "swamp"
	_leaves.global_position = ground + Vector3(0, 6.0, 0)
	_fireflies.emitting = calm and daylight < 0.25 and wild
	_fireflies.global_position = ground + Vector3(0, 1.0, 0)


## Rain around `center` while `intensity` > 0.
func update_rain(center: Vector3, intensity: float) -> void:
	_rain_amount = intensity
	_rain.emitting = intensity > 0.05
	_rain.global_position = center + Vector3(0, 18.0, 0)


## A puff of particles: `color` fades out, `speed` is the initial speed, `size` the particle size in meters.
func burst(position: Vector3, color: Color, count: int = 14, speed: float = 3.0, lifetime: float = 0.6, size: float = 0.14, gravity: float = 7.0, up: float = 0.6) -> void:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.amount = count
	particles.lifetime = lifetime
	particles.explosiveness = 0.95
	particles.direction = Vector3(0, up, 0)
	particles.spread = 80.0
	particles.initial_velocity_min = speed * 0.5
	particles.initial_velocity_max = speed
	particles.gravity = Vector3(0, -gravity, 0)
	particles.scale_amount_min = 0.7
	particles.scale_amount_max = 1.3
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = color.get_luminance() > 0.7
	material.emission = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if color.get_luminance() > 0.7 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mesh.material = material
	particles.mesh = mesh
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	particles.color_ramp = fade
	add_child(particles)
	particles.global_position = position
	particles.emitting = true
	get_tree().create_timer(lifetime + 0.5).timeout.connect(particles.queue_free)


func hit_zombie(position: Vector3) -> void:
	burst(position, Color(0.45, 0.62, 0.2), 12, 3.2, 0.55, 0.09)


func zombie_died(position: Vector3) -> void:
	burst(position, Color(0.4, 0.55, 0.2), 28, 4.5, 0.9, 0.12)
	burst(position, Color(0.35, 0.33, 0.3), 12, 2.0, 1.2, 0.3, 1.0, 0.2)


func hit_player(position: Vector3) -> void:
	burst(position, Color(0.78, 0.1, 0.1), 14, 3.4, 0.5, 0.08)


func muzzle_flash(position: Vector3) -> void:
	burst(position, Color(1.0, 0.85, 0.35), 8, 5.0, 0.12, 0.1, 0.0, 0.0)


func gathered(position: Vector3, color: Color) -> void:
	burst(position, color, 14, 3.0, 0.7, 0.07)


func level_up(position: Vector3) -> void:
	burst(position, Color(1.0, 0.85, 0.3), 36, 4.0, 1.1, 0.07, -1.5, 1.0)


func loot(position: Vector3) -> void:
	burst(position, Color(1.0, 0.9, 0.5), 16, 2.5, 0.8, 0.05, -0.5, 1.0)


## Dust kicked up by a runner; call every frame with the measured speed.
func footsteps(position: Vector3, speed: float, delta: float) -> void:
	if speed < 4.0:
		_dust_timer = 0.0
		return
	_dust_timer -= delta
	if _dust_timer <= 0.0:
		_dust_timer = 0.16
		burst(position + Vector3(0, 0.1, 0), Color(0.55, 0.5, 0.4, 0.5), 3, 0.9, 0.4, 0.07, -0.3, 0.3)
