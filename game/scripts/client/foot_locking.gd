extends RefCounted
## Foot locking with contact phases. Inspired by UE5 Foot Placement / Foot IK and
## Unity Animation Rigging two-bone IK foot pinning. Pure math (no nodes) so it can
## be tested headless; one instance per character.

const MAX_STRETCH: float = 0.35  ## metres the body may pull a locked foot from the animated pose
const BLEND_IN: float = 0.08  ## seconds to reach full IK weight after plant
const BLEND_OUT: float = 0.2  ## seconds to return to the animation after lift-off or release
const PLANT_THRESHOLD: float = 0.5
const FEET: Array[String] = ["left", "right"]

var _locked: Dictionary = {}  ## foot -> bool
var _released: Dictionary = {}  ## foot -> bool (stretched out; no re-lock until lift-off)
var _lock_pos: Dictionary = {}  ## foot -> Vector3
var _weight: Dictionary = {}  ## foot -> float


func _init() -> void:
	for foot: String in FEET:
		_locked[foot] = false
		_released[foot] = false
		_lock_pos[foot] = Vector3.ZERO
		_weight[foot] = 0.0


func update(delta: float, foot_world: Dictionary, contact: Dictionary, ground_height: Callable) -> Dictionary:
	var out: Dictionary = {}
	for foot: String in FEET:
		var anim: Vector3 = foot_world.get(foot, Vector3.ZERO)
		var c: float = contact.get(foot, 0.0)
		var planted: bool = c > PLANT_THRESHOLD
		var locked: bool = _locked[foot]
		var weight: float = _weight[foot]
		var pos: Vector3 = _lock_pos[foot]

		if not planted:
			locked = false
			_released[foot] = false
		elif not locked and not _released[foot]:
			var gy: float = ground_height.call(anim.x, anim.z)
			pos = Vector3(anim.x, gy, anim.z)
			locked = true
		elif locked and pos.distance_to(anim) > MAX_STRETCH:
			locked = false
			_released[foot] = true

		if locked:
			weight = minf(1.0, weight + delta / BLEND_IN)
		else:
			weight = maxf(0.0, weight - delta / BLEND_OUT)

		_locked[foot] = locked
		_lock_pos[foot] = pos
		_weight[foot] = weight
		out[foot] = {
			"target": pos if weight > 0.0 else anim,
			"weight": weight,
			"locked": locked,
		}
	return out


## Lowers the pelvis by the larger negative foot correction so the lower foot can reach.
static func pelvis_offset(left_target_y: float, right_target_y: float, left_anim_y: float, right_anim_y: float) -> float:
	var left_corr: float = left_target_y - left_anim_y
	var right_corr: float = right_target_y - right_anim_y
	return clampf(minf(minf(left_corr, right_corr), 0.0), -0.25, 0.0)
