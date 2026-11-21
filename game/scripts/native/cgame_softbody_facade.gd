extends RefCounted
## Single entry point for cloth, rope and hair simulation. Uses the native `cgame_softbody`
## engine module (CgameXPBDCloth, CgameXPBDRope, CgameHairStrands, ClothInstance3D) when the
## engine was built with it, and otherwise falls back to the reference GDScript implementations
## in the game project. Both back ends expose the same API, so callers never branch on them.
##
## Native-only extras: CgameXPBDCloth.drive(), CgameHairStrands.build_ribbon_mesh() and the
## ClothInstance3D node. The helpers below degrade gracefully when they are unavailable.

const CLOTH_SCRIPT := "res://scripts/shared/xpbd_cloth.gd"
const ROPE_SCRIPT := "res://scripts/shared/xpbd_rope.gd"
const HAIR_SCRIPT := "res://scripts/client/hair_strands.gd"


static func is_native() -> bool:
	return ClassDB.class_exists("CgameXPBDCloth") \
		and ClassDB.class_exists("CgameXPBDRope") \
		and ClassDB.class_exists("CgameHairStrands")


static func make_cloth() -> RefCounted:
	if ClassDB.class_exists("CgameXPBDCloth"):
		return ClassDB.instantiate("CgameXPBDCloth")
	return _from_script(CLOTH_SCRIPT)


static func make_rope() -> RefCounted:
	if ClassDB.class_exists("CgameXPBDRope"):
		return ClassDB.instantiate("CgameXPBDRope")
	return _from_script(ROPE_SCRIPT)


static func make_hair() -> RefCounted:
	if ClassDB.class_exists("CgameHairStrands"):
		return ClassDB.instantiate("CgameHairStrands")
	return _from_script(HAIR_SCRIPT)


## Creates a cloth grid (see CgameXPBDCloth.setup_grid) and returns it.
static func make_cloth_grid(width_cells: int, height_cells: int, spacing: float, origin: Transform3D, particle_mass: float = 1.0) -> RefCounted:
	var cloth := make_cloth()
	if cloth != null:
		cloth.setup_grid(width_cells, height_cells, spacing, origin, particle_mass)
	return cloth


## Creates a ClothInstance3D that steps and renders `cloth`, optionally following `skeleton`
## bones given as { particle_index: bone_name } (or [bone_name, local_offset]). Returns null
## when the native node is unavailable; use cloth.build_mesh() with your own MeshInstance3D and
## call cloth.step() yourself in that case (see update_fallback_mesh).
static func make_cloth_node(cloth: RefCounted, skeleton: Skeleton3D = null, bone_map: Dictionary = {}) -> Node3D:
	if not ClassDB.class_exists("ClothInstance3D"):
		return null
	var node: Node3D = ClassDB.instantiate("ClothInstance3D")
	node.set_cloth(cloth)
	if skeleton != null:
		# The skeleton path is resolved by bind_skeleton() once both nodes are in the tree.
		node.set_bone_attachments(bone_map)
	return node


## Binds a skeleton to a node returned by make_cloth_node once it is inside the scene tree.
static func bind_skeleton(node: Node3D, skeleton: Skeleton3D) -> void:
	if node == null or skeleton == null or not node.is_inside_tree():
		return
	node.set("cloth_skeleton_path", node.get_path_to(skeleton))


## Pure-GDScript fallback: rebuilds `mesh_instance.mesh` from the cloth. Use only when
## make_cloth_node() returned null.
static func update_fallback_mesh(cloth: RefCounted, mesh_instance: MeshInstance3D) -> void:
	if cloth == null or mesh_instance == null:
		return
	mesh_instance.mesh = cloth.build_mesh()


## Hair render ribbons: native single-pass generation when available, else render_strands +
## build_mesh.
static func build_hair_mesh(hair: RefCounted, per_guide: int, seed_value: int, width: float) -> ArrayMesh:
	if hair.has_method("build_ribbon_mesh"):
		return hair.build_ribbon_mesh(per_guide, seed_value, width)
	return hair.build_mesh(hair.render_strands(per_guide, seed_value), width)


## Hangs a particle at the end of a callable/position for either back end. Native cloth gets the
## cheaper drive(); the GDScript cloth gets pin() each call.
static func move_anchor(cloth: RefCounted, index: int, world_pos: Vector3) -> void:
	if cloth.has_method("drive"):
		cloth.drive(index, world_pos)
	else:
		cloth.pin(index, world_pos)


static func _from_script(path: String) -> RefCounted:
	if not ResourceLoader.exists(path):
		push_error("CgameSoftbodyFacade: native module missing and fallback script not found: %s" % path)
		return null
	var script: GDScript = load(path)
	return script.new()
