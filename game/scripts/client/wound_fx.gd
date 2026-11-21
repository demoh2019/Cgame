extends Node3D
## Location-based gore on enemies: the bone nearest the strike gets a cut or a bullet wound
## (a decal riding on that bone), blood sprays from the spot, and a heavy killing blow on a
## limb or the neck severs it — the bone collapses on the body and a bloody piece flies off.
## Purely cosmetic and client-side; the server only says who hit whom, how hard, and if it killed.

const MAX_WOUNDS_PER_BODY := 10
const MAX_WOUNDS := 160
const MAX_PIECES := 24
const PIECE_LIFETIME := 25.0
const SEVER_DAMAGE := 22.0

static var _cut_texture: ImageTexture
static var _hole_texture: ImageTexture
var _wounds: Array[Node] = []
var _pieces: Array[Dictionary] = [] # {"body": RigidBody3D, "age": float}
var _severed: Array[Dictionary] = [] # {"skeleton": Skeleton3D, "bone": int}
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


## model: the enemy's character model; origin/direction: the line of the strike in world space.
func on_hit(model: Node3D, origin: Vector3, direction: Vector3, damage: float, ranged: bool, fatal: bool, ichor: bool) -> void:
	if model == null or not is_instance_valid(model) or direction.length_squared() < 0.0001:
		return
	var skeleton := _skeleton_of(model)
	if skeleton == null:
		return
	direction = direction.normalized()
	var bone: int = _bone_on_line(skeleton, origin, direction)
	if bone < 0:
		return
	var bone_at: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin
	# The wound sits on the body surface facing the attacker, a little off the bone axis.
	var to_line: Vector3 = (origin + direction * (bone_at - origin).dot(direction)) - bone_at
	var surface: Vector3 = bone_at + to_line.limit_length(0.06) - direction * 0.09
	var color := Color(0.32, 0.02, 0.02) if not ichor else Color(0.22, 0.06, 0.02)
	_add_wound(skeleton, bone, surface, direction, damage, ranged, color)
	_spray(surface, -direction, damage, color)
	if fatal and not ranged and damage >= SEVER_DAMAGE:
		var cut: int = _severable(skeleton, bone)
		if cut >= 0:
			_sever(skeleton, cut, direction, color)
	elif fatal and ranged and damage >= SEVER_DAMAGE * 1.6 and _limb_kind(skeleton.get_bone_name(bone)) == "head":
		_sever(skeleton, bone, direction, color)


func _process(delta: float) -> void:
	# Keep severed bones collapsed: animation tracks rewrite the pose every frame.
	for i in range(_severed.size() - 1, -1, -1):
		var entry: Dictionary = _severed[i]
		var skeleton = entry["skeleton"]
		if not is_instance_valid(skeleton):
			_severed.remove_at(i)
			continue
		(skeleton as Skeleton3D).set_bone_pose_scale(int(entry["bone"]), Vector3.ONE * 0.001)
	for i in range(_pieces.size() - 1, -1, -1):
		_pieces[i]["age"] = float(_pieces[i]["age"]) + delta
		var body = _pieces[i]["body"]
		if not is_instance_valid(body) or float(_pieces[i]["age"]) > PIECE_LIFETIME:
			if is_instance_valid(body):
				(body as Node).queue_free()
			_pieces.remove_at(i)
	for i in range(_wounds.size() - 1, -1, -1):
		if not is_instance_valid(_wounds[i]):
			_wounds.remove_at(i)


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


func _add_wound(skeleton: Skeleton3D, bone: int, at: Vector3, direction: Vector3, damage: float, ranged: bool, color: Color) -> void:
	var on_body: int = 0
	for child in skeleton.get_children():
		if child is BoneAttachment3D and child.has_meta("wound"):
			on_body += 1
	if on_body >= MAX_WOUNDS_PER_BODY or _wounds.size() >= MAX_WOUNDS:
		return
	var holder := BoneAttachment3D.new()
	holder.set_meta("wound", true)
	holder.bone_idx = bone
	skeleton.add_child(holder)
	var decal := Decal.new()
	decal.texture_albedo = _hole_texture_get() if ranged else _cut_texture_get()
	decal.modulate = color.lightened(0.15)
	decal.albedo_mix = 1.0
	var length: float = clampf(0.14 + damage * 0.006, 0.14, 0.42)
	decal.size = Vector3(0.09 if ranged else length, 0.3, 0.09 if ranged else 0.12)
	decal.upper_fade = 0.2
	decal.lower_fade = 0.2
	decal.cull_mask = 0xFFFFF
	holder.add_child(decal)
	# A decal projects along its local -Y: aim it down the strike, with a random slash angle.
	var y_axis: Vector3 = -direction
	var x_axis: Vector3 = y_axis.cross(Vector3.UP if absf(y_axis.y) < 0.95 else Vector3.RIGHT).normalized()
	x_axis = x_axis.rotated(y_axis, _rng.randf_range(-0.9, 0.9))
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	decal.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), at)
	_wounds.append(holder)


## A short arterial spray at the wound, along the outgoing side.
func _spray(at: Vector3, outward: Vector3, damage: float, color: Color) -> void:
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 0.85
	particles.amount = clampi(int(8 + damage * 0.8), 8, 48)
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
	var drop := QuadMesh.new()
	drop.size = Vector2(0.035, 0.035)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = material
	particles.draw_pass_1 = drop
	add_child(particles)
	particles.global_position = at
	particles.emitting = true
	get_tree().create_timer(2.0).timeout.connect(particles.queue_free)


## Collapse the bone (and with it everything below) and throw a bloody piece of the right size.
func _sever(skeleton: Skeleton3D, bone: int, direction: Vector3, color: Color) -> void:
	for entry in _severed:
		if entry["skeleton"] == skeleton and int(entry["bone"]) == bone:
			return
	var start: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	var length := 0.3
	for child in skeleton.get_bone_children(bone):
		var child_at: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(child)).origin
		length = maxf(length, minf(start.origin.distance_to(child_at) * 2.0, 0.85))
	var kind: String = _limb_kind(skeleton.get_bone_name(bone))
	_severed.append({"skeleton": skeleton, "bone": bone})
	skeleton.set_bone_pose_scale(bone, Vector3.ONE * 0.001)
	# The stump keeps bleeding for a moment.
	for burst in 3:
		get_tree().create_timer(0.25 * burst).timeout.connect(func() -> void:
			if is_instance_valid(skeleton):
				_spray((skeleton.global_transform * skeleton.get_bone_global_pose(maxi(skeleton.get_bone_parent(bone), 0))).origin.lerp(start.origin, 0.8),
					Vector3.UP, 30.0, color))
	if _pieces.size() >= MAX_PIECES:
		return
	var body := RigidBody3D.new()
	body.mass = 3.0 if kind == "head" or kind == "neck" else 4.0
	var shape := CollisionShape3D.new()
	var mesh := MeshInstance3D.new()
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.42, 0.44, 0.36)
	skin.roughness = 0.85
	var gore := StandardMaterial3D.new()
	gore.albedo_color = color.lightened(0.1)
	gore.roughness = 0.35
	if kind == "head" or kind == "neck":
		var sphere := SphereMesh.new()
		sphere.radius = 0.12
		sphere.height = 0.26
		mesh.mesh = sphere
		var collider := SphereShape3D.new()
		collider.radius = 0.12
		shape.shape = collider
	else:
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.055
		capsule.height = length
		mesh.mesh = capsule
		var collider := CapsuleShape3D.new()
		collider.radius = 0.055
		collider.height = length
		shape.shape = collider
	mesh.material_override = skin
	body.add_child(shape)
	body.add_child(mesh)
	# A raw cut face at the severed end.
	var cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.06
	cap_mesh.bottom_radius = 0.06
	cap_mesh.height = 0.012
	cap.mesh = cap_mesh
	cap.material_override = gore
	cap.position = Vector3(0.0, length * 0.5 if kind != "head" and kind != "neck" else -0.11, 0.0)
	body.add_child(cap)
	add_child(body)
	body.global_transform = Transform3D(start.basis.orthonormalized(), start.origin)
	body.apply_central_impulse((direction * 2.2 + Vector3.UP * 1.6) * body.mass)
	body.apply_torque_impulse(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.6)
	_pieces.append({"body": body, "age": 0.0})


static func _cut_texture_get() -> ImageTexture:
	if _cut_texture == null:
		_cut_texture = _make_texture(false)
	return _cut_texture


static func _hole_texture_get() -> ImageTexture:
	if _hole_texture == null:
		_hole_texture = _make_texture(true)
	return _hole_texture


## Procedural wound mask: a ragged slash (dark core, wet rim, bruise halo) or a round entry hole.
static func _make_texture(hole: bool) -> ImageTexture:
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.15
	for y in size:
		for x in size:
			var u: float = (float(x) / float(size - 1)) * 2.0 - 1.0
			var v: float = (float(y) / float(size - 1)) * 2.0 - 1.0
			var jag: float = noise.get_noise_2d(x, y) * 0.18
			var d: float
			if hole:
				d = Vector2(u, v).length() + jag * 0.6
			else:
				var width: float = 0.22 * (1.0 - u * u) + 0.02
				d = absf(v + jag * 0.5) / maxf(width, 0.01) * 0.5 + maxf(0.0, absf(u) - 0.85) * 4.0
			var core: float = clampf(1.0 - d / 0.35, 0.0, 1.0)
			var rim: float = clampf(1.0 - absf(d - 0.45) / 0.2, 0.0, 1.0)
			var halo: float = clampf(1.0 - d, 0.0, 1.0) * 0.45
			var shade: float = lerpf(0.55, 0.12, core) # Bright wet rim, near-black depth.
			var alpha: float = clampf(maxf(core, maxf(rim * 0.9, halo)), 0.0, 1.0)
			image.set_pixel(x, y, Color(shade + rim * 0.35, shade * 0.4, shade * 0.35, alpha))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
