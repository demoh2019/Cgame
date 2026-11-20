extends Node3D
## Floating combat numbers (Diablo / WoW / Lost Ark): each hit pops a number above
## the target that springs up, drifts sideways and fades. Heavy hits are bigger
## and gold, damage taken by you is red. Pooled Label3D nodes; no allocation per hit.

const POOL_SIZE := 24
const LIFE := 0.85
const HEAVY_HIT := 35.0

var _pool: Array[Label3D] = []
var _age: Array[float] = []
var _vel: Array[Vector3] = []
var _base_scale: Array[float] = []
var _next := 0


## Colour and size for a hit: (color, font scale).
static func style(damage: float, on_me: bool) -> Array:
	if on_me:
		return [Color(1.0, 0.32, 0.28), 1.0]
	if damage >= HEAVY_HIT:
		return [Color(1.0, 0.82, 0.25), 1.45]
	return [Color(1.0, 1.0, 1.0), 1.0]


## Pop-in then settle: scale multiplier over normalized age (0..1).
static func pop(t: float) -> float:
	if t < 0.12:
		return lerpf(0.4, 1.35, t / 0.12)
	return lerpf(1.35, 1.0, clampf((t - 0.12) / 0.2, 0.0, 1.0))


func _ready() -> void:
	for i in POOL_SIZE:
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.0011
		label.font_size = 40
		label.outline_size = 10
		label.outline_modulate = Color(0, 0, 0, 0.85)
		label.render_priority = 10
		label.visible = false
		add_child(label)
		_pool.append(label)
		_age.append(LIFE)
		_vel.append(Vector3.ZERO)
		_base_scale.append(1.0)
	set_process(true)


func on_event(event: Dictionary, at: Vector3, my_peer: int) -> void:
	if str(event.get("type", "")) != "hit":
		return
	var damage: float = float(event.get("damage", 0.0))
	if damage <= 0.0:
		return
	var on_me: bool = str(event.get("kind", "")) != "zombie" and int(event.get("id", -1)) == my_peer
	var s: Array = style(damage, on_me)
	var label := _pool[_next]
	_age[_next] = 0.0
	_vel[_next] = Vector3(randf_range(-0.6, 0.6), 2.6, randf_range(-0.6, 0.6))
	_base_scale[_next] = float(s[1])
	label.text = str(int(round(damage)))
	label.modulate = s[0]
	label.position = at + Vector3(randf_range(-0.25, 0.25), 2.1, randf_range(-0.25, 0.25))
	label.visible = true
	_next = (_next + 1) % POOL_SIZE


func _process(delta: float) -> void:
	for i in POOL_SIZE:
		if _age[i] >= LIFE:
			continue
		_age[i] += delta
		var label := _pool[i]
		if _age[i] >= LIFE:
			label.visible = false
			continue
		_vel[i].y -= 5.5 * delta # Springs up, then arcs over.
		label.position += _vel[i] * delta
		var t: float = _age[i] / LIFE
		var k: float = pop(t) * _base_scale[i]
		label.scale = Vector3(k, k, k)
		label.modulate.a = 1.0 - smoothstep(0.6, 1.0, t)
		label.outline_modulate.a = 0.85 * label.modulate.a
