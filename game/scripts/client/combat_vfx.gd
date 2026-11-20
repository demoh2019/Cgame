extends Node3D
## Combat and interaction VFX layer (Niagara / VFX Graph style emitters, all pooled and capped by quality tier):
## ranged tracers, shell casings, muzzle light, melee swing trails, material-aware impacts, directional blood spray,
## water splash/ripples, landing dust, explosion shockwave with light, pickup sparkle.
## Static helpers hold the budgets/maths so they can be unit tested without a scene.

const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const WATER_LEVEL := 0.0 # Mirrors Defs.WATER_LEVEL.

# ---------------------------------------------------------------- static helpers

## Pool/cap sizes per feature and quality tier 0..3 (0 = nothing).
static func budget(kind: String, tier: int) -> int:
	var table := {
		"tracer": [0, 4, 8, 16],
		"casing": [0, 4, 10, 20],
		"light": [0, 1, 2, 3],
		"trail": [0, 2, 4, 8],
		"burst": [0, 6, 12, 24],
		"ring": [0, 4, 8, 12],
		"sparkle": [0, 1, 2, 4],
	}
	if not table.has(kind):
		return 0
	return int(table[kind][clampi(tier, 0, 3)])


## Horizontal unit direction from an event's `dir` value (Vector2/Vector3/Array/Dictionary); ZERO when unusable.
static func dir_xz(value) -> Vector2:
	var v := Vector2.ZERO
	if value is Vector2:
		v = value
	elif value is Vector3:
		v = Vector2(value.x, value.z)
	elif value is Array and value.size() >= 2:
		v = Vector2(float(value[0]), float(value[value.size() - 1]))
	elif value is Dictionary:
		v = Vector2(float(value.get("x", 0.0)), float(value.get("z", value.get("y", 0.0))))
	if not v.is_finite() or v.length() < 0.001:
		return Vector2.ZERO
	return v.normalized()


## Surface material for impacts from the biome (and gathered item id when known).
static func material_for(biome: String, item: String = "") -> String:
	if item.begins_with("wood"):
		return "wood"
	if item.begins_with("ore") or item.begins_with("metal") or item.begins_with("scrap"):
		return "metal"
	if item.begins_with("stone"):
		return "stone"
	match biome:
		"beach":
			return "sand"
		"mountain":
			return "stone"
		"swamp":
			return "mud"
		"water":
			return "water"
	return "dirt"


## Particle recipe per material: metal = bright sparks, wood = chips, dirt/sand/mud = dust clods.
static func impact_profile(material: String) -> Dictionary:
	match material:
		"metal":
			return {"color": Color(1.0, 0.8, 0.35), "count": 12, "speed": 6.0, "gravity": 9.0, "size": 0.04, "life": 0.35, "glow": true}
		"wood":
			return {"color": Color(0.58, 0.4, 0.22), "count": 10, "speed": 3.8, "gravity": 9.0, "size": 0.07, "life": 0.6, "glow": false}
		"stone":
			return {"color": Color(0.62, 0.62, 0.64), "count": 10, "speed": 4.2, "gravity": 9.0, "size": 0.06, "life": 0.5, "glow": false}
		"sand":
			return {"color": Color(0.86, 0.76, 0.55), "count": 12, "speed": 2.6, "gravity": 4.0, "size": 0.08, "life": 0.6, "glow": false}
		"mud":
			return {"color": Color(0.3, 0.25, 0.16), "count": 9, "speed": 2.8, "gravity": 8.0, "size": 0.09, "life": 0.55, "glow": false}
		"water":
			return {"color": Color(0.75, 0.88, 1.0), "count": 14, "speed": 3.4, "gravity": 8.0, "size": 0.06, "life": 0.55, "glow": false}
	return {"color": Color(0.5, 0.42, 0.3), "count": 10, "speed": 3.0, "gravity": 7.0, "size": 0.08, "life": 0.55, "glow": false}


## Blood/ichor sprays away from the attacker, slightly upward. Returns a unit vector.
static func spray_direction(from: Vector3, to: Vector3) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if flat.length() < 0.001:
		return Vector3.UP
	return (flat.normalized() + Vector3(0, 0.35, 0)).normalized()


## Tracer segment: starts a little ahead of the muzzle, ends `reach` meters on (or at `target`).
static func tracer_span(origin: Vector3, dir: Vector2, reach: float, target: Vector3 = Vector3.INF) -> PackedVector3Array:
	var d := Vector3(dir.x, 0.0, dir.y)
	var start := origin + d * 0.6
	var stop := origin + d * reach
	if target.is_finite():
		stop = target
	return PackedVector3Array([start, stop])


## Casing ejection velocity: out to the shooter's right and up, with deterministic jitter from `seed_value`.
static func casing_velocity(dir: Vector2, seed_value: int) -> Vector3:
	var right := Vector3(-dir.y, 0.0, dir.x) * -1.0
	var j := float((seed_value * 7919) % 100) / 100.0
	return right * (1.6 + j * 1.2) + Vector3(0, 2.2 + j, 0) - Vector3(dir.x, 0.0, dir.y) * 0.4


## Points of a swing arc in front of the attacker (sweeping from -half_angle to +half_angle).
static func swing_arc(origin: Vector3, dir: Vector2, reach: float, half_angle: float, steps: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var base := dir.angle()
	for i in steps + 1:
		var a := base + lerpf(-half_angle, half_angle, float(i) / float(maxi(steps, 1)))
		out.append(origin + Vector3(cos(a), 0.0, sin(a)) * reach)
	return out


## 0..1 landing dust strength for a fall speed in m/s (nothing below 3 m/s).
static func landing_strength(fall_speed: float) -> float:
	return clampf((fall_speed - 3.0) / 9.0, 0.0, 1.0)


static func in_water(ground_y: float) -> bool:
	return ground_y < WATER_LEVEL - 0.05


## Muzzle/explosion light energy over its life t in 0..1: instant peak then fast falloff.
static func flash_energy(peak: float, t: float) -> float:
	return peak * pow(clampf(1.0 - t, 0.0, 1.0), 2.0)


## Pickup sparkle colour per rarity-ish item hint.
static func sparkle_color(item: String) -> Color:
	if item.begins_with("gold") or item.begins_with("coin"):
		return Color(1.0, 0.85, 0.3)
	if item.begins_with("med") or item.begins_with("bandage"):
		return Color(0.5, 1.0, 0.6)
	return Color(1.0, 0.95, 0.7)


# ---------------------------------------------------------------- runtime

var _tracers: Array = [] # {node, age, life}
var _casings: Array = [] # {node, vel, age, ground}
var _lights: Array = [] # {node, age, life, peak}
var _trails: Array = []
var _bursts := 0
var _rings := 0
var _sparkles := 0
var _air_time := 0.0
var _fall_speed := 0.0
var _last_y := 0.0
var _splash_timer := 0.0
var _dust_timer := 0.0
var _unshaded: StandardMaterial3D


func _tier() -> int:
	return GraphicsQuality.level()


func _glow(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Bullet/arrow streak from the shooter along `dir` (Vector2) to `reach` meters or `target`.
func tracer(origin: Vector3, dir: Vector2, reach: float = 28.0, color: Color = Color(1.0, 0.85, 0.5), target: Vector3 = Vector3.INF) -> void:
	if dir == Vector2.ZERO or _tracers.size() >= budget("tracer", _tier()):
		return
	var span := tracer_span(origin, dir, reach, target)
	var length: float = span[0].distance_to(span[1])
	if length < 0.5:
		return
	var box := BoxMesh.new()
	box.size = Vector3(0.025, 0.025, length)
	box.material = _glow(color)
	var node := MeshInstance3D.new()
	node.mesh = box
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_position = (span[0] + span[1]) * 0.5
	node.look_at(span[1], Vector3.UP)
	_tracers.append({"node": node, "age": 0.0, "life": 0.12, "mat": box.material})


## Brass casing ejected sideways with simple ballistic motion and one bounce.
func shell_casing(origin: Vector3, dir: Vector2, ground_y: float) -> void:
	if dir == Vector2.ZERO or _casings.size() >= budget("casing", _tier()):
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.008
	mesh.bottom_radius = 0.008
	mesh.height = 0.04
	mesh.radial_segments = 6
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.65, 0.25)
	m.metallic = 0.9
	m.roughness = 0.35
	mesh.material = m
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_position = origin
	_casings.append({"node": node, "vel": casing_velocity(dir, Time.get_ticks_msec()), "age": 0.0, "ground": ground_y + 0.02, "bounced": false})


## Short-lived warm light at the muzzle / blast site; budgeted per tier.
func flash_light(position: Vector3, color: Color = Color(1.0, 0.75, 0.4), peak: float = 4.0, life: float = 0.09, range_m: float = 7.0) -> void:
	if _lights.size() >= budget("light", _tier()):
		return
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = range_m
	light.shadow_enabled = false
	light.light_energy = peak
	add_child(light)
	light.global_position = position
	_lights.append({"node": light, "age": 0.0, "life": life, "peak": peak})


## Fading arc ribbon for a melee swing in front of `origin`.
func swing_trail(origin: Vector3, dir: Vector2, reach: float = 1.9) -> void:
	if dir == Vector2.ZERO or _trails.size() >= budget("trail", _tier()):
		return
	var arc := swing_arc(origin, dir, reach, 0.9, 8)
	var mesh := ImmediateMesh.new()
	var material := _glow(Color(0.9, 0.95, 1.0, 0.55))
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, material)
	for p in arc:
		mesh.surface_add_vertex(p - origin + Vector3(0, 0.25, 0))
		mesh.surface_add_vertex(p - origin + Vector3(0, -0.15, 0))
	mesh.surface_end()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_position = origin
	_trails.append({"node": node, "age": 0.0, "life": 0.18, "mat": material})


## Directional particle spray (blood/ichor) along `direction`.
func spray(position: Vector3, direction: Vector3, color: Color, count: int = 14, speed: float = 4.0) -> void:
	_particles(position, direction, color, count, speed, 8.0, 0.06, 0.5, 35.0, false)


## Material-aware impact (metal sparks / wood chips / dirt dust...). `normal` is the surface bounce direction.
func impact(position: Vector3, material: String, normal: Vector3 = Vector3.UP) -> void:
	var p := impact_profile(material)
	_particles(position, normal, p["color"], int(p["count"]), float(p["speed"]), float(p["gravity"]), float(p["size"]), float(p["life"]), 50.0, bool(p["glow"]))


func _particles(position: Vector3, direction: Vector3, color: Color, count: int, speed: float, gravity: float, size: float, life: float, spread: float, glow: bool) -> void:
	var cap := budget("burst", _tier())
	if _bursts >= cap or cap == 0:
		return
	_bursts += 1
	var tier := _tier()
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = maxi(3, count * (tier + 1) / 4 + 2)
	p.lifetime = life
	p.explosiveness = 0.95
	p.direction = direction
	p.spread = spread
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	mesh.radial_segments = 5
	mesh.rings = 2
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = color
	mesh.material = m
	p.mesh = mesh
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	add_child(p)
	p.global_position = position
	p.emitting = true
	get_tree().create_timer(life + 0.4).timeout.connect(_free_burst.bind(p))


func _free_burst(p: Node) -> void:
	_bursts = maxi(0, _bursts - 1)
	if is_instance_valid(p):
		p.queue_free()


## Expanding ring (shockwave / ripple); budgeted. `ripple` rings are thin and flat.
func shock_ring(position: Vector3, color: Color, radius: float, seconds: float) -> void:
	if _rings >= budget("ring", _tier()):
		return
	_rings += 1
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	torus.rings = 24
	torus.ring_segments = 4
	var m := _glow(color)
	torus.material = m
	var node := MeshInstance3D.new()
	node.mesh = torus
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_position = position + Vector3(0, 0.08, 0)
	node.scale = Vector3(0.2, 0.03, 0.2)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(node, "scale", Vector3(radius, 0.03, radius), seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, seconds)
	tw.chain().tween_callback(_free_ring.bind(node))


func _free_ring(node: Node) -> void:
	_rings = maxi(0, _rings - 1)
	if is_instance_valid(node):
		node.queue_free()


## Blast: shockwave ring, ground dust, and a bright light.
func explosion(position: Vector3, radius: float, color: Color = Color(1.0, 0.85, 0.55)) -> void:
	shock_ring(position, Color(color.r, color.g, color.b, 0.7), radius, 0.5)
	impact(position + Vector3(0, 0.2, 0), "dirt", Vector3.UP)
	flash_light(position + Vector3(0, 1.0, 0), color, 8.0, 0.25, radius * 1.4)


## Sparkles rising from a pickup/crate.
func pickup_sparkle(position: Vector3, color: Color = Color(1.0, 0.95, 0.7)) -> void:
	var cap := budget("sparkle", _tier())
	if _sparkles >= cap or cap == 0:
		return
	_sparkles += 1
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 10
	p.lifetime = 0.9
	p.explosiveness = 0.3
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, 0.6, 0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	var m := _glow(color)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	quad.material = m
	p.mesh = quad
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	add_child(p)
	p.global_position = position
	p.emitting = true
	get_tree().create_timer(1.4).timeout.connect(_free_sparkle.bind(p))


func _free_sparkle(p: Node) -> void:
	_sparkles = maxi(0, _sparkles - 1)
	if is_instance_valid(p):
		p.queue_free()


## Per-frame: water splash/ripples when wading, and a landing dust puff after a fall. `ground_y` is terrain height.
## Kick-up dust colour for running feet; alpha 0 = no dust (wet or soft ground).
static func run_dust_color(biome: String) -> Color:
	match biome:
		"plains":
			return Color(0.66, 0.58, 0.44, 0.42)
		"beach":
			return Color(0.82, 0.76, 0.6, 0.38)
		"mountain":
			return Color(0.6, 0.6, 0.6, 0.35)
	return Color(0, 0, 0, 0)


func update_player(position: Vector3, ground_y: float, speed: float, delta: float, biome: String = "") -> void:
	if _tier() == 0:
		return
	var feet_y := position.y
	var airborne := feet_y - ground_y > 0.35
	if airborne:
		_air_time += delta
		_fall_speed = maxf(_fall_speed, (_last_y - feet_y) / maxf(delta, 0.0001))
	else:
		if _air_time > 0.12:
			var strength := landing_strength(_fall_speed)
			if strength > 0.0:
				_particles(Vector3(position.x, ground_y + 0.1, position.z), Vector3.UP, Color(0.6, 0.55, 0.45, 0.6), int(6 + strength * 10), 1.5 + strength * 2.0, 0.5, 0.1, 0.55, 80.0, false)
		_air_time = 0.0
		_fall_speed = 0.0
	_last_y = feet_y
	if in_water(ground_y) and speed > 0.5:
		_splash_timer -= delta
		if _splash_timer <= 0.0:
			_splash_timer = clampf(0.5 - speed * 0.05, 0.15, 0.5)
			var surface := Vector3(position.x, WATER_LEVEL, position.z)
			shock_ring(surface, Color(0.8, 0.92, 1.0, 0.45), 0.9 + speed * 0.12, 0.7)
			impact(surface + Vector3(0, 0.05, 0), "water", Vector3.UP)
	else:
		_splash_timer = 0.0
		# RDR2-style kicked-up dust while running on dry ground.
		var dust: Color = run_dust_color(biome)
		if dust.a > 0.0 and speed > 4.0 and not airborne:
			_dust_timer -= delta
			if _dust_timer <= 0.0:
				_dust_timer = clampf(0.36 - speed * 0.02, 0.18, 0.36)
				_particles(Vector3(position.x, ground_y + 0.08, position.z), Vector3.UP, dust, 4, 0.9, 0.4, 0.12, 0.7, 70.0, false)


func _process(delta: float) -> void:
	for i in range(_tracers.size() - 1, -1, -1):
		var t: Dictionary = _tracers[i]
		t["age"] += delta
		var k: float = t["age"] / t["life"]
		if k >= 1.0:
			t["node"].queue_free()
			_tracers.remove_at(i)
		else:
			(t["mat"] as StandardMaterial3D).albedo_color.a = 1.0 - k
	for i in range(_trails.size() - 1, -1, -1):
		var t: Dictionary = _trails[i]
		t["age"] += delta
		var k: float = t["age"] / t["life"]
		if k >= 1.0:
			t["node"].queue_free()
			_trails.remove_at(i)
		else:
			(t["mat"] as StandardMaterial3D).albedo_color.a = 0.55 * (1.0 - k)
	for i in range(_lights.size() - 1, -1, -1):
		var t: Dictionary = _lights[i]
		t["age"] += delta
		var k: float = t["age"] / t["life"]
		if k >= 1.0:
			t["node"].queue_free()
			_lights.remove_at(i)
		else:
			t["node"].light_energy = flash_energy(t["peak"], k)
	for i in range(_casings.size() - 1, -1, -1):
		var c: Dictionary = _casings[i]
		c["age"] += delta
		var node: MeshInstance3D = c["node"]
		var vel: Vector3 = c["vel"]
		vel.y -= 9.8 * delta
		node.global_position += vel * delta
		node.rotate_x(12.0 * delta)
		if node.global_position.y <= c["ground"] and vel.y < 0.0:
			if not c["bounced"]:
				c["bounced"] = true
				vel = Vector3(vel.x * 0.4, -vel.y * 0.35, vel.z * 0.4)
			else:
				vel = Vector3.ZERO
			node.global_position.y = c["ground"]
		c["vel"] = vel
		if c["age"] > 2.5:
			node.queue_free()
			_casings.remove_at(i)


## Server event dispatcher: `here` is the local player's position, `at` the event position (feet + 1 m), `biome` under `at`.
func handle_event(event: Dictionary, here: Vector3, at: Vector3, biome: String) -> void:
	var ground := Vector3(at.x, at.y - 1.0, at.z)
	match str(event.get("type", "")):
		"attack":
			var dir: Vector2 = dir_xz(event.get("dir"))
			var origin := Vector3(at.x, at.y + 0.2, at.z)
			if bool(event.get("ranged", false)):
				tracer(origin, dir)
				shell_casing(origin, dir, ground.y)
				flash_light(origin + Vector3(dir.x, 0.0, dir.y) * 0.6)
			else:
				swing_trail(origin, dir)
		"hit":
			var from: Vector3 = here if event.has("x") else at
			var dir3: Vector3 = spray_direction(from, at)
			if str(event.get("kind", "")) == "zombie":
				spray(at, dir3, Color(0.3, 0.42, 0.12), 12, 4.5)
			else:
				spray(at, dir3, Color(0.6, 0.05, 0.05), 14, 4.5)
		"zombie_died":
			spray(at, Vector3.UP, Color(0.3, 0.4, 0.1), 16, 4.0)
		"barricade_broken":
			impact(at, "wood")
			explosion(ground, 3.0, Color(0.8, 0.6, 0.35))
		"flash_thrown":
			explosion(ground, 7.0, Color(1.0, 1.0, 0.9))
		"ember_thrown":
			flash_light(at, Color(1.0, 0.55, 0.2), 5.0, 0.35, 6.0)
		"gathered":
			impact(here - Vector3(0, 0.6, 0), material_for(biome, str(event.get("item", ""))))
		"crate":
			pickup_sparkle(here, sparkle_color(str(event.get("item", ""))))
