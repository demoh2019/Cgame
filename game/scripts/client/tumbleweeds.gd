extends Node3D
## Wind-blown tumbleweeds on open plains (RDR2 / western ambience): a few brush
## balls roll downwind, hop over bumps and respawn upwind out of view. Purely
## visual and client-side; off on Performance, in calm air and off the plains.

const WEED_SHADER := preload("res://assets/shaders/tumbleweed.gdshader")
const MAX_WEEDS := 3
const SPAWN_DISTANCE := 32.0
const DESPAWN_DISTANCE := 45.0
const MIN_WIND := 0.25

var _weeds: Array[MeshInstance3D] = []
var _vel: Array[Vector3] = []
var _hop: Array[float] = []


static func weed_count(level: int, biome: String, wind: Vector2) -> int:
	if level < 1 or biome != "plains" or wind.length() < MIN_WIND:
		return 0
	return 1 if level == 1 else MAX_WEEDS


## Upwind spawn point around the player (weeds then roll past them).
static func spawn_point(player: Vector3, wind: Vector2, lateral: float) -> Vector3:
	var w := wind.normalized()
	var side := Vector2(-w.y, w.x)
	var p := Vector2(player.x, player.z) - w * SPAWN_DISTANCE + side * lateral
	return Vector3(p.x, player.y, p.y)


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.45
	sphere.height = 0.85
	sphere.radial_segments = 12
	sphere.rings = 6
	var mat := ShaderMaterial.new()
	mat.shader = WEED_SHADER
	for i in MAX_WEEDS:
		var weed := MeshInstance3D.new()
		weed.mesh = sphere
		weed.material_override = mat
		weed.visible = false
		add_child(weed)
		_weeds.append(weed)
		_vel.append(Vector3.ZERO)
		_hop.append(0.0)


func update_view(world, player: Vector3, biome: String, wind: Vector2, level: int, delta: float, underground: bool) -> void:
	var want: int = 0 if underground or world == null else weed_count(level, biome, wind)
	var dt := minf(delta, 0.1)
	var w3 := Vector3(wind.x, 0.0, wind.y)
	for i in MAX_WEEDS:
		var weed := _weeds[i]
		if i >= want:
			weed.visible = false
			continue
		var flat_dist := Vector2(weed.position.x - player.x, weed.position.z - player.z).length()
		if not weed.visible or flat_dist > DESPAWN_DISTANCE:
			weed.position = spawn_point(player, wind, randf_range(-14.0, 14.0))
			_vel[i] = w3.normalized() * randf_range(2.0, 3.5)
			_hop[i] = randf() * TAU
			weed.visible = true
		# Accelerate towards wind speed with gusty variation.
		var target: Vector3 = w3.normalized() * clampf(wind.length() * 4.0, 2.0, 6.5)
		_vel[i] = _vel[i].lerp(target, 1.0 - exp(-dt * 0.8))
		weed.position += _vel[i] * dt
		var ground: float = world.height_at(weed.position.x, weed.position.z)
		_hop[i] += dt * (2.5 + _vel[i].length() * 0.4)
		weed.position.y = ground + 0.42 + absf(sin(_hop[i])) * 0.35
		# Roll: rotate about the axis perpendicular to travel, by distance / radius.
		var speed := _vel[i].length()
		if speed > 0.01:
			var axis := Vector3.UP.cross(_vel[i] / speed).normalized()
			weed.rotate(axis, speed * dt / 0.42)
