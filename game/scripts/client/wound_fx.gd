extends Node3D
## Location-based gore, built the way shipped games do it (Valve's L4D2 wound cut-outs, the
## layered anatomy of Dead Island 2's FLESH, weight-based dismemberment):
##  * the bone nearest the strike gets a real opening — a shader cuts the skin along the strike
##    and shows a crater of skin, fat and striated muscle, with the actual BONE inside;
##  * fresh wounds keep dripping;
##  * a severing blow removes the limb from the body BY BONE WEIGHTS (no stretching), leaves a
##    layered stump (skin rim, fat, muscle, bone with marrow) and throws a copy of the real limb;
##  * blunt power blows snap limbs to sick angles.
## Purely cosmetic and client-side; the server only says who hit whom, how hard, and if it killed.

const MAX_WOUNDS_PER_BODY := 10
const MAX_WOUNDS := 160
const MAX_PIECES := 24
const PIECE_LIFETIME := 25.0
const SEVER_DAMAGE := 22.0

var _pieces: Array[Dictionary] = [] # {"body": RigidBody3D, "age": float}
var _severed: Array[Dictionary] = [] # {"skeleton": Skeleton3D, "bone": int}


## Runs after animation and ragdoll every frame: collapses severed bones and bends broken ones.
class Breaker extends SkeletonModifier3D:
	var severed: Dictionary = {} # bone -> true
	var broken: Dictionary = {} # bone -> Quaternion offset
	func _process_modification() -> void:
		var skeleton := get_skeleton()
		if skeleton == null:
			return
		for bone in broken:
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * (broken[bone] as Quaternion))


static func _breaker_of(skeleton: Skeleton3D) -> Breaker:
	for child in skeleton.get_children():
		if child is Breaker:
			return child
	var breaker := Breaker.new()
	skeleton.add_child(breaker)
	return breaker


static func _is_blunt(weapon_id: String) -> bool:
	var w := weapon_id.to_lower()
	return w == "" or w.contains("club") or w.contains("hammer") or w.contains("bat") or w.contains("mace") or w.contains("pipe")
var _rng := RandomNumberGenerator.new()
var _drip_timer := 0.0
const DRIP_SECONDS := 9.0 # A fresh wound keeps dripping this long.
const MAX_DRIPPING := 6


func _init() -> void:
	_rng.randomize()


## model: the enemy's character model; origin/direction: the line of the strike in world space.
## Returns true when the blow was spectacular (severed or snapped), for a beat of slow motion.
func on_hit(model: Node3D, origin: Vector3, direction: Vector3, damage: float, ranged: bool, fatal: bool, ichor: bool, weapon_id: String = "", charge: float = 0.0) -> bool:
	if model == null or not is_instance_valid(model) or direction.length_squared() < 0.0001:
		return false
	var skeleton := _skeleton_of(model)
	if skeleton == null:
		return false
	direction = direction.normalized()
	var bone: int = _bone_on_line(skeleton, origin, direction)
	if bone < 0:
		return false
	var bone_at: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin
	# The wound sits on the body surface facing the attacker, a little off the bone axis.
	var to_line: Vector3 = (origin + direction * (bone_at - origin).dot(direction)) - bone_at
	var surface: Vector3 = _surface_point(skeleton, bone_at + to_line.limit_length(0.06), direction)
	var color := Color(0.32, 0.02, 0.02) if not ichor else Color(0.22, 0.06, 0.02)
	_add_wound(skeleton, bone, surface, direction, wound_shape(weapon_id, ranged, damage))
	_spray(surface, -direction, damage, color)
	_add_bone_core(skeleton, bone)
	var spectacular := false
	# Blunt power blows and heavy swings snap arms and legs: the limb hangs at a sick angle.
	var kind: String = _limb_kind(skeleton.get_bone_name(bone))
	if not ranged and _is_blunt(weapon_id) and (charge >= 0.75 or damage >= 28.0) and (kind == "arm" or kind == "leg"):
		_break(skeleton, bone, direction)
		spectacular = true
	var heavy: bool = charge >= 0.75 or damage >= 35.0
	if not ranged and not _is_blunt(weapon_id) and (fatal or heavy) and damage >= SEVER_DAMAGE:
		var cut: int = _severable(skeleton, bone)
		if cut >= 0:
			spectacular = _sever(skeleton, cut, direction, color) or spectacular
	elif fatal and ranged and damage >= SEVER_DAMAGE * 1.6 and _limb_kind(skeleton.get_bone_name(bone)) == "head":
		spectacular = _sever(skeleton, bone, direction, color) or spectacular
	return spectacular


## Where the strike line meets the skin: nearest skinned vertex to the line near the struck bone.
func _surface_point(skeleton: Skeleton3D, near: Vector3, direction: Vector3) -> Vector3:
	# The shader opens a channel along the strike line, so the point only has to sit on that line
	# near the bone; it is moved slightly out toward the attacker so the blood sprays from the skin.
	return near - direction * 0.06


## Snap a limb: from now on it bends 70-110 degrees off its animated pose, with a crack of blood.
func _break(skeleton: Skeleton3D, bone: int, direction: Vector3) -> void:
	var breaker := _breaker_of(skeleton)
	if breaker.broken.has(bone) or breaker.severed.has(bone):
		return
	var local_axis: Vector3 = (skeleton.get_bone_global_pose(bone).basis.inverse() * (skeleton.global_transform.basis.inverse() * direction.cross(Vector3.UP))).normalized()
	if not local_axis.is_finite() or local_axis.length_squared() < 0.5:
		local_axis = Vector3.RIGHT
	breaker.broken[bone] = Quaternion(local_axis, deg_to_rad(_rng.randf_range(70.0, 110.0)))
	var at: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin
	_spray(at, -direction, 30.0, Color(0.3, 0.02, 0.02))


## Ground finisher on a downed body: a blunt weapon caves the skull in, a blade takes the head.
func finisher(model: Node3D, weapon_id: String, ichor: bool) -> void:
	var skeleton := _skeleton_of(model) if model != null and is_instance_valid(model) else null
	if skeleton == null:
		return
	var color := Color(0.32, 0.02, 0.02) if not ichor else Color(0.22, 0.06, 0.02)
	for bone in skeleton.get_bone_count():
		if _limb_kind(skeleton.get_bone_name(bone)) != "head":
			continue
		var head: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin
		var down := Vector3(_rng.randf_range(-0.2, 0.2), -1.0, _rng.randf_range(-0.2, 0.2)).normalized()
		for burst in 4:
			_spray(head + Vector3(0, 0.08, 0), Vector3(_rng.randf_range(-1, 1), 0.6, _rng.randf_range(-1, 1)).normalized(), 60.0, color)
		if _is_blunt(weapon_id):
			_add_wound(skeleton, bone, head - down * 0.1, down, {"radius": 0.06, "elongation": 1.3, "depth": 0.07})
			var breaker := _breaker_of(skeleton)
			breaker.broken[bone] = Quaternion(Vector3.RIGHT, deg_to_rad(35.0))
		else:
			_sever(skeleton, _severable(skeleton, bone), down.cross(Vector3.UP).normalized() + Vector3.UP * 0.3, color)
		return


func _process(delta: float) -> void:
	_update_bodies()
	_drip_timer -= delta
	if _drip_timer <= 0.0:
		_drip_timer = 0.3
		_drip_fresh_wounds()
	for i in range(_severed.size() - 1, -1, -1):
		if not is_instance_valid(_severed[i]["skeleton"]):
			_severed.remove_at(i)
	for i in range(_pieces.size() - 1, -1, -1):
		_pieces[i]["age"] = float(_pieces[i]["age"]) + delta
		var body = _pieces[i]["body"]
		if not is_instance_valid(body) or float(_pieces[i]["age"]) > PIECE_LIFETIME:
			if is_instance_valid(body):
				(body as Node).queue_free()
			_pieces.remove_at(i)


static func _skeleton_of(model: Node) -> Skeleton3D:
	var found: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	return found[0] as Skeleton3D if not found.is_empty() else null


## The bone closest to the strike line (with a nudge toward bigger targets: torso and head).
func _bone_on_line(skeleton: Skeleton3D, origin: Vector3, direction: Vector3) -> int:
	var best := -1
	var best_score := INF
	for bone in skeleton.get_bone_count():
		var kind: String = _limb_kind(skeleton.get_bone_name(bone))
		if kind == "skip":
			continue
		var at: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin
		var along: float = (at - origin).dot(direction)
		if along < 0.0:
			continue
		var miss: float = (origin + direction * along).distance_to(at)
		if kind == "torso":
			miss *= 0.85
		if miss < best_score:
			best_score = miss
			best = bone
	return best if best_score < 0.9 else -1


static func _limb_kind(bone_name: String) -> String:
	var n := bone_name.to_lower()
	if n.contains("finger") or n.contains("thumb") or n.contains("toe") or n.contains("eye") or n.contains("jaw") \
			or n.contains("end") or n.contains("ik") or n.contains("pole") or n.contains("root"):
		return "skip"
	if n.contains("head"):
		return "head"
	if n.contains("neck"):
		return "neck"
	if n.contains("upperarm") or n.contains("upper_arm") or n.contains("shoulder") or n.contains("arm") \
			or n.contains("hand") or n.contains("wrist") or n.contains("elbow"):
		return "arm"
	if n.contains("thigh") or n.contains("upperleg") or n.contains("leg") or n.contains("shin") \
			or n.contains("calf") or n.contains("knee") or n.contains("foot") or n.contains("ankle"):
		return "leg"
	return "torso"


## Where a hit on this bone cuts: arms and legs at the struck bone, the head at the neck.
static func _severable(skeleton: Skeleton3D, bone: int) -> int:
	var kind: String = _limb_kind(skeleton.get_bone_name(bone))
	if kind == "arm" or kind == "leg" or kind == "neck":
		return bone
	if kind == "head":
		var parent: int = skeleton.get_bone_parent(bone)
		return parent if parent >= 0 and _limb_kind(skeleton.get_bone_name(parent)) == "neck" else bone
	return -1


const WOUND_SHADER := preload("res://shaders/wound_flesh.gdshader")
const MAX_OPENINGS := 8 # Shader slots per body; the oldest wound closes when a ninth opens.
var _bodies: Dictionary = {} # skeleton instance id -> {"skeleton", "surfaces": [{mesh, material, source}], "wounds": []}


## Weapon families: stabbing makes a deep round hole, slashing a long gaping cut, blunt a small split.
static func wound_shape(weapon_id: String, ranged: bool, damage: float) -> Dictionary:
	if ranged:
		return {"radius": 0.011, "elongation": 1.0, "depth": 0.02}
	var w := weapon_id.to_lower()
	if w.contains("knife") or w.contains("spear") or w.contains("dagger") or w.contains("bayonet") or w.contains("shiv"):
		return {"radius": clampf(0.018 + damage * 0.0002, 0.018, 0.028), "elongation": 1.6, "depth": 0.035}
	if w == "" or w.contains("club") or w.contains("hammer") or w.contains("bat") or w.contains("mace") or w.contains("pipe"):
		return {"radius": 0.014, "elongation": 2.0, "depth": 0.05}
	return {"radius": clampf(0.014 + damage * 0.0002, 0.014, 0.022), "elongation": clampf(3.0 + damage * 0.04, 3.0, 4.5), "depth": 0.03}


func _add_wound(skeleton: Skeleton3D, bone: int, at: Vector3, direction: Vector3, shape: Dictionary) -> void:
	var body: Dictionary = _body_of(skeleton)
	if body.is_empty():
		return
	var bone_world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	var to_bone: Transform3D = bone_world.affine_inverse()
	# A random cut angle across the strike, stored in the bone's frame so it rides the animation.
	var across: Vector3 = direction.cross(Vector3.UP if absf(direction.y) < 0.95 else Vector3.RIGHT).normalized()
	across = across.rotated(direction, _rng.randf_range(-0.9, 0.9))
	var wounds: Array = body["wounds"]
	if wounds.size() >= MAX_OPENINGS:
		wounds.pop_front()
	wounds.append({"bone": bone, "at": to_bone * at,
		"axis": (to_bone.basis * across).normalized(), "dir": (to_bone.basis * direction).normalized(),
		"radius": float(shape["radius"]), "elongation": float(shape["elongation"]), "depth": float(shape["depth"]),
		"born": Time.get_ticks_msec()})


## Swap the body's opaque surfaces to the openable flesh shader (once per body).
func _body_of(skeleton: Skeleton3D) -> Dictionary:
	var key: int = skeleton.get_instance_id()
	if _bodies.has(key):
		return _bodies[key]
	if _bodies.size() >= MAX_WOUNDS / MAX_OPENINGS:
		return {}
	var surfaces: Array = []
	for node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		if mesh.material_override is BaseMaterial3D:
			var swapped := _flesh_material(mesh.material_override as BaseMaterial3D)
			if swapped != null:
				surfaces.append({"mesh": mesh, "material": swapped, "source": mesh.material_override})
				mesh.material_override = swapped
			continue
		for s in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(s) as BaseMaterial3D
			var swapped := _flesh_material(source)
			if swapped != null:
				surfaces.append({"mesh": mesh, "material": swapped, "source": source})
				mesh.set_surface_override_material(s, swapped)
	var body := {"skeleton": skeleton, "surfaces": surfaces, "wounds": [], "mask": [0, 0, 0, 0, 0], "cores": {}}
	_bodies[key] = body
	return body


static func _flesh_material(source: BaseMaterial3D) -> ShaderMaterial:
	if source == null:
		return null
	var material := ShaderMaterial.new()
	material.shader = WOUND_SHADER
	# Hair and cloth cards must be cuttable too: keep their shape by cutting out on texture alpha.
	if source.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		material.set_shader_parameter("alpha_scissor", source.alpha_scissor_threshold)
	elif source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		material.set_shader_parameter("alpha_scissor", 0.4)
	material.set_shader_parameter("albedo_color", source.albedo_color)
	if source.albedo_texture != null:
		material.set_shader_parameter("albedo_tex", source.albedo_texture)
		material.set_shader_parameter("has_albedo_tex", 1.0)
	if source.normal_enabled and source.normal_texture != null:
		material.set_shader_parameter("normal_tex", source.normal_texture)
		material.set_shader_parameter("has_normal_tex", 1.0)
	material.set_shader_parameter("uv_scale", source.uv1_scale)
	material.set_shader_parameter("uv_offset", source.uv1_offset)
	material.set_shader_parameter("base_roughness", source.roughness)
	material.set_shader_parameter("base_metallic", source.metallic)
	return material


## Move every opening with its bone, into each mesh's local space, and mirror the hit flash.
func _update_bodies() -> void:
	for key in _bodies.keys():
		var body: Dictionary = _bodies[key]
		var skeleton = body["skeleton"]
		if not is_instance_valid(skeleton):
			_bodies.erase(key)
			continue
		var world_wounds: Array = []
		for wound in body["wounds"]:
			var bone_world: Transform3D = (skeleton as Skeleton3D).global_transform * (skeleton as Skeleton3D).get_bone_global_pose(int(wound["bone"]))
			world_wounds.append([bone_world * (wound["at"] as Vector3), bone_world.basis * (wound["axis"] as Vector3), bone_world.basis * (wound["dir"] as Vector3), wound])
		for surface in body["surfaces"]:
			var mesh = surface["mesh"]
			if not is_instance_valid(mesh):
				continue
			var to_local: Transform3D = (mesh as MeshInstance3D).global_transform.affine_inverse()
			var unit: float = maxf((mesh as MeshInstance3D).global_transform.basis.get_scale().x, 0.0001)
			var centres := PackedVector4Array()
			var axes := PackedVector4Array()
			var dirs := PackedVector4Array()
			for entry in world_wounds:
				var wound: Dictionary = entry[3]
				var c: Vector3 = to_local * (entry[0] as Vector3)
				var a: Vector3 = (to_local.basis * (entry[1] as Vector3)).normalized()
				var d: Vector3 = (to_local.basis * (entry[2] as Vector3)).normalized()
				centres.append(Vector4(c.x, c.y, c.z, float(wound["radius"]) / unit))
				axes.append(Vector4(a.x, a.y, a.z, float(wound["elongation"])))
				dirs.append(Vector4(d.x, d.y, d.z, float(wound["depth"]) / unit))
			while centres.size() < MAX_OPENINGS:
				centres.append(Vector4.ZERO)
				axes.append(Vector4(1, 0, 0, 1))
				dirs.append(Vector4.ZERO)
			var material: ShaderMaterial = surface["material"]
			material.set_shader_parameter("wound_count", world_wounds.size())
			material.set_shader_parameter("wounds", centres)
			material.set_shader_parameter("wound_axes", axes)
			material.set_shader_parameter("wound_dirs", dirs)
			var source = surface["source"]
			if source is BaseMaterial3D:
				material.set_shader_parameter("flash_energy", (source as BaseMaterial3D).emission_energy_multiplier if (source as BaseMaterial3D).emission_enabled else 0.0)


## A short arterial spray at the wound, along the outgoing side.
func _spray(at: Vector3, outward: Vector3, damage: float, color: Color) -> void:
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 0.85
	particles.amount = clampi(int(10 + damage * 0.8), 10, 40)
	particles.lifetime = 0.9
	var process := ParticleProcessMaterial.new()
	process.direction = (outward + Vector3.UP * 0.4).normalized()
	process.spread = 28.0
	process.initial_velocity_min = 1.5
	process.initial_velocity_max = 3.5 + damage * 0.05
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.scale_min = 0.5
	process.scale_max = 1.4
	particles.process_material = process
	var drop := SphereMesh.new()
	drop.radius = 0.007
	drop.height = 0.016
	drop.radial_segments = 6
	drop.rings = 3
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.12
	material.metallic_specular = 0.8
	drop.material = material
	particles.draw_pass_1 = drop
	add_child(particles)
	particles.global_position = at
	particles.emitting = true
	get_tree().create_timer(2.0).timeout.connect(particles.queue_free)


## Bones of a limb: the cut bone and everything below it, as the shader's 5x30-bit mask.
static func _subtree_mask(skeleton: Skeleton3D, bone: int) -> Array:
	var mask := [0, 0, 0, 0, 0]
	var stack: Array = [bone]
	while not stack.is_empty():
		var b: int = stack.pop_back()
		if b < 150:
			mask[b / 30] = int(mask[b / 30]) | (1 << (b % 30))
		stack.append_array(skeleton.get_bone_children(b))
	return mask


static func _set_cut(material: ShaderMaterial, mode: int, mask: Array) -> void:
	material.set_shader_parameter("cut_mode", mode)
	material.set_shader_parameter("cut_mask", PackedInt32Array(mask))


## Sever by bone weights: the limb leaves the body (no bone scaling, so nothing stretches),
## a layered stump caps the joint, and a copy of the real limb flies off.
func _sever(skeleton: Skeleton3D, bone: int, direction: Vector3, color: Color) -> bool:
	if bone < 0:
		return false
	for entry in _severed:
		if entry["skeleton"] == skeleton and int(entry["bone"]) == bone:
			return false
	var body: Dictionary = _body_of(skeleton)
	if body.is_empty():
		return false
	var limb: Array = _subtree_mask(skeleton, bone)
	var mask: Array = body["mask"]
	for w in 5:
		mask[w] = int(mask[w]) | int(limb[w])
	for surface in body["surfaces"]:
		_set_cut(surface["material"], 1, mask)
	# Bone cores inside the lost limb go with it.
	for holder in skeleton.get_children():
		if holder is BoneAttachment3D and holder.has_meta("core"):
			var b: int = (holder as BoneAttachment3D).bone_idx
			if b < 150 and (int(limb[b / 30]) >> (b % 30)) & 1 == 1:
				holder.queue_free()
	var kind: String = _limb_kind(skeleton.get_bone_name(bone))
	_severed.append({"skeleton": skeleton, "bone": bone})
	_breaker_of(skeleton).broken.erase(bone)
	var joint: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	var child_at: Vector3 = joint.origin + joint.basis.y.normalized() * 0.25
	for child in skeleton.get_bone_children(bone):
		child_at = (skeleton.global_transform * skeleton.get_bone_global_pose(child)).origin
		break
	var along: Vector3 = (child_at - joint.origin).normalized()
	var radius: float = {"arm": 0.05, "leg": 0.075, "neck": 0.055, "head": 0.06}.get(kind, 0.06)
	var parent: int = skeleton.get_bone_parent(bone)
	if parent >= 0:
		_add_stump(skeleton, parent, joint.origin, along, radius)
	# The stump pumps blood for a few seconds.
	for burst in 6:
		get_tree().create_timer(0.3 * burst).timeout.connect(func() -> void:
			if is_instance_valid(skeleton) and parent >= 0:
				var at: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin
				_spray(at, Vector3.UP * 0.4 + along * 0.6, 22.0 - burst * 3.0, color))
	if _pieces.size() < MAX_PIECES:
		_throw_limb(skeleton, bone, limb, kind, joint, along, radius, direction, color)
	return true


## The flying piece is a frozen copy of the whole model that only draws the severed limb.
func _throw_limb(skeleton: Skeleton3D, bone: int, limb: Array, kind: String, joint: Transform3D, along: Vector3,
		radius: float, direction: Vector3, color: Color) -> void:
	var source_root: Node3D = skeleton.get_parent() as Node3D
	if source_root == null:
		return
	var copy: Node3D = source_root.duplicate() as Node3D
	# Drop everything that animates or hangs off the bones, right now (not deferred).
	for type_name in ["AnimationPlayer", "AnimationTree", "SkeletonModifier3D", "BoneAttachment3D", "GPUParticles3D"]:
		for extra in copy.find_children("*", type_name, true, false):
			if is_instance_valid(extra) and extra.get_parent() != null:
				extra.get_parent().remove_child(extra)
				extra.free()
	for node in copy.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		if mesh.material_override != null:
			mesh.material_override = _piece_material(mesh.material_override, limb)
		for s in mesh.mesh.get_surface_count():
			var active := mesh.get_active_material(s)
			if active != null:
				mesh.set_surface_override_material(s, _piece_material(active, limb))
	var rigid := RigidBody3D.new()
	rigid.add_to_group("buoyant") # A severed limb floats if it lands in water (buoyancy.gd).
	rigid.mass = 3.0 if kind == "head" or kind == "neck" else 4.0
	var shape := CollisionShape3D.new()
	var length := 0.45 if kind == "leg" else 0.32
	if kind == "head" or kind == "neck":
		var sphere := SphereShape3D.new()
		sphere.radius = 0.12
		shape.shape = sphere
	else:
		var capsule := CapsuleShape3D.new()
		capsule.radius = radius
		capsule.height = length
		shape.shape = capsule
	add_child(rigid)
	rigid.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, along)), joint.origin + along * length * 0.5)
	shape.rotation = Vector3.ZERO
	rigid.add_child(shape)
	rigid.add_child(copy)
	copy.global_transform = source_root.global_transform
	var copy_skeleton := _skeleton_of(copy)
	if copy_skeleton != null:
		_add_stump(copy_skeleton, bone, joint.origin, -along, radius) # The raw end of the piece.
	rigid.apply_central_impulse((direction * 2.4 + Vector3.UP * 1.8) * rigid.mass)
	rigid.apply_torque_impulse(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.8)
	_pieces.append({"body": rigid, "age": 0.0})


static func _piece_material(active: Material, limb: Array) -> Material:
	var material: ShaderMaterial = null
	if active is ShaderMaterial and (active as ShaderMaterial).shader == WOUND_SHADER:
		material = (active as ShaderMaterial).duplicate() as ShaderMaterial
	elif active is BaseMaterial3D:
		material = _flesh_material(active as BaseMaterial3D)
	if material == null:
		return active
	_set_cut(material, 2, limb)
	return material


static var _stump_texture: ImageTexture
static var _bone_material: StandardMaterial3D


## A layered cut face at a joint: torn skin rim, yellow fat, red muscle, white bone with marrow,
## plus the splintered bone end sticking out.
func _add_stump(skeleton: Skeleton3D, bone: int, at: Vector3, outward: Vector3, radius: float) -> void:
	var holder := BoneAttachment3D.new()
	skeleton.add_child(holder)
	holder.bone_idx = bone
	var unit: float = maxf(skeleton.global_transform.basis.get_scale().x, 0.0001)
	var cap := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius / unit
	disc.bottom_radius = radius * 0.92 / unit
	disc.height = 0.01 / unit
	disc.radial_segments = 20
	disc.rings = 1
	cap.mesh = disc
	var face := StandardMaterial3D.new()
	face.albedo_texture = _stump_texture_get()
	face.uv1_triplanar = false
	face.roughness = 0.2
	face.metallic_specular = 0.7
	cap.material_override = face
	holder.add_child(cap)
	var spike := MeshInstance3D.new()
	var stub := CylinderMesh.new()
	stub.top_radius = radius * 0.22 / unit
	stub.bottom_radius = radius * 0.3 / unit
	stub.height = 0.045 / unit
	spike.mesh = stub
	spike.material_override = _bone_material_get()
	holder.add_child(spike)
	# The attachment only follows its bone from the next frame: place children in the bone's frame.
	var to_bone: Transform3D = (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).affine_inverse()
	var basis := Basis(Quaternion(Vector3.UP, outward.normalized()))
	cap.transform = to_bone * Transform3D(basis.scaled(Vector3.ONE * unit), at)
	spike.transform = to_bone * Transform3D(basis.scaled(Vector3.ONE * unit), at + outward.normalized() * 0.02)


## Real bone inside the limb: hidden by the skin, seen through any opening over it.
func _add_bone_core(skeleton: Skeleton3D, bone: int) -> void:
	var body: Dictionary = _body_of(skeleton)
	var kind: String = _limb_kind(skeleton.get_bone_name(bone))
	var name := skeleton.get_bone_name(bone).to_lower()
	# Only the thick upper segments (thigh, upper arm) hide a bone well inside every model.
	var upper: bool = name.contains("thigh") or name.contains("upperarm") or name.contains("upper_arm") or name.contains("upperleg")
	if body.is_empty() or body["cores"].has(bone) or not upper:
		return
	var children: PackedInt32Array = skeleton.get_bone_children(bone)
	if children.is_empty():
		return
	body["cores"][bone] = true
	var mask: Array = body["mask"]
	if bone < 150 and (int(mask[bone / 30]) >> (bone % 30)) & 1 == 1:
		return # Already cut off.
	var from: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin
	var to: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(children[0])).origin
	var unit: float = maxf(skeleton.global_transform.basis.get_scale().x, 0.0001)
	var holder := BoneAttachment3D.new()
	holder.set_meta("core", true)
	skeleton.add_child(holder)
	holder.bone_idx = bone
	var core := MeshInstance3D.new()
	var shaft := CapsuleMesh.new()
	shaft.radius = (0.011 if kind == "arm" else 0.015) / unit
	shaft.height = maxf(from.distance_to(to) * 0.8, 0.05) / unit
	core.mesh = shaft
	core.material_override = _bone_material_get()
	holder.add_child(core)
	var to_bone: Transform3D = (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).affine_inverse()
	core.transform = to_bone * Transform3D(Basis(Quaternion(Vector3.UP, (to - from).normalized())).scaled(Vector3.ONE * unit), (from + to) * 0.5)


## Fresh wounds keep bleeding for a while.
func _drip_fresh_wounds() -> void:
	var now: int = Time.get_ticks_msec()
	var dripping := 0
	for key in _bodies:
		var body: Dictionary = _bodies[key]
		var skeleton = body["skeleton"]
		if not is_instance_valid(skeleton):
			continue
		for wound in body["wounds"]:
			if now - int(wound.get("born", 0)) > int(DRIP_SECONDS * 1000.0) or dripping >= MAX_DRIPPING:
				continue
			dripping += 1
			var bone_world: Transform3D = (skeleton as Skeleton3D).global_transform * (skeleton as Skeleton3D).get_bone_global_pose(int(wound["bone"]))
			_drip(bone_world * (wound["at"] as Vector3))


func _drip(at: Vector3) -> void:
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.amount = 2
	particles.lifetime = 0.8
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.DOWN
	process.spread = 8.0
	process.initial_velocity_min = 0.1
	process.initial_velocity_max = 0.4
	process.gravity = Vector3(0.0, -9.8, 0.0)
	particles.process_material = process
	var drop := SphereMesh.new()
	drop.radius = 0.006
	drop.height = 0.016
	drop.radial_segments = 6
	drop.rings = 3
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.01, 0.01)
	material.roughness = 0.1
	drop.material = material
	particles.draw_pass_1 = drop
	add_child(particles)
	particles.global_position = at
	particles.emitting = true
	get_tree().create_timer(1.2).timeout.connect(particles.queue_free)


static func _bone_material_get() -> StandardMaterial3D:
	if _bone_material == null:
		_bone_material = StandardMaterial3D.new()
		_bone_material.albedo_color = Color(0.9, 0.86, 0.76)
		_bone_material.roughness = 0.45
	return _bone_material


## Cross-section texture of a limb: skin, fat, muscle with fibre noise, bone, marrow.
static func _stump_texture_get() -> ImageTexture:
	if _stump_texture != null:
		return _stump_texture
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	for y in size:
		for x in size:
			var u: float = (float(x) / float(size - 1)) * 2.0 - 1.0
			var v: float = (float(y) / float(size - 1)) * 2.0 - 1.0
			var r: float = Vector2(u, v).length() + noise.get_noise_2d(x, y) * 0.05
			var n: float = 0.5 + 0.5 * noise.get_noise_2d(x * 3.0, y * 3.0)
			var c: Color
			if r > 0.93:
				c = Color(0.35, 0.05, 0.05) # Torn skin edge.
			elif r > 0.8:
				c = Color(0.88, 0.74, 0.45).darkened(n * 0.15) # Fat.
			elif r > 0.32:
				c = Color(0.52, 0.05, 0.06).darkened(0.25 * n) # Muscle.
			elif r > 0.2:
				c = Color(0.92, 0.88, 0.78) # Cortical bone.
			else:
				c = Color(0.55, 0.12, 0.1) # Marrow.
			image.set_pixel(x, y, c)
	image.generate_mipmaps()
	_stump_texture = ImageTexture.create_from_image(image)
	return _stump_texture
