extends Node
## Gameplay camera and post-processing feel: the Cinemachine (look-ahead, impulse, FOV, zoom) and URP/HDRP Volume /
## Unreal Post Process Volume (vignette, chromatic aberration, motion blur, desaturation) behaviours, driven by what
## happens to the local player. Pure maths lives in static helpers (tested); the node owns the overlay and the camera.

const SHADER := preload("res://assets/shaders/camera_post_fx.gdshader")
const BASE_FOV := 38.0
const LOW_HEALTH_START := 40.0
const MAX_LOOK_AHEAD := 2.6

var camera: Camera3D
var hud: CanvasLayer
var look := Vector3.ZERO ## Added to the camera target (look-ahead).
var zoom_mul := 1.0 ## Multiplies the camera distance (speed pull-out).
var photo_active := false

var _rect: ColorRect
var _mat: ShaderMaterial
var _hurt := 0.0
var _aberration := 0.0
var _blur := 0.0
var _letterbox := 0.0
var _frost := 0.0
var cold := 0.0 ## 0..1 set by the client from altitude/snow/night (see breath_vapor.gd).
var _clock := 0.0
var _stop_until_msec := 0
var _photo_yaw := 0.0
var _photo_pitch := 0.9
var _photo_dist := 20.0
var _photo_target := Vector3.ZERO
var _look_smooth := Vector3.ZERO
var _fov := BASE_FOV
var base_fov := BASE_FOV # online_main sets the first-person lens here; kicks add on top.


# --- pure helpers ---------------------------------------------------------------------------------------------------

## Red flash strength for a hit of `damage` HP (a scratch still reads, a big hit saturates).
static func hurt_intensity(damage: float) -> float:
	return clampf(damage / 40.0, 0.25, 1.0)


## 0 at or above the threshold, rising to 1 at death's door.
static func low_health_amount(health: float, start: float = LOW_HEALTH_START) -> float:
	if health >= start:
		return 0.0
	return clampf(1.0 - maxf(health, 0.0) / start, 0.0, 1.0)


## Double-thump pulse in 0..1, faster as health drops. Zero when `amount` is zero.
static func heartbeat(time: float, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var bpm := lerpf(70.0, 130.0, amount)
	var phase := fposmod(time * bpm / 60.0, 1.0)
	var beat := exp(-pow((phase - 0.05) * 14.0, 2.0)) + 0.6 * exp(-pow((phase - 0.30) * 14.0, 2.0))
	return clampf(beat, 0.0, 1.0) * amount


## Exponential decay towards zero, frame-rate independent.
static func decay(value: float, delta: float, rate: float) -> float:
	return value * exp(-rate * delta)


## Brief freeze for an impact: Vector2(real seconds, time scale). Zero duration means no hit-stop.
static func hit_stop(damage: float, killed: bool, mine: bool) -> Vector2:
	if not mine:
		return Vector2.ZERO
	if killed:
		return Vector2(0.09, 0.08)
	if damage >= 30.0:
		return Vector2(0.06, 0.12)
	return Vector2.ZERO


## Whether a hit-stop is still running at `now` (msec).
static func stop_active(now_msec: int, until_msec: int) -> bool:
	return now_msec < until_msec


## FOV kick: wider while sprinting, wider still on the bike, scaled by actual speed.
static func fov_target(base: float, sprinting: bool, riding: bool, speed: float) -> float:
	var kick := 0.0
	if riding:
		kick = 6.0 * clampf(speed / 9.0, 0.0, 1.0)
	elif sprinting:
		kick = 3.5 * clampf(speed / 6.0, 0.0, 1.0)
	return base + kick


## Distance pull-out so fast travel shows more road ahead.
static func zoom_multiplier(sprinting: bool, riding: bool, speed: float) -> float:
	if riding:
		return 1.0 + 0.12 * clampf(speed / 9.0, 0.0, 1.0)
	if sprinting:
		return 1.0 + 0.05 * clampf(speed / 6.0, 0.0, 1.0)
	return 1.0


## Cinemachine-style look-ahead: lead the target along the move direction (xz), capped.
static func look_ahead(move_dir: Vector2, speed: float) -> Vector3:
	if move_dir.length_squared() < 0.0001:
		return Vector3.ZERO
	var lead := clampf(speed * 0.35, 0.0, MAX_LOOK_AHEAD)
	var n := move_dir.normalized()
	return Vector3(n.x, 0.0, n.y) * lead


## Radial blur strength 0..1; only at speed, off on Low quality.
static func radial_blur_amount(speed: float, sprinting: bool, riding: bool, level: int) -> float:
	if level < 1:
		return 0.0
	var gate := 4.5 if riding else 5.5
	if not (riding or sprinting) or speed <= gate:
		return 0.0
	return clampf((speed - gate) / 6.0, 0.0, 1.0)


## Blur taps per quality tier (0 disables the loop in the shader).
static func blur_taps(level: int) -> int:
	return [0, 3, 5, 8][clampi(level, 0, 3)]


## Letterbox target: bars slide in while dead (cinematic death), out when alive.
static func letterbox_target(alive: bool) -> float:
	return 0.0 if alive else 1.0


## Photo-mode orbit clamp: Vector3(yaw, pitch, distance).
static func clamp_orbit(yaw: float, pitch: float, dist: float) -> Vector3:
	return Vector3(wrapf(yaw, -PI, PI), clampf(pitch, 0.1, 1.45), clampf(dist, 4.0, 45.0))


# --- node -----------------------------------------------------------------------------------------------------------

func setup(main_camera: Camera3D, hud_layer: CanvasLayer = null) -> void:
	camera = main_camera
	hud = hud_layer
	var layer := CanvasLayer.new()
	layer.layer = -9
	add_child(layer)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect.material = _mat
	_rect.visible = false
	layer.add_child(_rect)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


## Feed gameplay events (the match block in online_main). `distance` is metres from the player to the event.
func on_event(event: Dictionary, my_peer: int, distance: float) -> void:
	var kind := str(event.get("type", ""))
	var damage := float(event.get("damage", 0.0))
	if kind == "hit":
		var on_zombie := str(event.get("kind", "")) == "zombie"
		if not on_zombie and int(event.get("id", -1)) == my_peer:
			_hurt = maxf(_hurt, hurt_intensity(damage))
			_aberration = maxf(_aberration, hurt_intensity(damage))
		_start_stop(hit_stop(damage, false, on_zombie and distance < 4.0))
	elif kind == "zombie_died" or kind == "finishing_strike":
		_start_stop(hit_stop(damage, true, distance < 6.0))


func _start_stop(v: Vector2) -> void:
	if v.x <= 0.0:
		return
	Engine.time_scale = v.y
	_stop_until_msec = Time.get_ticks_msec() + int(v.x * 1000.0)


## Per-frame update. `you` is the server state dict; read `look`/`zoom_mul`/`photo_active` afterwards.
func update(delta: float, you: Dictionary, move_input: Vector2, speed: float, quality_level: int) -> void:
	if Engine.time_scale != 1.0 and not stop_active(Time.get_ticks_msec(), _stop_until_msec):
		Engine.time_scale = 1.0
	var d := delta / maxf(Engine.time_scale, 0.01) # Real-time delta so the feel does not slow with the hit-stop.
	_clock += d
	var health := float(you.get("health", 100.0))
	var alive := bool(you.get("alive", true))
	var riding := bool(you.get("mounted", false)) and alive
	var sprinting := InputMap.has_action("survive_sprint") and Input.is_action_pressed("survive_sprint") and speed > 4.8 and not riding
	_hurt = decay(_hurt, d, 2.6)
	_aberration = decay(_aberration, d, 5.0)
	var low := low_health_amount(health) if alive else 0.0
	var beat := heartbeat(_clock, low)
	_blur = move_toward(_blur, radial_blur_amount(speed, sprinting, riding, quality_level), d * 2.5)
	_letterbox = move_toward(_letterbox, letterbox_target(alive), d * 0.9)
	# Frost creeps in slowly (~25 s) and melts faster (~8 s); off on Performance.
	var frost_target: float = clampf(cold, 0.0, 1.0) * 0.8 if quality_level >= 1 else 0.0
	_frost = move_toward(_frost, frost_target, d * (0.03 if frost_target > _frost else 0.12))
	_fov = lerpf(_fov, fov_target(base_fov, sprinting, riding, speed), 1.0 - exp(-5.0 * d))
	if camera != null:
		camera.fov = _fov
	zoom_mul = lerpf(zoom_mul, zoom_multiplier(sprinting, riding, speed), 1.0 - exp(-3.0 * d))
	var lead := look_ahead(move_input, speed) if alive else Vector3.ZERO
	_look_smooth = _look_smooth.lerp(lead, 1.0 - exp(-3.0 * d))
	look = _look_smooth
	var active := _hurt > 0.01 or _aberration > 0.01 or low > 0.0 or _blur > 0.01 or _letterbox > 0.001 or _frost > 0.01
	if _rect != null:
		_rect.visible = active
		if active:
			_mat.set_shader_parameter("hurt", _hurt)
			_mat.set_shader_parameter("low_health", low)
			_mat.set_shader_parameter("heartbeat", beat)
			_mat.set_shader_parameter("aberration", _aberration if quality_level >= 1 else 0.0)
			_mat.set_shader_parameter("radial_blur", _blur)
			_mat.set_shader_parameter("blur_taps", blur_taps(quality_level))
			_mat.set_shader_parameter("letterbox", _letterbox)
			_mat.set_shader_parameter("frost", _frost)


## Photo mode: free orbit around the player with the interface hidden. Ctrl+Alt+P toggles, Esc leaves.
func toggle_photo(player_pos: Vector3) -> void:
	photo_active = not photo_active
	_photo_target = player_pos
	_photo_yaw = 0.0
	_photo_pitch = 0.9
	_photo_dist = 20.0
	if hud != null:
		hud.visible = not photo_active


func photo_camera(cam: Camera3D, player_pos: Vector3) -> void:
	_photo_target = _photo_target.lerp(player_pos + Vector3(0, 0.8, 0), 0.1)
	var orbit := clamp_orbit(_photo_yaw, _photo_pitch, _photo_dist)
	var offset := Vector3(sin(orbit.x) * cos(orbit.y), sin(orbit.y), cos(orbit.x) * cos(orbit.y)) * orbit.z
	cam.position = cam.position.lerp(_photo_target + offset, 0.25)
	cam.look_at(_photo_target)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.alt_pressed and event.keycode == KEY_P and camera != null:
			toggle_photo(camera.position)
			get_viewport().set_input_as_handled()
		elif photo_active and event.keycode == KEY_ESCAPE:
			toggle_photo(_photo_target)
			get_viewport().set_input_as_handled()
	elif photo_active and event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_photo_yaw -= event.relative.x * 0.006
		_photo_pitch += event.relative.y * 0.004
		get_viewport().set_input_as_handled()
	elif photo_active and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_photo_dist -= 1.5
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_photo_dist += 1.5
		get_viewport().set_input_as_handled()
