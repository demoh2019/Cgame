extends RefCounted
## Motion Warping for melee (UE5 Motion Warping / "magnetism" in action RPGs):
## during the wind-up of a swing the visual model glides a short way toward
## the enemy in front of it and turns to face it (orientation warping), then
## eases back to the server-owned position. Purely cosmetic: the server's
## authoritative position and hit test never move.

const MAX_SLIDE := 0.45 # Metres of visual lunge.
const CONE_DOT := 0.5 # About 60 degrees either side of the swing.
const SEARCH_EXTRA := 1.2 # Look a little past weapon reach for a target.
const LUNGE_SECONDS := 0.14
const RETURN_SECONDS := 0.26
const STOP_SHORT := 0.75 # Never slide into the target's body.


## Returns {"offset": Vector3 (world, horizontal), "yaw": float} or {} when nothing to warp to.
static func solve(origin: Vector3, direction: Vector2, reach: float, targets: Array) -> Dictionary:
	if direction.length_squared() < 0.0001 or not origin.is_finite():
		return {}
	var dir := direction.normalized()
	var best: Vector3 = Vector3.INF
	var best_distance := INF
	for candidate in targets:
		var p: Vector3 = candidate
		if not p.is_finite():
			continue
		var to := Vector2(p.x - origin.x, p.z - origin.z)
		var distance := to.length()
		if distance < 0.05 or distance > reach + SEARCH_EXTRA:
			continue
		if to.normalized().dot(dir) < CONE_DOT:
			continue
		if distance < best_distance:
			best_distance = distance
			best = p
	if best == Vector3.INF:
		return {}
	var to_target := Vector2(best.x - origin.x, best.z - origin.z)
	var slide: float = clampf(best_distance - STOP_SHORT, 0.0, MAX_SLIDE)
	var flat := to_target.normalized() * slide
	return {"offset": Vector3(flat.x, 0.0, flat.y), "yaw": atan2(to_target.x, to_target.y)}


## Animates a model node's local offset out and back. Safe to call repeatedly.
static func play(model: Node3D, world_offset: Vector3) -> void:
	if model == null or not model.is_inside_tree():
		return
	var parent := model.get_parent() as Node3D
	var local: Vector3 = world_offset
	if parent != null:
		local = parent.global_transform.basis.inverse() * world_offset
	var rest: Vector3 = model.get_meta(&"aa_warp_rest", model.position)
	model.set_meta(&"aa_warp_rest", rest)
	var previous: Variant = model.get_meta(&"aa_warp_tween", null)
	if previous is Tween and (previous as Tween).is_valid():
		(previous as Tween).kill()
	var tween := model.create_tween()
	tween.tween_property(model, "position", rest + local, LUNGE_SECONDS) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(model, "position", rest, RETURN_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	model.set_meta(&"aa_warp_tween", tween)
