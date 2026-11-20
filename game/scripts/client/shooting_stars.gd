extends Node3D
## Occasional shooting stars on clear nights (Ghost of Tsushima / Firewatch skies).
## A single additive streak far above the camera, animated every frame (the sky
## shader refreshes on a slower cadence, so meteors live outside it).

const MIN_GAP := 18.0
const MAX_GAP := 55.0
const LIFE := 0.7

var camera: Camera3D
var _streak: MeshInstance3D
var _mat: StandardMaterial3D
var _wait := 8.0
var _age := LIFE
var _from := Vector3.ZERO
var _dir := Vector3.ZERO


static func allowed(level: int, daylight: float, storm: float) -> bool:
	return level >= 2 and daylight < 0.15 and storm < 0.25


## Brightness envelope over a meteor's life (0..1): quick flare, longer fade.
static func envelope(t: float) -> float:
	if t <= 0.0 or t >= 1.0:
		return 0.0
	return smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.45, 1.0, t))


func _ready() -> void:
	_streak = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(16.0, 0.35)
	_streak.mesh = quad
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.no_depth_test = true
	_mat.disable_fog = true
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 1))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 4
	_mat.albedo_texture = tex
	_mat.albedo_color = Color(0.85, 0.92, 1.0, 0.0)
	_streak.material_override = _mat
	_streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_streak.visible = false
	add_child(_streak)


func update_view(daylight: float, storm: float, level: int, delta: float) -> void:
	if camera == null:
		return
	if _age < LIFE:
		_age += delta
		var t := _age / LIFE
		var pos := _from + _dir * (t * 60.0)
		_streak.global_position = pos
		_mat.albedo_color.a = envelope(t) * 1.4
		if _age >= LIFE:
			_streak.visible = false
		return
	if not allowed(level, daylight, storm):
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = randf_range(MIN_GAP, MAX_GAP)
	_age = 0.0
	# Somewhere high in the sky in front of the camera, falling diagonally.
	var cam := camera.global_transform
	var ahead := -cam.basis.z
	ahead.y = 0.0
	ahead = ahead.normalized() if ahead.length() > 0.01 else Vector3.FORWARD
	var side := Vector3.UP.cross(ahead).normalized()
	_from = cam.origin + ahead * 220.0 + side * randf_range(-120.0, 120.0) + Vector3.UP * randf_range(140.0, 200.0)
	_dir = (side * (1.0 if randf() < 0.5 else -1.0) + Vector3.DOWN * 0.45).normalized()
	_streak.global_position = _from
	# Orient the quad's long axis (X) along travel, facing the camera.
	var to_cam := (cam.origin - _from).normalized()
	var x := _dir
	var z := (to_cam - x * to_cam.dot(x)).normalized()
	_streak.global_basis = Basis(x, z.cross(x), z)
	_streak.visible = true
