extends Node3D
const CharacterShading = preload("res://scripts/client/character_shading.gd")
## An animated character. With the downloaded packs it is a Quaternius Fantasy Races character playing the
## Universal Animation Library (idle, walk, jog, sprint, attacks, chopping, harvesting, zombie walk, death);
## without them it is the small Kenney robot with its idle and walk animations.

const Assets = preload("res://scripts/client/assets.gd")
const RainGear = preload("res://scripts/client/character_rain_gear.gd")
const SkinSSS = preload("res://scripts/client/graphics_skin_scattering.gd")
const Ragdoll = preload("res://scripts/client/ragdoll.gd")
const EngineFeatures = preload("res://scripts/client/engine_features.gd")
const Anim = preload("res://scripts/client/character_anim.gd")
const AnimModifier = preload("res://scripts/client/character_anim_modifier.gd")

static var _tinted: Dictionary = {}

var animator: AnimationPlayer
var pack_mode := false
var external_anim_lod := false # True when the native AnimationLODController advances `animator`.
var _native_feet := false # True when the engine FootPlacementModifier3D plants the feet.
var _native_foot_modifier: Node = null # Cached to avoid per-frame skeleton hierarchy walks.
var _materials: Array[StandardMaterial3D] = []
var _wet_surfaces: Array[Dictionary] = [] # Live outfit/gear surfaces and their original materials.
var _wet_surface_keys: Dictionary = {}
var _wet_step: int = 0
var _skin_surfaces: Array[Dictionary] = [] # Authored opaque skin only, never clothing/eyes/hair.
var _skin_quality := -1
var _skin_renderer := ""
var _moving := false
var _walk_speed := 1.0
var _last_position := Vector3.INF
var speed := 0.0 # Measured ground speed in m/s.

# Procedural animation (see character_anim.gd).
static var _upper_cache: Dictionary = {}
var _procedural: SkeletonModifier3D
var _layer: AnimationPlayer # Upper-body-only clips over locomotion.
var _layer_left := 0.0
var _dt := 0.0
var _last_yaw := INF
var _yaw_rate := 0.0
var _lod_tier := 0
var _lod_accum := 0.0
var _status_pulse_tween: Tween
var _hit_flash_tween: Tween

# Pack mode state.
var _zombie := false
# Caller-controlled visual IK work group (0 player, 1 infected,
# 2 elite/boss, 3 future cinematic characters). No gameplay authority.
var animation_budget_group: int = 0
var _zombie_state := 0 # Zombie.State: 0 idle, 1 wander, 2 chase, 3 attack, 4 dead.
var _action_loop := ""
var _oneshot := ""
var _oneshot_left := 0.0
var _dead := false
var _crouching := false
var _riding := false
var _swimming := false
var _sex := "" # "Male" or "Female" for the clothed survivors, which can show worn gear.
var _gear_shown: Dictionary = {} # Gear slot -> item id currently drawn on the body.
var motion_matching := false # Visual-only: locomotion clip chosen by the native motion matching search.
var _mm_clip := "" # Last matched database clip ("" = not searched yet).
var _mm_frame := -1
var _mm_timer := 0.0


## `model_name` picks a character of the pack ("Orc_Male", "Elf_Female", ...); empty or an unavailable pack
## gives the Kenney robot. `scale_factor` is relative to the robot (2.0 is a person), so 2.0 is a normal size for both.
## `look_seed` picks the outfit and hair when the clothed survivors are installed (same seed, same look).
func setup(tint: Color, scale_factor: float, walk_speed: float = 1.0, model_name: String = "", zombie: bool = false, look_seed: int = 0) -> void:
	_walk_speed = walk_speed
	_zombie = zombie
	animation_budget_group = 1 if zombie else 0
	# A reused character never inherits a freed skeleton or previous leg solver.
	# Deactivate the old one before detaching its cached reference.
	if _native_foot_modifier != null and is_instance_valid(_native_foot_modifier):
		_native_foot_modifier.set("active", false)
	_native_feet = false
	_native_foot_modifier = null
	# A pooled/reconfigured model must never inherit its predecessor's IK slot.
	set_meta("aa_full_ik_retained", false)
	set_meta("aa_combat_pose_retained", false) # Pooled models cannot carry another actor's combat history.
	# One GPU batch provides soft floor contact where real shadows are disabled.
	# Register the actual live actor model, never model-template resources.
	add_to_group("aa_grounded_characters")
	set_meta("aa_contact_shadow_radius", (1.04 if zombie else 0.82) *
		clampf(scale_factor / 2.0, 0.7, 1.7))
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
	RainGear.clear_cache() # No stale material variants after leaving a client world.
	SkinSSS.clear_cache()


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
	# Strand-anisotropic hair, cloth sheen and wet eyes on High/Ultra.
	CharacterShading.enhance_model(skeleton)
	return model


func _setup_pack(tint: Color, scale_factor: float, model_name: String, look_seed: int = 0) -> void:
	pack_mode = true
	var sex := survivor_sex(model_name)
	_sex = sex
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
	_setup_procedural(model)
	_capture_skin_surfaces(model)
	apply_skin_quality(SkinSSS.current_level, SkinSSS.current_method)
	_capture_wet_surfaces(model)


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


## Register only imported skin, not a whole outfit. Keep the exact previous
## full-mesh / surface override: Performance/Balanced restore it, with no
## extra GPU skin shader pass. Called once as each actor is assembled.
func _capture_skin_surfaces(root: Node) -> void:
	if root == null:
		return
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if not SkinSSS.is_skin_mesh(instance):
			continue
		if instance.material_override is StandardMaterial3D:
			var full := instance.material_override as StandardMaterial3D
			if SkinSSS.supports(full):
				_skin_surfaces.append({"mesh": instance, "surface": -1,
					"base": full, "override": full})
			continue
		for surface in instance.mesh.get_surface_count():
			var original_override: Material = instance.get_surface_override_material(surface)
			var original: Material = original_override if original_override != null else (
				instance.mesh.surface_get_material(surface))
			if original is StandardMaterial3D and SkinSSS.supports(original as StandardMaterial3D):
				_skin_surfaces.append({"mesh": instance, "surface": surface,
					"base": original, "override": original_override})


## Preset switch only; no traversal or duplicate materials inside _process().
## Works for new characters already spawned after a previous preset switch.
func apply_skin_quality(level: int, method: String) -> void:
	if not pack_mode:
		return
	var tier: int = clampi(level, 0, 3)
	if _skin_quality == tier and _skin_renderer == method:
		return
	_skin_quality = tier
	_skin_renderer = method
	for entry in _skin_surfaces:
		var mesh_instance: MeshInstance3D = entry["mesh"]
		if not is_instance_valid(mesh_instance) or mesh_instance.is_queued_for_deletion():
			continue
		var base := entry["base"] as StandardMaterial3D
		var material: Material = SkinSSS.variant(base, tier, method) if (
				bool(SkinSSS.settings(tier, method)["enabled"])) else entry["override"]
		if int(entry["surface"]) < 0:
			mesh_instance.material_override = material
		else:
			mesh_instance.set_surface_override_material(int(entry["surface"]), material)


## Capture only opaque clothing and worn equipment. Imported skin, eyes and
## hair remain exactly as authored. Store the DRY override so exiting rain
## restores the original imported material, not a wet variant of a variant.
## Newly attached gear is discovered after set_gear(), never in _process().
func _capture_wet_surfaces(root: Node) -> void:
	if root == null:
		return
	var still_live: Array[Dictionary] = []
	for target in _wet_surfaces:
		var old: MeshInstance3D = target["mesh"]
		if is_instance_valid(old) and not old.is_queued_for_deletion():
			still_live.append(target)
		else:
			_wet_surface_keys.erase(str(target["key"]))
	_wet_surfaces = still_live
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var part_name: String = str(mesh_instance.name)
		if not (part_name.begins_with("Outfit_") or part_name.begins_with("Gear_")):
			continue
		# Respect authors' full-mesh overrides, e.g. a custom special-effect.
		if mesh_instance.material_override != null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var key: String = "%d:%d" % [mesh_instance.get_instance_id(), surface]
			if _wet_surface_keys.has(key):
				continue
			var original_override: Material = mesh_instance.get_surface_override_material(surface)
			var original: Material = original_override if original_override != null else (
				mesh_instance.mesh.surface_get_material(surface))
			if not (original is StandardMaterial3D):
				continue
			var base := original as StandardMaterial3D
			if not RainGear.supports(base):
				continue
			_wet_surface_keys[key] = true
			_wet_surfaces.append({"mesh": mesh_instance, "surface": surface,
				"base": base, "override": original_override, "key": key})
			if _wet_step > 0:
				mesh_instance.set_surface_override_material(surface,
					RainGear.variant(base, _wet_step))


## Called with a discrete weather level, never a continuously changing shader
## parameter: 0 restores dry imported PBR, 1-4 use globally cached variants.
## A no-op when the tier does not change (the common 60 FPS case).
func set_wetness_step(step: int) -> void:
	var target_step: int = clampi(step, 0, RainGear.STEPS)
	if target_step == _wet_step:
		return
	_wet_step = target_step
	for target in _wet_surfaces:
		var instance: MeshInstance3D = target["mesh"]
		if not is_instance_valid(instance) or instance.is_queued_for_deletion():
			continue
		var material: Material = target["override"] if _wet_step == 0 else (
			RainGear.variant(target["base"], _wet_step))
		instance.set_surface_override_material(int(target["surface"]), material)


func set_tint(tint: Color) -> void:
	for material in _materials:
		material.albedo_color = tint
	# SSS variants are lightweight duplicates: keep a tinted actor's visible
	# skin in sync without touching source textures or other players' skins.
	for entry in _skin_surfaces:
		var base: StandardMaterial3D = entry["base"]
		if base in _materials and _skin_quality >= 0:
			var visible_skin: StandardMaterial3D = SkinSSS.variant(
				base, _skin_quality, _skin_renderer)
			if visible_skin != null and visible_skin != base:
				visible_skin.albedo_color = tint


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
	else:
		# Same clip: ease the playback rate so crossing a speed bracket does not pop the stride.
		animator.speed_scale = Anim.smooth_rate(animator.speed_scale, speed_scale, _dt, 3.0)


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
	if _layer != null and not _riding and not _swimming and not _crouching and Anim.layerable(animation_name, _moving, _zombie):
		_play_layered(animation_name, speed_scale)
		return
	_oneshot = animation_name
	if _swing_trail != null and (animation_name.begins_with("Sword") or animation_name.begins_with("Melee")):
		_swing_trail.set("emitting", true)
	animator.play(animation_name, 0.08)
	animator.speed_scale = speed_scale
	_oneshot_left = animator.get_animation(animation_name).length / maxf(speed_scale, 0.1)


## A looping activity such as chopping; an empty name stops it.
func set_action_loop(animation_name: String) -> void:
	_action_loop = animation_name


# --- Procedural layer (see character_anim.gd) -----------------------------------------------------------------------

func _setup_procedural(model: Node3D) -> void:
	var skeleton := model.find_children("*", "Skeleton3D", true, false)
	if skeleton.is_empty():
		return
	var modifier := AnimModifier.new()
	modifier.name = "ProceduralAnim"
	modifier.body = self
	# Opt into engine-wide SkeletonModifier work-unit profiling only on
	# supported Cgame builds. The script-local stopwatch remains as fallback.
	if modifier.has_method("set_modifier_profiling_enabled"):
		modifier.use_engine_profile_timing = true
		modifier.call("set_modifier_profiling_enabled", _lod_tier == 0 and not _dead)
	(skeleton[0] as Skeleton3D).add_child(modifier)
	_procedural = modifier
	_layer = AnimationPlayer.new()
	_layer.name = "UpperBodyLayer"
	model.add_child(_layer) # Added after the base player, so its upper-body tracks win.
	_layer.add_animation_library("", AnimationLibrary.new())


## World height source `(x, z) -> y` for foot IK (the terrain's height_at).
func set_ground_source(source: Callable) -> void:
	if _procedural != null:
		_procedural.set("ground_fn", source)


func has_ground_source() -> bool:
	return _procedural != null and (_procedural.get("ground_fn") as Callable).is_valid()


## World point the head turns toward (camera or threat); Vector3.INF clears it.
func set_look_point(point: Vector3) -> void:
	if _procedural != null:
		_procedural.set("look_point", point)


## Animation LOD tier from Anim.assign_tiers: 0 full, 1 no IK/look, 2+ reduced update rate and no modifiers.
func set_anim_lod(tier: int) -> void:
	if tier == _lod_tier or animator == null or not pack_mode:
		return
	_lod_tier = tier
	var cheap := tier >= 2
	if not external_anim_lod: # The native AnimationLODController owns the update rate when present.
		var mode := AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if cheap else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		animator.callback_mode_process = mode
		if _layer != null:
			_layer.callback_mode_process = mode
	_lod_accum = 0.0
	# A preset or distance-LOD transition must not replay the time collected
	# under the previous animation rate. Native and stock paths stay aligned.
	if animator.has_method("reset_advance_budget"):
		animator.call("reset_advance_budget")
	if _layer != null and _layer.has_method("reset_advance_budget"):
		_layer.call("reset_advance_budget")
	# The native foot solver must obey the SAME visual-only IK tier as the
	# scripted modifier; otherwise it runs expensive terrain callbacks even
	# when crowd budgeting has already demoted this actor.
	if _native_foot_modifier != null and is_instance_valid(_native_foot_modifier):
		var full_native_ik: bool = tier == 0 and not _dead
		_native_foot_modifier.set("active", tier == 0 and not _dead)
		if _native_foot_modifier.has_method("set_modifier_profiling_enabled"):
			_native_foot_modifier.call("set_modifier_profiling_enabled", full_native_ik)
	if _procedural != null:
		if _procedural.has_method("set_modifier_profiling_enabled"):
			_procedural.call("set_modifier_profiling_enabled", tier == 0 and not _dead)
	if _procedural != null and not _dead:
		_procedural.set("foot_ik", tier == 0 and not _native_feet) # Native FootPlacementModifier3D wins when present.
		_procedural.set("look_at_enabled", tier == 0)
		if cheap:
			_procedural.call("reset")
		_procedural.active = not cheap


func anim_lod_tier() -> int:
	return _lod_tier


## The next frame's optional full-pose admission estimate combines the real
## script modifier duration and native FootPlacement duration when available.
## The native timer covers terrain queries + leg solving, not GPU skinning or
## core animation playback. Older engines simply report zero native samples.
func estimated_full_pose_cost_us() -> int:
	var script_us: int = int(_procedural.get("estimated_full_pose_us")) if _procedural != null else 0
	# Use native SkeletonModifier measurements only after a real completed
	# sample, not just because the method exists. Never sum both clocks
	# from the same modifier.
	if _procedural != null and _procedural.has_method("get_modifier_profile_sample_count") and \
			int(_procedural.call("get_modifier_profile_sample_count")) > 0:
		script_us = int(_procedural.call("get_modifier_estimated_update_us"))
	var native_us: int = 0
	if _native_foot_modifier != null and is_instance_valid(_native_foot_modifier):
		if _native_foot_modifier.has_method("get_modifier_profile_sample_count") and \
				int(_native_foot_modifier.call("get_modifier_profile_sample_count")) > 0:
			native_us = int(_native_foot_modifier.call("get_modifier_estimated_update_us"))
		elif _native_foot_modifier.has_method("get_estimated_process_cost_us"):
			# Older Cgame engines expose only the FootPlacement-specific clock.
			native_us = int(_native_foot_modifier.call("get_estimated_process_cost_us"))
	return clampi(maxi(script_us, 0) + maxi(native_us, 0), 0, 100000)


## Developer diagnostics: last and EMA update costs, by actual modifier.
## No scene walks, timers, or allocations are made until explicitly called.
func animation_modifier_profile() -> Dictionary:
	var result := {}
	if _procedural != null and _procedural.has_method("get_modifier_profile_sample_count"):
		result["script"] = {
			"last_us": _procedural.call("get_modifier_last_update_us"),
			"estimated_us": _procedural.call("get_modifier_estimated_update_us"),
			"samples": _procedural.call("get_modifier_profile_sample_count")
		}
	if _native_foot_modifier != null and is_instance_valid(_native_foot_modifier) and \
			_native_foot_modifier.has_method("get_modifier_profile_sample_count"):
		result["foot_placement"] = {
			"last_us": _native_foot_modifier.call("get_modifier_last_update_us"),
			"estimated_us": _native_foot_modifier.call("get_modifier_estimated_update_us"),
			"samples": _native_foot_modifier.call("get_modifier_profile_sample_count")
		}
	return result


## Turns motion-matched locomotion on (only takes effect when the native module is available at `quality`).
## Returns whether it is active. Visual only: never affects gameplay or networking.
func enable_motion_matching(quality: int) -> bool:
	motion_matching = Anim.motion_matching_available(quality)
	_mm_clip = ""
	_mm_frame = -1
	_mm_timer = 0.0
	return motion_matching


## Plays the locomotion loop picked by motion matching. Returns false (caller uses the speed-bracket state
## machine) when disabled, on cheap LOD tiers, or when the search yields nothing. Searches are throttled to
## MOTION_MATCHING_INTERVAL; between searches the last match keeps playing with a speed-matched rate.
func _play_matched_locomotion(delta: float) -> bool:
	if not motion_matching or _lod_tier >= 2:
		return false
	_mm_timer -= delta
	if _mm_timer <= 0.0 or _mm_clip == "":
		_mm_timer = Anim.MOTION_MATCHING_INTERVAL
		var found: Dictionary = Anim.match_locomotion(speed if _moving else 0.0, _yaw_rate, _mm_clip, _mm_frame)
		_mm_clip = str(found["clip"])
		_mm_frame = int(found["frame"])
	if _mm_clip == "":
		return false
	var choice: Array = Anim.locomotion_animation(_mm_clip, speed if _moving else 0.0, _zombie)
	_play(str(choice[0]), float(choice[1]))
	return true


func _track_yaw(delta: float) -> void:
	var yaw := global_rotation.y
	if _last_yaw != INF and delta > 0.0:
		_yaw_rate = lerpf(_yaw_rate, angle_difference(_last_yaw, yaw) / delta, clampf(delta * 8.0, 0.0, 1.0))
	_last_yaw = yaw


func _tick_procedural(delta: float) -> void:
	if _procedural != null:
		_procedural.set("yaw_rate", _yaw_rate)
		_procedural.set("move_speed", speed)
	if _layer_left > 0.0:
		_layer_left -= delta
		if _layer_left <= 0.0 and _oneshot == "" and _swing_trail != null:
			_swing_trail.set("emitting", false)
	var interval := Anim.lod_interval(_lod_tier)
	if interval > 0.0 and not external_anim_lod:
		if animator.has_method("advance_budgeted"):
			# The custom Godot fork handles catchup/intervals without
			# script-side per-character allocations, preserving native
			# AnimationPlayer playback and layered upper-body tracks.
			animator.call("advance_budgeted", delta, interval, 0.5)
			if _layer != null:
				_layer.call("advance_budgeted", delta, interval, 0.5)
		else:
			# Stock Godot fallback; cap long loading stalls like the native
			# path so teleporting/loading cannot fast-forward attack clips.
			_lod_accum = minf(_lod_accum + maxf(delta, 0.0), 0.5)
			if _lod_accum >= interval:
				animator.advance(_lod_accum)
				if _layer != null:
					_layer.advance(_lod_accum)
				_lod_accum = 0.0


## Plays an action clip on the upper body only; the legs keep their locomotion clip.
func _play_layered(animation_name: String, speed_scale: float) -> void:
	if not _upper_cache.has(animation_name):
		_upper_cache[animation_name] = Anim.upper_body_copy(animator.get_animation(animation_name))
	var library := _layer.get_animation_library("")
	if not library.has_animation(animation_name):
		library.add_animation(animation_name, _upper_cache[animation_name])
	if _swing_trail != null and (animation_name.begins_with("Sword") or animation_name.begins_with("Melee")):
		_swing_trail.set("emitting", true)
	_layer.play(animation_name, 0.1)
	_layer.speed_scale = speed_scale
	_layer_left = _layer.get_animation(animation_name).length / maxf(speed_scale, 0.1)


# --- Weapon in hand -------------------------------------------------------------------------------------------------

# Weapon item (tier suffix dropped) -> model held in the right hand. KayKit Fantasy Weapons Bits (CC0) and the Kenney
# blaster for the pistols. Tools held while gathering use the same table.
const HELD_MODELS := {
	"club": "kaykit:hammer_B", "spear": "kaykit:spear_A", "machete": "kaykit:sword_B", "sunder_axe": "kaykit:axe_A",
	"dagger": "kaykit:dagger_A", "sledgehammer": "kaykit:hammer_C", "restoration_staff": "kaykit:staff_A",
	"bow": "kaykit:bow_A_withString", "crossbow": "kaykit:bow_B_withString", "purifier_maul": "kaykit:hammer_A",
	"axe": "kaykit:axe_B", "pistol": "kenney:blaster", "suppressed_pistol": "kenney:blaster",
}
# Scale of each model in the hand: the kit is about twice life size (a 1.8 m sword, a 3 m spear).
const HELD_SCALES := {
	"kaykit:hammer_B": 0.5, "kaykit:spear_A": 0.62, "kaykit:sword_B": 0.46, "kaykit:axe_A": 0.6, "kaykit:dagger_A": 0.5,
	"kaykit:hammer_C": 0.7, "kaykit:staff_A": 0.62, "kaykit:bow_A_withString": 0.55, "kaykit:bow_B_withString": 0.5,
	"kaykit:hammer_A": 0.55, "kaykit:axe_B": 0.55, "kenney:blaster": 0.32,
}
static var _held_scenes: Dictionary = {}
var _held_id := ""
var _swing_trail: Node3D # Trail3D (engine) at the blade's tip, lit only while a swing plays.
var _hand: BoneAttachment3D


## The weapon family of an item id: "machete_3" -> "machete".
static func weapon_family(item_id: String) -> String:
	item_id = item_id.get_slice("+", 0)
	var parts := item_id.rsplit("_", true, 1)
	return parts[0] if parts.size() == 2 and parts[1].is_valid_int() else item_id


# Outfit pieces that show a worn item of a gear slot, by sex (the kit has no gloves; those show only in the bag).
const GEAR_PARTS := {
	"head": {"Male": "Male_Ranger_Head_Hood", "Female": "Female_Ranger_Head_Hood"},
	"cape": {"Male": "Male_Ranger_Acc_Pauldron", "Female": "Female_Ranger_Acc_Pauldrons"},
	"feet": {"Male": "Male_Ranger_Feet_Boots", "Female": "Female_Ranger_Feet"},
}


## Puts the worn hood, cloak (shoulder mantle) and boots on the survivor's body; a hood hides the hair, boots replace the
## outfit's own shoes. Only clothed survivors can show gear.
func set_gear(gear: Dictionary) -> void:
	if not pack_mode or _sex == "" or _zombie:
		return
	var skeleton := _find_skeleton()
	if skeleton == null:
		return
	var gear_changed := false
	for slot in GEAR_PARTS:
		var item_id: String = str(gear.get(slot, ""))
		if str(_gear_shown.get(slot, "")) == item_id:
			continue
		_gear_shown[slot] = item_id
		gear_changed = true
		for old in skeleton.find_children("Gear_%s*" % slot, "MeshInstance3D", false, false):
			old.queue_free()
		if item_id != "":
			var scene := load(Assets.PACKS + "outfits/%s.gltf" % GEAR_PARTS[slot][_sex]) as PackedScene
			if scene != null:
				var piece := scene.instantiate()
				for found in piece.find_children("*", "MeshInstance3D", true, false):
					var mesh_instance := found as MeshInstance3D
					mesh_instance.get_parent().remove_child(mesh_instance)
					mesh_instance.owner = null
					mesh_instance.name = "Gear_%s_%s" % [slot, mesh_instance.name]
					skeleton.add_child(mesh_instance)
					mesh_instance.skeleton = mesh_instance.get_path_to(skeleton)
				piece.free()
		# What the worn piece covers is hidden: the hair under a hood, the shoes inside boots.
		for found in skeleton.get_children():
			var instance := found as MeshInstance3D
			if instance == null:
				continue
			var name_text := String(instance.name)
			if slot == "head" and (name_text.contains("Hair") or name_text.contains("Eyebrow")) and not name_text.contains("Beard") and not name_text.begins_with("Gear_"):
				instance.visible = item_id == ""
			if slot == "feet" and name_text.begins_with("Outfit_") and name_text.contains("Feet"):
				instance.visible = item_id == ""
	if gear_changed:
		_capture_wet_surfaces(self)


## The tip of the rod in hand, or INF when there is none.
func rod_tip() -> Vector3:
	if _hand == null:
		return Vector3.INF
	var tip := _hand.find_child("Tip", true, false) as Node3D
	return tip.global_position if tip != null else Vector3.INF


## A fishing rod: a tapered pole of about two metres, held forward and up out of the fist, with a cork grip.
static func _fishing_rod() -> Node3D:
	var rod := Node3D.new()
	rod.name = "FishingRod"
	var pole := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = 0.006
	shape.bottom_radius = 0.018
	shape.height = 2.1
	shape.radial_segments = 6
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.22, 0.13)
	wood.roughness = 0.7
	shape.material = wood
	pole.mesh = shape
	pole.position = Vector3(0, 1.0, 0)
	rod.add_child(pole)
	var tip := Marker3D.new()
	tip.name = "Tip" # The line of the cast hangs from here.
	tip.position = Vector3(0, 2.05, 0)
	rod.add_child(tip)
	var grip := MeshInstance3D.new()
	var cork := CylinderMesh.new()
	cork.top_radius = 0.024
	cork.bottom_radius = 0.024
	cork.height = 0.28
	var cork_material := StandardMaterial3D.new()
	cork_material.albedo_color = Color(0.62, 0.48, 0.32)
	cork.material = cork_material
	grip.mesh = cork
	grip.position = Vector3(0, 0.05, 0)
	rod.add_child(grip)
	# Out of the fist and leaning well forward over the water (the held pose keeps the forearm upright).
	rod.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5 + 0.85), Vector3(0.0, 0.08, 0.03))
	return rod


## Shows the weapon (or tool) in the right hand; an empty or unknown id empties the hand. Cheap to call every frame.
func set_weapon(item_id: String) -> void:
	if not pack_mode or item_id == _held_id:
		return
	_held_id = item_id
	if _hand == null:
		var skeleton := _find_skeleton()
		if skeleton == null or skeleton.find_bone("hand_r") < 0:
			return
		_hand = BoneAttachment3D.new()
		_hand.bone_name = "hand_r"
		skeleton.add_child(_hand)
	for child in _hand.get_children():
		child.queue_free()
	if item_id == "fishing_rod":
		_hand.add_child(_fishing_rod()) # The kits have no rod: a thin tapered pole, built once per hand.
		_swing_trail = null
		return
	var key: String = HELD_MODELS.get(weapon_family(item_id), "")
	if key == "":
		return
	if not _held_scenes.has(key):
		var path: String = ("res://assets/models/kaykit_weapons/%s.gltf" if key.begins_with("kaykit:") else "res://assets/kenney/fps/%s.glb") % key.get_slice(":", 1)
		_held_scenes[key] = load(path) if ResourceLoader.exists(path) else null
	var scene := _held_scenes[key] as PackedScene
	if scene == null:
		return
	var held := scene.instantiate() as Node3D
	# The grip sits in the palm and the blade or shaft leaves the fist along the hand bone's +Z (forward and up at rest,
	# a ready stance); the hand bone's +Y runs along the fingers. A bow stands upright in the fist.
	var size: float = float(HELD_SCALES.get(key, 0.5))
	if key.begins_with("kenney:"):
		held.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3.ONE * size), Vector3(0.0, 0.09, 0.03))
	elif key.contains("bow"):
		held.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5).scaled(Vector3.ONE * size), Vector3(0.0, 0.08, 0.0))
	else:
		held.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3.ONE * size), Vector3(0.0, 0.08, 0.03))
	_hand.add_child(held)
	# A pale streak behind the tip of melee weapons while they swing (the fork's Trail3D).
	_swing_trail = null
	if ClassDB.class_exists("Trail3D") and key.begins_with("kaykit:") and not key.contains("bow"):
		var tip_height: float = 0.0
		for mesh_instance in held.find_children("*", "MeshInstance3D", true, false):
			tip_height = maxf(tip_height, (mesh_instance as MeshInstance3D).get_aabb().end.y)
		var trail: Node3D = ClassDB.instantiate("Trail3D")
		trail.set("limit_mode", 0) # By time.
		trail.set("lifetime", 0.1)
		trail.set("width", 0.09 / size)
		trail.set("mesh_alignment", 1) # Facing the camera: a thin streak, not a sheet.
		trail.set("material_mode", 1) # Additive.
		var fade := Gradient.new()
		fade.colors = PackedColorArray([Color(1.0, 0.97, 0.88, 0.0), Color(1.0, 0.97, 0.88, 0.55)])
		trail.set("color_gradient", fade)
		trail.set("emitting", false)
		trail.position = Vector3(0.0, tip_height * 0.85, 0.0)
		held.add_child(trail)
		_swing_trail = trail


## Hands the body to physics (zombie deaths): stops animation, builds ragdoll bodies,
## starts simulation and shoves the torso by `push` (m/s). Null when the rig has no mannequin bones.
func start_ragdoll(push: Vector3) -> PhysicalBoneSimulator3D:
	if not pack_mode:
		return null
	var skeleton := _find_skeleton()
	if skeleton == null:
		return null
	disable_foot_placement()
	var simulator := Ragdoll.build(skeleton)
	if simulator == null:
		return null
	_dead = true
	if _procedural != null:
		_procedural.call("reset")
		_procedural.active = false
	if _layer != null:
		_layer.stop()
	if animator != null:
		animator.pause() # Keep the last pose as the starting pose.
	simulator.physical_bones_start_simulation()
	for body in simulator.get_children():
		if body is PhysicalBone3D:
			(body as PhysicalBone3D).apply_central_impulse(push * (body as PhysicalBone3D).mass)
	return simulator


## Plants the feet on the terrain with the engine's FootPlacementModifier3D (two-bone leg IK, pelvis drop,
## foot-to-ground tilt). `height_at` is Callable(x, z) -> float in world space. A no-op on engine builds
## without the class (see game/docs/ENGINE_FOOT_PLACEMENT.md). Returns true when the modifier is active.
func enable_foot_placement(height_at: Callable) -> bool:
	if not pack_mode or not height_at.is_valid() or not EngineFeatures.has("FootPlacementModifier3D"):
		return false
	var skeleton := _find_skeleton()
	if skeleton == null or skeleton.find_bone("pelvis") < 0 or skeleton.find_bone("foot_l") < 0 or skeleton.find_bone("foot_r") < 0:
		return false
	var existing := skeleton.get_node_or_null("FootPlacement")
	if existing != null:
		_native_foot_modifier = existing
		_native_feet = true
		existing.set("ground_height_callback", height_at)
		if existing.has_method("set_modifier_profiling_enabled"):
			# The shared wrapper measures this whole native pass; the old
			# FootPlacement-specific clock must not run at the same time.
			existing.call("set_modifier_profiling_enabled", _lod_tier == 0 and not _dead)
			if existing.has_method("set_profiling_enabled"):
				existing.call("set_profiling_enabled", false)
		elif existing.has_method("set_profiling_enabled"):
			existing.call("set_profiling_enabled", true)
		existing.set("active", _lod_tier == 0 and not _dead)
		if _procedural != null:
			_procedural.set("foot_ik", false)
		return true
	var modifier = ClassDB.instantiate("FootPlacementModifier3D")
	if modifier == null:
		return false
	modifier.name = "FootPlacement"
	modifier.set("pelvis_bone", "pelvis")
	modifier.set("ground_height_callback", height_at)
	modifier.set("max_pelvis_offset", 0.35)
	modifier.set("max_foot_angle", deg_to_rad(35.0))
	modifier.call("add_leg", "thigh_l", "calf_l", "foot_l", 0.0)
	modifier.call("add_leg", "thigh_r", "calf_r", "foot_r", 0.0)
	# The profiler is optional on older Cgame builds. Avoid measuring on
	# projects not explicitly opting in.
	if modifier.has_method("set_modifier_profiling_enabled"):
		modifier.call("set_modifier_profiling_enabled", _lod_tier == 0 and not _dead)
	elif modifier.has_method("set_profiling_enabled"):
		modifier.call("set_profiling_enabled", true)
	skeleton.add_child(modifier)
	_native_foot_modifier = modifier as Node
	_native_feet = true
	modifier.set("active", _lod_tier == 0 and not _dead)
	if _procedural != null:
		_procedural.set("foot_ik", false) # One leg solver per skeleton.
	return true


func disable_foot_placement() -> void:
	if _native_foot_modifier != null and is_instance_valid(_native_foot_modifier):
		_native_foot_modifier.set("active", false)
		return
	var skeleton := _find_skeleton()
	if skeleton == null:
		return
	var modifier := skeleton.get_node_or_null("FootPlacement")
	if modifier != null:
		modifier.set("active", false)


func _find_skeleton() -> Skeleton3D:
	for child in get_children():
		var found: Array = child.find_children("*", "Skeleton3D", true, false)
		if not found.is_empty():
			return found[0]
	return null


## Sneaking low or riding the bike: picked up by update_motion.
func set_stance(crouching: bool, riding: bool, swimming: bool = false) -> void:
	_crouching = crouching
	_riding = riding
	_swimming = swimming


## A flinch when struck (not while already playing an action, dead, or riding).
func play_hit(heavy: bool = false, from_dir: Vector3 = Vector3.ZERO) -> void:
	if not pack_mode or _dead or _riding:
		return
	# Additive flinch on top of whatever is playing.
	if _procedural != null:
		var local_dir := global_transform.basis.inverse() * from_dir if from_dir != Vector3.ZERO else Vector3.BACK
		_procedural.call("kick", local_dir, 1.0 if heavy else 0.55)
		# Moving, acting or a light hit: the flinch alone, locomotion is not interrupted.
		if _oneshot != "" or _moving or not heavy:
			return
	elif _oneshot != "":
		return
	play_action("Hit_Knockback" if heavy else ("Hit_Chest" if randf() < 0.6 else "Hit_Head"), 1.3)


func set_dead(dead: bool) -> void:
	_dead = dead


## For zombies: the AI state from the snapshot (see Zombie.State).
func set_zombie_state(state: int) -> void:
	_zombie_state = state


## Call each frame after the node has moved: works out the speed and picks what to play.
func update_motion(delta: float) -> void:
	_dt = delta
	_track_yaw(delta)
	var here := global_position
	if _last_position != Vector3.INF and delta > 0.0:
		speed = lerpf(speed, Vector2(here.x - _last_position.x, here.z - _last_position.z).length() / delta, clampf(delta * 10.0, 0.0, 1.0))
		_moving = speed > 0.35
		if not pack_mode:
			set_moving(_moving)
	_last_position = here
	if not pack_mode or animator == null:
		return
	_tick_procedural(delta)
	if _oneshot != "":
		_oneshot_left -= delta
		if _oneshot_left > 0.0:
			return
		_oneshot = ""
		if _swing_trail != null:
			_swing_trail.set("emitting", false)
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
		elif _play_matched_locomotion(delta):
			pass # Motion matching chose the locomotion loop.
		elif _moving:
			if speed > 3.0:
				_play("Jog_Fwd_Loop", clampf(speed / 3.6, 0.6, 2.0))
			else:
				_play("Zombie_Walk_Fwd_Loop", clampf(speed / 1.1, 0.6, 2.2))
		else:
			_play("Zombie_Idle_Loop", 1.0)
		return
	if _riding:
		_play("Driving_Loop", 1.0) # Seated, hands on the handlebars.
		return
	if _swimming:
		_play("Swim_Fwd_Loop" if _moving else "Swim_Idle_Loop", 1.0)
		return
	if _crouching:
		_play("Crouch_Fwd_Loop" if _moving else "Crouch_Idle_Loop", clampf(speed / 1.2, 0.6, 1.4) if _moving else 1.0)
		return
	# Each clip plays at the rate its stride matches the ground speed (walk about 1.6 m/s, jog 4 m/s, sprint 6.5 m/s
	# at rate 1), with wide limits so slow cargo walks and fast bike-free sprints do not slide.
	if _play_matched_locomotion(delta):
		return
	if not _moving:
		_play("Idle_Loop", 1.0)
	elif speed < 2.6:
		_play("Walk_Loop", clampf(speed / 1.6, 0.45, 1.7))
	elif speed < 5.6:
		_play("Jog_Fwd_Loop", clampf(speed / 4.0, 0.6, 1.5))
	else:
		_play("Sprint_Loop", clampf(speed / 6.5, 0.7, 1.5))


## Diablo IV / Hades-style hit flash: every material of this character pops to
## a white emissive glow and fades out in ~0.14 s. Reuses the per-character
## material duplicates, so other characters are never affected.
## Subtle emission cue for a periodic status effect. A real hit always wins.
## The periodic scheduler coalesces pulses before calling this method.
func status_pulse(color: Color) -> void:
	if _materials.is_empty() or not is_inside_tree():
		return
	if _status_pulse_tween != null and _status_pulse_tween.is_running():
		return
	if _hit_flash_tween != null and _hit_flash_tween.is_running():
		return # Never reduce or recolor a genuine damage flash.
	for material in _materials:
		if material == null:
			continue
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.95
	_status_pulse_tween = create_tween()
	_status_pulse_tween.tween_method(_set_flash_energy, 0.95, 0.0, 0.22).set_ease(Tween.EASE_OUT)
	_status_pulse_tween.tween_callback(_end_flash)


func hit_flash(strength: float = 1.0) -> void:
	if _materials.is_empty():
		return
	if _status_pulse_tween != null and _status_pulse_tween.is_running():
		_status_pulse_tween.kill()
	var energy: float = 2.4 * clampf(strength, 0.3, 1.5)
	for material in _materials:
		if material == null:
			continue
		material.emission_enabled = true
		material.emission = Color(1.0, 0.96, 0.9)
		material.emission_energy_multiplier = energy
	if _hit_flash_tween != null and _hit_flash_tween.is_running():
		_hit_flash_tween.kill()
	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_method(_set_flash_energy, energy, 0.0, 0.14).set_ease(Tween.EASE_OUT)
	_hit_flash_tween.tween_callback(_end_flash)


func _set_flash_energy(value: float) -> void:
	for material in _materials:
		if material != null:
			material.emission_energy_multiplier = value


func _end_flash() -> void:
	for material in _materials:
		if material != null:
			material.emission_enabled = false
