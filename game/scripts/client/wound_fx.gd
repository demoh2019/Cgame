extends Node3D
## Location-based gore on enemies: the bone nearest the strike gets a cut or a bullet wound
## (the skin there is opened by a shader: a real hole or gaping cut that rides that bone), blood sprays from the spot, and a heavy killing blow on a
## limb or the neck severs it — the bone collapses on the body and a bloody piece flies off.
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
		for bone in severed:
			skeleton.set_bone_pose_scale(bone, Vector3.ONE * 0.001)


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


func _init() -> void:
	_rng.randomize()


## model: the enemy's character model; origin/direction: the line of the strike in world space.
func on_hit(model: Node3D, origin: Vector3, direction: Vector3, damage: float, ranged: bool, fatal: bool, ichor: bool, weapon_id: String = "", charge: float = 0.0) -> void:
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
	var surface: Vector3 = _surface_point(skeleton, bone_at + to_line.limit_length(0.06), direction)
	var color := Color(0.32, 0.02, 0.02) if not ichor else Color(0.22, 0.06, 0.02)
	_add_wound(skeleton, bone, surface, direction, wound_shape(weapon_id, ranged, damage))
	_spray(surface, -direction, damage, color)
	# Blunt power blows and heavy swings snap arms and legs: the limb hangs at a sick angle.
	var kind: String = _limb_kind(skeleton.get_bone_name(bone))
	if not ranged and _is_blunt(weapon_id) and (charge >= 0.75 or damage >= 28.0) and (kind == "arm" or kind == "leg"):
		_break(skeleton, bone, direction)
	var heavy: bool = charge >= 0.75 or damage >= 35.0
	if not ranged and not _is_blunt(weapon_id) and (fatal or heavy) and damage >= SEVER_DAMAGE:
		var cut: int = _severable(skeleton, bone)
		if cut >= 0:
			_sever(skeleton, cut, direction, color)
	elif fatal and ranged and damage >= SEVER_DAMAGE * 1.6 and _limb_kind(skeleton.get_bone_name(bone)) == "head":
		_sever(skeleton, bone, direction, color)


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
		return {"radius": 0.016, "elongation": 1.0, "depth": 0.025}
	var w := weapon_id.to_lower()
	if w.contains("knife") or w.contains("spear") or w.contains("dagger") or w.contains("bayonet") or w.contains("shiv"):
		return {"radius": clampf(0.022 + damage * 0.0004, 0.022, 0.04), "elongation": 1.7, "depth": 0.035}
	if w.contains("club") or w.contains("hammer") or w.contains("bat") or w.contains("mace") or w.contains("pipe"):
		return {"radius": 0.016, "elongation": 2.0, "depth": 0.05}
	return {"radius": clampf(0.02 + damage * 0.0003, 0.02, 0.035), "elongation": clampf(3.0 + damage * 0.05, 3.0, 6.0), "depth": 0.03}


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
		"radius": float(shape["radius"]), "elongation": float(shape["elongation"]), "depth": float(shape["depth"])})


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
	var body := {"skeleton": skeleton, "surfaces": surfaces, "wounds": []}
	_bodies[key] = body
	return body


static func _flesh_material(source: BaseMaterial3D) -> ShaderMaterial:
	if source == null or source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return null
	var material := ShaderMaterial.new()
	material.shader = WOUND_SHADER
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
			var centres := PackedVector4Array()
			var axes := PackedVector4Array()
			var dirs := PackedVector4Array()
			for entry in world_wounds:
				var wound: Dictionary = entry[3]
				var c: Vector3 = to_local * (entry[0] as Vector3)
				var a: Vector3 = (to_local.basis * (entry[1] as Vector3)).normalized()
				var d: Vector3 = (to_local.basis * (entry[2] as Vector3)).normalized()
				centres.append(Vector4(c.x, c.y, c.z, float(wound["radius"])))
				axes.append(Vector4(a.x, a.y, a.z, float(wound["elongation"])))
				dirs.append(Vector4(d.x, d.y, d.z, float(wound["depth"])))
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
	var breaker := _breaker_of(skeleton)
	breaker.severed[bone] = true
	breaker.broken.erase(bone)
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
