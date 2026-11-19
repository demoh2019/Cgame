extends Node3D
## An animated character built from the Kenney character model: tinted, scaled, and switching between
## its idle and walk animations.

const Assets = preload("res://scripts/client/assets.gd")

static var _tinted: Dictionary = {}

var animator: AnimationPlayer
var _materials: Array[StandardMaterial3D] = []
var _moving := false
var _walk_speed := 1.0
var _last_position := Vector3.INF


func setup(tint: Color, scale_factor: float, walk_speed: float = 1.0) -> void:
	var model := Assets.instance("character/character")
	model.scale = Vector3.ONE * scale_factor
	add_child(model)
	_walk_speed = walk_speed
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


func set_moving(moving: bool) -> void:
	if moving == _moving or animator == null:
		return
	_moving = moving
	var animation_name := "walk" if moving else "idle"
	if animator.has_animation(animation_name):
		animator.play(animation_name, 0.15)
		animator.speed_scale = _walk_speed if moving else 1.0


## Call each frame after the node has moved: walks when it travelled, idles otherwise.
func update_motion(delta: float) -> void:
	var here := global_position
	if _last_position != Vector3.INF and delta > 0.0:
		set_moving(here.distance_to(_last_position) / delta > 0.35)
	_last_position = here
