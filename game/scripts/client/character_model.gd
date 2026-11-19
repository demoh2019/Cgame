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
func setup(tint: Color, scale_factor: float, walk_speed: float = 1.0, model_name: String = "", zombie: bool = false) -> void:
	_walk_speed = walk_speed
	_zombie = zombie
	if model_name != "" and Assets.has_characters():
		_setup_pack(tint, scale_factor, model_name)
	else:
		_setup_kenney(tint, scale_factor)


func _setup_pack(tint: Color, scale_factor: float, model_name: String) -> void:
	pack_mode = true
	var model := (load(Assets.PACKS + "characters/" + model_name + ".glb") as PackedScene).instantiate() as Node3D
	model.scale = Vector3.ONE * (scale_factor / 2.0)
	add_child(model)
	# Only the skin takes the tint, so eyes and hair keep their look.
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh_instance as MeshInstance3D
		if String(instance.name).ends_with("_Body") and tint != Color.WHITE:
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
