extends Node3D
## An animated character. With the downloaded packs it is a Quaternius Fantasy Races character playing the
## Universal Animation Library (idle, walk, jog, sprint, attacks, chopping, harvesting, zombie walk, death);
## without them it is the small Kenney robot with its idle and walk animations.

const Assets = preload("res://scripts/client/assets.gd")

static var _tinted: Dictionary = {}

var animator: AnimationPlayer
var pack_mode := false
var _materials: Array[StandardMaterial3D] = []
var _moving := false
var _walk_speed := 1.0
var _last_position := Vector3.INF
var speed := 0.0 # Measured ground speed in m/s.

# Pack mode state.
var _zombie := false
var _zombie_state := 0 # Zombie.State: 0 idle, 1 wander, 2 chase, 3 attack, 4 dead.
var _action_loop := ""
var _oneshot := ""
var _oneshot_left := 0.0
var _dead := false


## `model_name` picks a character of the pack ("Orc_Male", "Elf_Female", ...); empty or an unavailable pack
## gives the Kenney robot. `scale_factor` is relative to the robot (2.0 is a person), so 2.0 is a normal size for both.
## `look_seed` picks the outfit and hair when the clothed survivors are installed (same seed, same look).
func setup(tint: Color, scale_factor: float, walk_speed: float = 1.0, model_name: String = "", zombie: bool = false, look_seed: int = 0) -> void:
	_walk_speed = walk_speed
	_zombie = zombie
	if model_name != "" and Assets.has_characters():
		_setup_pack(tint, scale_factor, model_name, look_seed)
	else:
		_setup_kenney(tint, scale_factor)


# --- Survivors: a base body cut down to its head, an outfit and a hairstyle on one skeleton ---------------------------

# Whole outfits or pieces of them, then hair. Rangers wear a hood, so no hair. The free kit's female peasant has bare
# legs, so she wears the ranger's trousers and boots. Picked by the look seed; the fantasy name only decides the sex.
const FEMALE_WORKER := ["Female_Peasant_Body", "Female_Peasant_Arms", "Female_Ranger_Legs", "Female_Ranger_Feet"]
const SURVIVOR_LOOKS := {
	"Male": [["Male_Ranger"], ["Male_Peasant", "Hair_SimpleParted"], ["Male_Peasant", "Hair_Buzzed", "Hair_Beard"],
		["Male_Peasant", "Hair_Long", "Hair_Beard"],
		["Male_Peasant_Body", "Male_Peasant_Arms", "Male_Ranger_Legs", "Male_Ranger_Feet_Boots", "Hair_Buzzed"],
		["Male_Ranger_Body", "Male_Ranger_Arms", "Male_Peasant_Legs", "Male_Peasant_Feet", "Hair_SimpleParted", "Hair_Beard"]],
	"Female": [["Female_Ranger"], FEMALE_WORKER + ["Hair_Buns"], FEMALE_WORKER + ["Hair_Long"],
		["Female_Ranger_Body", "Female_Ranger_Arms", "Female_Ranger_Legs", "Female_Ranger_Feet", "Hair_BuzzedFemale"]],
}
const ZOMBIE_LOOKS := {"Male": ["Male_Peasant"], "Female": FEMALE_WORKER}
const HEAD_BONES := ["Head", "neck_01"]
# The kit's hair texture is a pale grey meant to be coloured: dark brown, black, chestnut, auburn, dirty blond, grey.
const HAIR_COLORS := [Color(0.3, 0.2, 0.13), Color(0.12, 0.1, 0.09), Color(0.45, 0.27, 0.15), Color(0.5, 0.2, 0.1),
	Color(0.72, 0.58, 0.36), Color(0.62, 0.6, 0.57)]
static var _heads: Dictionary = {}


## Whether a pack character name should be drawn as a clothed survivor.
static func survivor_sex(model_name: String) -> String:
	if not Assets.has_survivors():
		return ""
	if model_name.ends_with("_Male"):
		return "Male"
	if model_name.ends_with("_Female"):
		return "Female"
	return ""


## The base body's skin mesh with only the triangles of the head and neck: the outfit covers the rest, and the hidden body
## would otherwise poke through the clothes. Built once per body.
static func _head_mesh(instance: MeshInstance3D) -> ArrayMesh:
	var key := instance.mesh.resource_path + "|" + String(instance.name)
	if _heads.has(key):
		return _heads[key]
	var skin := instance.skin
	var allowed := {}
	var skeleton := instance.get_node_or_null(instance.skeleton) as Skeleton3D
	for bind in skin.get_bind_count():
		var bone_name := String(skin.get_bind_name(bind))
		if bone_name == "" and skeleton != null and skin.get_bind_bone(bind) >= 0:
			bone_name = skeleton.get_bone_name(skin.get_bind_bone(bind))
		if bone_name in HEAD_BONES:
			allowed[bind] = true
	var result := ArrayMesh.new()
	for surface in instance.mesh.get_surface_count():
		var arrays: Array = instance.mesh.surface_get_arrays(surface)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var per_vertex: int = bones.size() / maxi((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 1)
		var kept := PackedInt32Array()
		for t in range(0, indices.size(), 3):
			var keep := true
			for k in 3:
				var v: int = indices[t + k]
				var best := 0
				for w in range(1, per_vertex):
					if weights[v * per_vertex + w] > weights[v * per_vertex + best]:
						best = w
				if not allowed.has(bones[v * per_vertex + best]):
					keep = false
					break
			if keep:
				kept.append_array([indices[t], indices[t + 1], indices[t + 2]])
		if kept.is_empty():
			continue
		arrays[Mesh.ARRAY_INDEX] = kept
		for custom in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			arrays[custom] = null # Extra exporter channels the shader never reads; they would need their own format flags.
		var flags: int = Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per_vertex == 8 else 0
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		result.surface_set_material(result.get_surface_count() - 1, instance.mesh.surface_get_material(surface))
	_heads[key] = result
	return result


static var _templates: Dictionary = {}


## Frees the cached survivor templates (they live outside the tree); the client calls it when it quits.
static func clear_templates() -> void:
	for template in _templates.values():
		(template as Node).free()
	_templates.clear()


func _setup_survivor(tint: Color, scale_factor: float, sex: String, look_seed: int) -> Node3D:
	var looks: Array = SURVIVOR_LOOKS[sex]
	var look_index: int = posmod(look_seed, looks.size())
	var hair_index: int = posmod(look_seed * 7 + 3, HAIR_COLORS.size())
	var key := "%s|%d|%d|%s" % [sex, look_index, hair_index, _zombie]
	if not _templates.has(key):
		_templates[key] = _build_survivor(sex, ZOMBIE_LOOKS[sex] if _zombie else looks[look_index],
			Color(0.35, 0.36, 0.3) if _zombie else HAIR_COLORS[hair_index])
	# Copying an assembled template is about ten times cheaper than assembling: a horde can stream in without a hitch.
	var model := (_templates[key] as Node3D).duplicate() as Node3D
	if _zombie:
		# Bare skin (the hands) takes the zombie tint, per zombie, so it flushes with the rest of the skin (alert, stagger).
		for found in model.find_children("Outfit_*", "MeshInstance3D", true, false):
			var instance := found as MeshInstance3D
			for surface in instance.mesh.get_surface_count():
				var base := instance.mesh.surface_get_material(surface) as StandardMaterial3D
				if base != null and (base.resource_name.begins_with("MI_Regular") or base.resource_name.begins_with("MI_Superhero")):
					var skin := base.duplicate() as StandardMaterial3D
					skin.albedo_color = tint
					instance.set_surface_override_material(surface, skin)
					_materials.append(skin)
	model.scale = Vector3.ONE * (scale_factor / 2.0)
	return model


## A base body cut down to its head, with the outfit pieces and hair moved onto its skeleton. Kept as a template.
static func _build_survivor(sex: String, look: Array, hair_color: Color) -> Node3D:
	var model := (load(Assets.PACKS + "outfits/Superhero_%s_FullBody.gltf" % sex) as PackedScene).instantiate() as Node3D
	# A plain node tree, not an instance of the glTF scene: duplicate() would otherwise re-instance the file and lose the
	# pieces added below.
	model.scene_file_path = ""
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for found in skeleton.get_children():
		var body := found as MeshInstance3D
		if body != null and String(body.name).to_lower().begins_with("superhero"):
			body.mesh = _head_mesh(body)
			body.set_meta("skin", true) # Takes the skin tint in _setup_pack.
	var zombie := hair_color == Color(0.35, 0.36, 0.3)
	for part in look:
		var scene := load(Assets.PACKS + "outfits/" + String(part) + ".gltf") as PackedScene
		if scene == null:
			continue
		var piece := scene.instantiate()
		for found in piece.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := found as MeshInstance3D
			mesh_instance.get_parent().remove_child(mesh_instance)
			mesh_instance.owner = null
			# The outfit's own "..._Body" piece is clothing, not skin to tint.
			mesh_instance.name = "Outfit_" + String(mesh_instance.name).replace("_Body", "_Torso")
			skeleton.add_child(mesh_instance)
			mesh_instance.owner = model
			mesh_instance.skeleton = mesh_instance.get_path_to(skeleton)
			if zombie:
				# Torn, filthy clothes: darker and a sickly cast.
				for surface in mesh_instance.mesh.get_surface_count():
					var base := mesh_instance.mesh.surface_get_material(surface) as StandardMaterial3D
					if base != null:
						var dirty := base.duplicate() as StandardMaterial3D
						dirty.albedo_color = Color(0.55, 0.52, 0.42)
						mesh_instance.set_surface_override_material(surface, dirty)
		piece.free()
	# Hair and eyebrows share one material: dye it.
	for found in skeleton.get_children():
		var instance := found as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		var base := instance.mesh.surface_get_material(0) as BaseMaterial3D
		if base != null and base.resource_name.begins_with("MI_Hair"):
			var dyed := base.duplicate() as BaseMaterial3D
			dyed.albedo_color = hair_color
			instance.set_surface_override_material(0, dyed)
	return model


func _setup_pack(tint: Color, scale_factor: float, model_name: String, look_seed: int = 0) -> void:
	pack_mode = true
	var sex := survivor_sex(model_name)
	var model: Node3D
	if sex != "" and not (_zombie and model_name == "Orc_Female"):
		model = _setup_survivor(tint, scale_factor, sex, look_seed)
	else:
		model = (load(Assets.PACKS + "characters/" + model_name + ".glb") as PackedScene).instantiate() as Node3D
	model.scale = Vector3.ONE * (scale_factor / 2.0)
	add_child(model)
	# Only the skin takes the tint, so eyes and hair keep their look.
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh_instance as MeshInstance3D
		if (String(instance.name).ends_with("_Body") or instance.has_meta("skin")) and tint != Color.WHITE:
			var base := instance.mesh.surface_get_material(0)
			if base is StandardMaterial3D:
				var material := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
				material.albedo_color = tint
				instance.material_override = material
				_materials.append(material)
	animator = AnimationPlayer.new()
	model.add_child(animator) # Its root is the model, where "Armature/Skeleton3D" lives.
	animator.add_animation_library("", Assets.animation_library())
	animator.animation_finished.connect(_on_animation_finished)
	_play("Zombie_Idle_Loop" if _zombie else "Idle_Loop", 1.0)


func _setup_kenney(tint: Color, scale_factor: float) -> void:
	var model := Assets.instance("character/character")
	model.scale = Vector3.ONE * scale_factor
	add_child(model)
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh_instance as MeshInstance3D
		var base := instance.mesh.surface_get_material(0)
		if base is StandardMaterial3D:
			var material := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
			material.albedo_color = tint
			instance.material_override = material
			_materials.append(material)
	var found := model.find_children("*", "AnimationPlayer", true, false)
	if not found.is_empty():
		animator = found[0]
		for animation_name in ["idle", "walk"]:
			if animator.has_animation(animation_name):
				animator.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
		animator.play("idle")


func set_tint(tint: Color) -> void:
	for material in _materials:
		material.albedo_color = tint


# --- Kenney robot -------------------------------------------------------------------------------------------------

func set_moving(moving: bool) -> void:
	if pack_mode or moving == _moving or animator == null:
		return
	_moving = moving
	var animation_name := "walk" if moving else "idle"
	if animator.has_animation(animation_name):
		animator.play(animation_name, 0.15)
		animator.speed_scale = _walk_speed if moving else 1.0


# --- Pack characters ----------------------------------------------------------------------------------------------

func _play(animation_name: String, speed_scale: float) -> void:
	if animator == null or not animator.has_animation(animation_name):
		return
	# A play() issued before the model entered the tree can leave the right name set but nothing running.
	if animator.current_animation != animation_name or not animator.is_playing():
		animator.play(animation_name, 0.2)
	animator.speed_scale = speed_scale


func _on_animation_finished(finished: StringName) -> void:
	if String(finished) == _oneshot:
		_oneshot = ""


## For people who stand about (settlement survivors): loops one animation forever, whatever its name says.
func play_fixed(animation_name: String) -> void:
	if not pack_mode or animator == null:
		return
	var chosen: String = animation_name if animator.has_animation(animation_name) else "Idle_Loop"
	if not animator.has_animation(chosen):
		return
	animator.get_animation(chosen).loop_mode = Animation.LOOP_LINEAR
	animator.play(chosen)
	# Not all standing about is in step: start each person somewhere else in the clip.
	animator.seek(randf() * animator.get_animation(chosen).length, true)


## A single action (a swing, a shot) that plays over the movement and then hands control back.
func play_action(animation_name: String, speed_scale: float = 1.0) -> void:
	if not pack_mode or animator == null or _dead or not animator.has_animation(animation_name):
		return
	_oneshot = animation_name
	animator.play(animation_name, 0.08)
	animator.speed_scale = speed_scale
	_oneshot_left = animator.get_animation(animation_name).length / maxf(speed_scale, 0.1)


## A looping activity such as chopping; an empty name stops it.
func set_action_loop(animation_name: String) -> void:
	_action_loop = animation_name


func set_dead(dead: bool) -> void:
	_dead = dead


## For zombies: the AI state from the snapshot (see Zombie.State).
func set_zombie_state(state: int) -> void:
	_zombie_state = state


## Call each frame after the node has moved: works out the speed and picks what to play.
func update_motion(delta: float) -> void:
	var here := global_position
	if _last_position != Vector3.INF and delta > 0.0:
		speed = lerpf(speed, Vector2(here.x - _last_position.x, here.z - _last_position.z).length() / delta, clampf(delta * 10.0, 0.0, 1.0))
		_moving = speed > 0.35
		if not pack_mode:
			set_moving(_moving)
	_last_position = here
	if not pack_mode or animator == null:
		return
	if _oneshot != "":
		_oneshot_left -= delta
		if _oneshot_left > 0.0:
			return
		_oneshot = ""
	if _dead:
		if animator.current_animation != "Death01":
			animator.play("Death01", 0.1)
			animator.speed_scale = 1.0
		return
	if _action_loop != "":
		_play(_action_loop, 1.0)
		return
	if _zombie:
		if _zombie_state == 3:
			_play("Zombie_Scratch", 1.0)
		elif _moving:
			if speed > 3.0:
				_play("Jog_Fwd_Loop", clampf(speed / 3.6, 0.6, 2.0))
			else:
				_play("Zombie_Walk_Fwd_Loop", clampf(speed / 1.1, 0.6, 2.2))
		else:
			_play("Zombie_Idle_Loop", 1.0)
		return
	if not _moving:
		_play("Idle_Loop", 1.0)
	elif speed < 2.2:
		_play("Walk_Loop", clampf(speed / 1.5, 0.6, 1.5))
	elif speed < 5.4:
		_play("Jog_Fwd_Loop", clampf(speed / 3.6, 0.7, 1.6))
	else:
		_play("Sprint_Loop", clampf(speed / 6.5, 0.8, 1.4))
