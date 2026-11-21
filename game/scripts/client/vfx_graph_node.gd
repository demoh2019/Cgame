extends Node3D
## Renders a VfxGraph system: one MultiMeshInstance3D (billboard quads) per emitter.
## Particles are simulated in this node's local space. See vfx_graph.gd for the asset format.

const VfxGraph = preload("res://scripts/client/vfx_graph.gd")

signal finished

## Free the node once every emitter has finished and no particles remain.
@export var one_shot: bool = false
## Max live particles across all emitters of this node (-1 = unlimited).
@export var budget_particles: int = -1
@export var time_scale: float = 1.0

var system: Dictionary = {}
var _renderers: Array = []
var _done: bool = false


class Renderer extends RefCounted:
	var emitter: VfxGraph.Emitter
	var instance: MultiMeshInstance3D
	var multimesh: MultiMesh
	var buf: PackedFloat32Array = PackedFloat32Array()

	func upload() -> void:
		var n: int = emitter.count
		var o: int = 0
		for i in n:
			var p: Vector3 = emitter.pos[i]
			var s: float = emitter.size[i]
			var c: Color = emitter.col[i]
			buf[o] = s
			buf[o + 1] = 0.0
			buf[o + 2] = 0.0
			buf[o + 3] = p.x
			buf[o + 4] = 0.0
			buf[o + 5] = s
			buf[o + 6] = 0.0
			buf[o + 7] = p.y
			buf[o + 8] = 0.0
			buf[o + 9] = 0.0
			buf[o + 10] = s
			buf[o + 11] = p.z
			buf[o + 12] = c.r
			buf[o + 13] = c.g
			buf[o + 14] = c.b
			buf[o + 15] = c.a
			o += 16
		multimesh.buffer = buf
		multimesh.visible_instance_count = n


func setup(asset: Dictionary, seed_value: int) -> void:
	_clear()
	_done = false
	system = VfxGraph.create_system(asset, seed_value)
	var defs: Dictionary = asset.get("emitters", {})
	for key in system["order"]:
		var em: VfxGraph.Emitter = VfxGraph.get_emitter(system, str(key))
		var def: Dictionary = defs[key]
		var r := Renderer.new()
		r.emitter = em
		r.buf.resize(em.cap * 16)
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		if str(def.get("blend", "alpha")) == "add":
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		var tex: Variant = def.get("texture", null)
		if tex is Texture2D:
			mat.albedo_texture = tex
		quad.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.instance_count = em.cap
		mm.mesh = quad
		mm.visible_instance_count = 0
		var half: float = float(def.get("bounds", 100.0))
		mm.custom_aabb = AABB(Vector3(-half, -half, -half), Vector3(half, half, half) * 2.0)
		var inst := MultiMeshInstance3D.new()
		inst.name = str(key)
		inst.multimesh = mm
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(inst)
		r.instance = inst
		r.multimesh = mm
		_renderers.append(r)


func _clear() -> void:
	for r: Renderer in _renderers:
		if is_instance_valid(r.instance):
			r.instance.queue_free() if r.instance.is_inside_tree() else r.instance.free()
	_renderers.clear()
	system = {}


func _process(delta: float) -> void:
	step(delta * time_scale)


## Advance the simulation and refresh the MultiMeshes (also used directly by tests).
func step(delta: float) -> void:
	if system.is_empty() or _done:
		return
	if budget_particles >= 0:
		VfxGraph.set_budget(system, maxi(budget_particles - VfxGraph.total_particles(system), 0))
	else:
		VfxGraph.set_budget(system, -1)
	VfxGraph.tick(system, delta)
	for r: Renderer in _renderers:
		r.upload()
	if one_shot and VfxGraph.is_finished(system):
		_done = true
		finished.emit()
		if is_inside_tree():
			queue_free()


func particle_count() -> int:
	return VfxGraph.total_particles(system) if not system.is_empty() else 0


func is_finished() -> bool:
	return _done


func profile() -> Dictionary:
	return system.get("profile", {})
