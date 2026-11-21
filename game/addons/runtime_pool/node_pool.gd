class_name RuntimeNodePool
extends Node
## Generic PackedScene reuse for Cgame/Godot projects.
## Optional callbacks: on_pool_created(), on_pool_acquired(pool), on_pool_released().

signal instance_acquired(instance: Node)
signal instance_released(instance: Node)
signal capacity_exhausted()

@export var template: PackedScene
@export_range(0, 4096, 1) var prewarm_count: int = 0
@export_range(0, 4096, 1) var max_idle: int = 32
## Zero means no active-instance cap.
@export_range(0, 4096, 1) var max_active: int = 0
@export var prewarm_on_ready: bool = true

var _idle: Array[Node] = []
var _active: Dictionary = {} # instance id -> WeakRef
var _created_total: int = 0
var _reused_total: int = 0
var _released_total: int = 0
var _disposed_total: int = 0
var _rejected_total: int = 0
var _peak_active: int = 0


func _ready() -> void:
	if prewarm_on_ready:
		prewarm(prewarm_count)


## Allocate idle nodes once, clamped by max_idle.
func prewarm(target: int) -> int:
	_prune_invalid()
	if template == null:
		return 0
	var desired: int = mini(maxi(target, 0), max_idle)
	var added: int = 0
	while _idle.size() < desired:
		var instance: Node = _new_instance()
		if instance == null:
			break
		_idle.append(instance)
		added += 1
	return added



## Niagara-inspired frame-sliced resident pool maintenance. Positive return
## means created, negative means idle nodes freed. Target includes checked-out
## objects; no active VFX is removed and every call is bounded to 64 changes.
func maintain_residency(target_total: int, max_changes: int = 2) -> int:
	if target_total < 0 or target_total > 4096 or max_changes < 0 or max_changes > 64 or max_changes == 0:
		return 0
	_prune_invalid()
	var current: int = _active.size() + _idle.size()
	if current < target_total:
		if template == null:
			return 0
		var to_create: int = mini(mini(target_total - current, max_changes), max_idle - _idle.size())
		var created: int = 0
		for i in to_create:
			var instance: Node = _new_instance()
			if instance == null:
				break
			_idle.append(instance)
			created += 1
		return created
	if current > target_total:
		var to_free: int = mini(mini(current - target_total, max_changes), _idle.size())
		var freed: int = 0
		for i in to_free:
			var instance: Node = _idle.pop_back()
			if is_instance_valid(instance) and not instance.is_queued_for_deletion():
				instance.free()
				_disposed_total += 1
				freed += 1
		return -freed
	return 0


## Acquire one node under a gameplay parent; null when unavailable.
func acquire(parent_node: Node) -> Node:
	if not is_instance_valid(parent_node) or parent_node.is_queued_for_deletion() or template == null:
		return null
	_prune_invalid()
	if max_active > 0 and _active.size() >= max_active:
		_rejected_total += 1
		capacity_exhausted.emit()
		return null
	var instance: Node = null
	if not _idle.is_empty():
		instance = _idle.pop_back()
		_reused_total += 1
	else:
		instance = _new_instance()
	if instance == null:
		return null
	parent_node.add_child(instance)
	_active[instance.get_instance_id()] = weakref(instance)
	_peak_active = maxi(_peak_active, _active.size())
	if instance.has_method("on_pool_acquired"):
		instance.call("on_pool_acquired", self)
	instance_acquired.emit(instance)
	return instance


## Returns false for foreign/double returns and destroyed nodes.
func release(instance: Node) -> bool:
	if not is_instance_valid(instance) or instance.is_queued_for_deletion():
		return false
	var id: int = instance.get_instance_id()
	if not _active.has(id):
		return false
	var ref: WeakRef = _active[id]
	if ref.get_ref() != instance:
		return false
	_active.erase(id)
	if instance.has_method("on_pool_released"):
		instance.call("on_pool_released")
	if is_instance_valid(instance) and instance.get_parent() != null:
		instance.get_parent().remove_child(instance)
	_released_total += 1
	if is_instance_valid(instance) and not instance.is_queued_for_deletion():
		if _idle.size() < max_idle:
			_idle.append(instance)
		else:
			instance.queue_free()
			_disposed_total += 1
	instance_released.emit(instance if is_instance_valid(instance) else null)
	return true


## Use in Area/Body physics callbacks to avoid reparenting during a signal.
func release_deferred(instance: Node) -> void:
	call_deferred("release", instance)


func clear_idle() -> void:
	for instance in _idle:
		if is_instance_valid(instance):
			instance.free()
			_disposed_total += 1
	_idle.clear()


func get_active_count() -> int:
	_prune_invalid()
	return _active.size()


func get_idle_count() -> int:
	_prune_invalid()
	return _idle.size()


func get_stats() -> Dictionary:
	_prune_invalid()
	return {
		"active": _active.size(),
		"idle": _idle.size(),
		"created_total": _created_total,
		"reused_total": _reused_total,
		"released_total": _released_total,
		"disposed_total": _disposed_total,
		"rejected_total": _rejected_total,
		"peak_active": _peak_active,
	}


func _exit_tree() -> void:
	clear_idle()
	_active.clear()


func _new_instance() -> Node:
	var instance: Node = template.instantiate()
	if instance == null:
		return null
	_created_total += 1
	if instance.has_method("on_pool_created"):
		instance.call("on_pool_created")
	return instance


func _prune_invalid() -> void:
	for id in _active.keys():
		var ref: WeakRef = _active[id]
		var instance: Object = ref.get_ref()
		if instance == null or instance.is_queued_for_deletion():
			_active.erase(id)
	for i in range(_idle.size() - 1, -1, -1):
		if not is_instance_valid(_idle[i]) or _idle[i].is_queued_for_deletion():
			_idle.remove_at(i)
