@tool
extends Node3D
class_name HLODCluster3D
## A distance-switched proxy for static MeshInstance3D descendants.
## Only rendered geometry is switched; physics, collision and scripts remain active.

@export_range(1.0, 100000.0, 1.0, "or_greater") var switch_distance := 60.0
@export_range(0.0, 10000.0, 0.5) var hysteresis := 5.0
@export_range(0.01, 10.0, 0.01) var check_interval := 0.1
@export_range(3, 250000, 1) var vertex_budget := 250000
@export_enum("Merged Geometry", "Bounds Proxy") var proxy_mode: int = 0

@export_tool_button("Build HLOD Proxy") var build_action := build_proxy
@export_tool_button("Clear HLOD Proxy") var clear_action := clear_proxy

const PROXY_NAME := HLODMeshBuilder.PROXY_NAME

var _is_far := false
var _elapsed := 0.0
var _sources: Array[MeshInstance3D] = []
var _original_visibility: Dictionary = {}


func _ready() -> void:
	set_process(not Engine.is_editor_hint())
	var proxy := get_proxy()
	if proxy != null:
		proxy.visible = false


func _exit_tree() -> void:
	_set_far(false)


func get_proxy() -> MeshInstance3D:
	return get_node_or_null(NodePath(PROXY_NAME)) as MeshInstance3D


func get_proxy_surface_count() -> int:
	var proxy := get_proxy()
	if proxy == null or proxy.mesh == null:
		return 0
	return proxy.mesh.get_surface_count()


func get_proxy_vertex_count() -> int:
	var proxy := get_proxy()
	if proxy == null or proxy.mesh == null:
		return 0
	var count := 0
	for surface in proxy.mesh.get_surface_count():
		count += proxy.mesh.surface_get_array_len(surface)
	return count


func is_using_proxy() -> bool:
	return _is_far


func build_proxy() -> bool:
	_set_far(false)
	var result: Dictionary = HLODMeshBuilder.build(self, vertex_budget, proxy_mode == 1)
	if not result["ok"]:
		push_warning("HLOD Builder: %s" % result["error"])
		return false

	var proxy := get_proxy()
	if proxy == null:
		proxy = MeshInstance3D.new()
		proxy.name = PROXY_NAME
		add_child(proxy)
		if Engine.is_editor_hint() and get_tree() != null:
			var edited_root := get_tree().edited_scene_root
			if edited_root != null and (edited_root == self or edited_root.is_ancestor_of(self)):
				proxy.owner = edited_root
	proxy.mesh = result["mesh"]
	proxy.visible = false
	return true


func clear_proxy() -> void:
	_set_far(false)
	var proxy := get_proxy()
	if proxy != null:
		remove_child(proxy)
		proxy.queue_free()


func _set_far(far: bool) -> void:
	if far == _is_far:
		return
	var proxy := get_proxy()
	if far and proxy == null:
		return
	if far:
		_sources = HLODMeshBuilder.get_sources(self)
		_original_visibility.clear()
		for source in _sources:
			_original_visibility[source.get_instance_id()] = source.visible
			source.visible = false
	else:
		for source in _sources:
			if is_instance_valid(source) and _original_visibility.has(source.get_instance_id()):
				source.visible = bool(_original_visibility[source.get_instance_id()])
		_sources.clear()
		_original_visibility.clear()
	_is_far = far
	if proxy != null:
		proxy.visible = far


func update_for_camera_position(camera_position: Vector3) -> void:
	# Public deterministic entry point for tests and manually controlled cameras.
	if get_proxy() == null:
		_set_far(false)
		return
	var distance: float = camera_position.distance_to(global_position)
	var threshold := switch_distance - hysteresis if _is_far else switch_distance + hysteresis
	_set_far(distance > maxf(threshold, 0.0))


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_elapsed += delta
	if _elapsed < check_interval:
		return
	_elapsed = 0.0
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		update_for_camera_position(camera.global_position)
	else:
		_set_far(false)
