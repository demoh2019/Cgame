extends RefCounted
## Impostor LOD, character hair/cloth/eye shading, VRAM budget, shader warm-up, lens distortion.

const ImpostorBaker = preload("res://scripts/client/impostor_baker.gd")
const ImpostorField = preload("res://scripts/client/impostor_field.gd")
const CharacterShading = preload("res://scripts/client/character_shading.gd")
const VramBudget = preload("res://scripts/client/graphics_vram_budget.gd")
const ShaderWarmup = preload("res://scripts/client/shader_warmup.gd")
const GraphicsLens = preload("res://scripts/client/graphics_lens.gd")


func run(t) -> void:
	t.current = "impostors"
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 4.0, 2.0)
	var frame: Vector2 = ImpostorBaker.frame_size(box)
	t.check(frame.x >= 4.0, "bake extent covers the tallest side")
	t.near(frame.y, 0.0, 0.001, "vertical center follows the mesh bounds")
	t.check(ImpostorBaker.material_for(box, ImageTexture.new()).shader != null, "impostor material has the shader")
	ImpostorField.configure(0)
	var parent := Node3D.new()
	var transforms: Array[Transform3D] = [Transform3D(Basis(), Vector3(1, 0, 1)), Transform3D(Basis(), Vector3(9, 0, 4))]
	t.eq(ImpostorField.add(parent, box, transforms, 60.0), null, "Performance draws no impostors")
	ImpostorField.configure(2)
	var field: MultiMeshInstance3D = ImpostorField.add(parent, box, transforms, 60.0)
	t.check(field != null, "High builds an impostor field")
	t.eq(field.multimesh.instance_count, 2, "one impostor per placement")
	t.near(field.visibility_range_begin, 60.0, 0.001, "impostors start where meshes end")
	t.near(field.visibility_range_end, 132.0, 0.001, "impostors reach 2.2x further")
	t.check(not field.visible, "hidden until its atlas is baked")
	parent.free()

	t.current = "character shading"
	t.eq(CharacterShading.kind_of("MI_Hair_Long"), "hair", "hair material")
	t.eq(CharacterShading.kind_of("M_EyeBall"), "eye", "eye material")
	t.eq(CharacterShading.kind_of("MI_Regular_Skin"), "skin", "skin left to SSS")
	t.eq(CharacterShading.kind_of("MI_Jacket"), "cloth", "everything else is cloth")
	var hair := StandardMaterial3D.new()
	t.check(CharacterShading.enhance(hair, "hair", 3), "hair enhanced on Ultra")
	t.check(hair.anisotropy_enabled and hair.rim_enabled, "hair is anisotropic with rim")
	var eye := StandardMaterial3D.new()
	CharacterShading.enhance(eye, "eye", 2)
	t.check(eye.clearcoat_enabled, "eyes get a clearcoat cornea")
	var cloth := StandardMaterial3D.new()
	t.check(not CharacterShading.enhance(cloth, "cloth", 1), "Balanced keeps plain PBR")
	CharacterShading.enhance(cloth, "cloth", 3)
	t.check(cloth.rim_enabled and cloth.roughness >= 0.75, "cloth gets sheen and stays rough")
	var root := Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var shared := StandardMaterial3D.new()
	shared.resource_name = "MI_Hair_Short"
	mesh.material = shared
	mesh_instance.mesh = mesh
	root.add_child(mesh_instance)
	t.eq(CharacterShading.enhance_model(root, 3), 1, "model surfaces enhanced")
	t.check(not shared.anisotropy_enabled, "shared imported material is not mutated")
	root.free()

	t.current = "vram budget"
	var guard := VramBudget.new()
	var heavy: float = VramBudget.budget_bytes(2) * 0.95
	t.check(not guard.sample(heavy, 2, 1.0), "one second of pressure is tolerated")
	t.check(guard.sample(heavy, 2, 1.5), "sustained pressure steps down")
	t.check(not guard.sample(heavy, 0, 5.0), "nothing below Performance")
	t.check(not VramBudget.upgrade_allowed(VramBudget.budget_bytes(3), 2), "no upgrade near the next budget")

	t.current = "shader warm-up and lens"
	var paths: PackedStringArray = ShaderWarmup.shader_paths()
	t.check(paths.has("res://assets/shaders/impostor.gdshader"), "warm-up finds game shaders")
	t.check(ShaderWarmup.spatial_shaders().size() >= 10, "spatial shaders are collected")
	t.eq(ShaderWarmup.start(null), null, "no camera, no warm-up")
	t.eq(GraphicsLens.distortion(1, "forward_plus"), 0.0, "Balanced has no distortion")
	t.check(GraphicsLens.distortion(3, "forward_plus") > 0.0, "Ultra has subtle distortion")
