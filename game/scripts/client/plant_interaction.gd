extends RefCounted
## Grass and bushes bend away from the player and plants shake when hit or harvested. Two global shader vec4s
## (x, z, radius, strength) read by grass_field.gd / foliage.gd through plant_interaction.gdshaderinc.
## Unity: vertex-shader "interactive grass" with a player-position uniform. Unreal: Niagara/material
## "grass interaction" via a Material Parameter Collection. Purely cosmetic; never touches simulation.

const BEND_RADIUS := [0.0, 1.1, 1.5, 1.9] # Low, Medium, High, Ultra: Low keeps grass untouched.
const SHAKE_RADIUS := [0.0, 2.2, 2.8, 3.4]
const SHAKE_SECONDS := 1.1
const MAX_BEND := 0.5
const MAX_CRUSHERS := 8
const CRUSH_RANGE := 45.0 # Beyond the grass fade there is nothing to flatten.
# Footprint radius (m) and strength per kind of object resting in the grass.
const FOOTPRINTS := {
	"campfire": Vector2(1.05, 1.0), "shelter": Vector2(1.9, 1.0), "barricade": Vector2(1.2, 1.0),
	"bag": Vector2(0.6, 1.0), "snare": Vector2(0.5, 0.9), "decoy": Vector2(0.5, 0.9),
	"player": Vector2(0.5, 0.75), "zombie": Vector2(0.5, 0.75),
}

var _shake_at := Vector2.ZERO
var _shake_age := 99.0
var _shake_amp := 0.0
var _smoothed_speed := 0.0
var _last := Vector3.INF


static func bend_radius(level: int) -> float:
	return BEND_RADIUS[clampi(level, 0, BEND_RADIUS.size() - 1)]


static func shake_radius(level: int) -> float:
	return SHAKE_RADIUS[clampi(level, 0, SHAKE_RADIUS.size() - 1)]


## Push strength in metres at the blade tip: standing presses a little, running presses fully.
static func bend_strength(speed: float) -> float:
	if not is_finite(speed):
		return 0.0
	return clampf(0.14 + speed * 0.09, 0.0, MAX_BEND)


## Shake amplitude (metres of sway) of age `age` seconds after the hit: damped oscillation envelope.
static func shake_envelope(age: float, amp: float) -> float:
	if not is_finite(age) or not is_finite(amp) or age < 0.0 or age >= SHAKE_SECONDS or amp <= 0.0:
		return 0.0
	var t := age / SHAKE_SECONDS
	return amp * (1.0 - t) * exp(-2.0 * t)


## Harvesting shakes more than a glancing hit.
static func shake_amplitude_for(event_type: String) -> float:
	match event_type:
		"gathered":
			return 0.22
		"hit", "zombie_died":
			return 0.1
		"barricade_broken", "knockback":
			return 0.14
	return 0.0


func shake(at: Vector3, amp: float) -> void:
	if not is_finite(amp) or amp <= 0.0 or not at.is_finite():
		return
	_shake_at = Vector2(at.x, at.z)
	_shake_amp = amp
	_shake_age = 0.0


func update(delta: float, player: Vector3, level: int) -> Vector2:
	# A broken position or delta must never reach global shader uniforms.
	var safe_delta: float = delta if is_finite(delta) and delta > 0.0 else 0.0
	var at: Vector3 = player if player.is_finite() else (_last if _last.is_finite() else Vector3.ZERO)
	var radius: float = bend_radius(level)
	if safe_delta > 0.0 and _last.is_finite():
		var speed: float = Vector2(at.x - _last.x, at.z - _last.z).length() / safe_delta
		_smoothed_speed = lerpf(_smoothed_speed, minf(speed, 8.0), 1.0 - exp(-8.0 * safe_delta))
	_last = at
	_shake_age += safe_delta
	var bend := Vector4(at.x, at.z, radius, bend_strength(_smoothed_speed) if radius > 0.0 else 0.0)
	var shake_strength := shake_envelope(_shake_age, _shake_amp) if shake_radius(level) > 0.0 else 0.0
	var shake_v := Vector4(_shake_at.x, _shake_at.y, shake_radius(level), shake_strength)
	RenderingServer.global_shader_parameter_set(&"aa_plant_bend", bend)
	RenderingServer.global_shader_parameter_set(&"aa_plant_shake", shake_v)
	return Vector2(bend.w, shake_v.w)


## Nearest object footprints to `center` as Vector4(x, z, radius, strength), at most MAX_CRUSHERS.
## `sources` is an Array of [kind, Dictionary-with-x-and-z].
static func pick_crushers(center: Vector2, sources: Array) -> Array:
	if not center.is_finite():
		return []
	# Shader has only eight slots. Keep an ordered, bounded top-K while walking
	# sources instead of allocating and sorting every nearby actor each frame.
	var nearest: Array = []
	var max_distance_sq: float = CRUSH_RANGE * CRUSH_RANGE
	for source in sources:
		if not (source is Array) or source.size() < 2 or not (source[1] is Dictionary):
			continue
		var kind: String = str(source[0])
		var entity: Dictionary = source[1]
		if not FOOTPRINTS.has(kind) or not entity.has("x") or not entity.has("z"):
			continue
		var at := Vector2(float(entity["x"]), float(entity["z"]))
		if not at.is_finite():
			continue
		var distance_sq: float = center.distance_squared_to(at)
		if distance_sq > max_distance_sq:
			continue
		var insert_at: int = nearest.size()
		# Strict comparison preserves source order for equally distant actors.
		while insert_at > 0 and distance_sq < float(nearest[insert_at - 1]["d"]):
			insert_at -= 1
		if insert_at >= MAX_CRUSHERS:
			continue
		var footprint: Vector2 = FOOTPRINTS[kind]
		nearest.insert(insert_at, {"d": distance_sq,
			"v": Vector4(at.x, at.y, footprint.x, footprint.y)})
		if nearest.size() > MAX_CRUSHERS:
			nearest.pop_back()
	var result: Array = []
	for entry in nearest:
		result.append(entry["v"])
	return result


## Uploads the footprints to the grass shader globals.
func set_crushers(crushers: Array) -> void:
	var count: int = mini(crushers.size(), MAX_CRUSHERS)
	for i in MAX_CRUSHERS:
		var value: Vector4 = crushers[i] if i < count else Vector4.ZERO
		RenderingServer.global_shader_parameter_set(StringName("aa_plant_crush_%d" % i), value)
	RenderingServer.global_shader_parameter_set(&"aa_plant_crush_count", float(count))
