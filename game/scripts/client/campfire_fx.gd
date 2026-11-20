extends Node3D
## AAA-style campfire: animated HDR flame (bloom-driven), flickering warm light with
## soft shadows on high-end, rising ember particles and screen-space heat haze.
## Unreal/Unity fires combine exactly these four layers. Purely visual, client-only.

const FLAME_SHADER := preload("res://assets/shaders/campfire_flame.gdshader")
const HAZE_SHADER := preload("res://assets/shaders/heat_haze.gdshader")
const BASE_ENERGY := 1.6

var light: OmniLight3D
var _t := 0.0
var _seed := 0.0


## Layered-sine flicker in ~[0.75, 1.15]: cheap, smooth, never strobes.
static func flicker(time: float, seed: float) -> float:
	var f := sin(time * 7.3 + seed) * 0.07 + sin(time * 13.1 + seed * 2.0) * 0.05 \
		+ sin(time * 23.7 + seed * 3.0) * 0.03
	return clampf(0.95 + f, 0.75, 1.15)


## Heavy layers (haze needs the screen texture, embers are particles) only on High/Ultra Forward+.
static func rich_effects(level: int, rendering_method: String) -> bool:
	return rendering_method == "forward_plus" and level >= 2


func _init() -> void:
	_seed = randf() * 10.0


func build(level: int, rendering_method: String) -> void:
	var rich := rich_effects(level, rendering_method)
	# Two crossed flame quads read as a volume from every angle.
	for i in 2:
		var q := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.9, 1.25)
		q.mesh = mesh
		q.position.y = 0.78
		q.rotation.y = PI * 0.5 * i
		var m := ShaderMaterial.new()
		m.shader = FLAME_SHADER
		m.set_shader_parameter("seed", _seed + i)
		q.material_override = m
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(q)
	light = OmniLight3D.new()
	light.position.y = 0.9
	light.light_color = Color(1.0, 0.52, 0.2)
	light.light_energy = BASE_ENERGY
	light.omni_range = 6.0
	light.omni_attenuation = 1.4
	light.shadow_enabled = rich
	light.shadow_blur = 2.0
	add_child(light)
	if not rich:
		return
	var embers := GPUParticles3D.new()
	embers.amount = 24
	embers.lifetime = 1.8
	embers.position.y = 0.5
	embers.visibility_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3, 4, 3))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 18.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3(0, 0.3, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.75, 0.3, 1.0))
	fade.set_color(1, Color(1.0, 0.2, 0.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	embers.process_material = pm
	var spark := QuadMesh.new()
	spark.size = Vector2(0.035, 0.035)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.vertex_color_use_as_albedo = true
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.45, 0.1)
	sm.emission_energy_multiplier = 4.0
	spark.material = sm
	embers.draw_pass_1 = spark
	add_child(embers)
	var haze := MeshInstance3D.new()
	var hq := QuadMesh.new()
	hq.size = Vector2(1.4, 2.2)
	haze.mesh = hq
	haze.position.y = 1.7
	var hm := ShaderMaterial.new()
	hm.shader = HAZE_SHADER
	haze.material_override = hm
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(haze)


func _process(delta: float) -> void:
	if light == null:
		return
	_t += delta
	var k := flicker(_t, _seed)
	light.light_energy = BASE_ENERGY * k
	# Flame tongues also shift the light origin slightly, making shadows dance.
	light.position = Vector3(sin(_t * 5.1 + _seed) * 0.04, 0.9 + (k - 0.95) * 0.3, cos(_t * 4.3 + _seed) * 0.04)
