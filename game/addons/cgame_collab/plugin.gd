@tool
extends EditorPlugin
## Collaboration skeleton: shows connected users and asset locks in a dock.
## No sockets are opened here. Set a transport with set_transport(send: Callable) where
## send(message: Dictionary) delivers a message to the other editors, and feed incoming
## messages to receive(message). Not enabled in project.godot by default.

const SceneCRDT = preload("res://scripts/tools/scene_crdt.gd")
const AssetConflicts = preload("res://scripts/tools/asset_conflicts.gd")

var doc: RefCounted = null
var locks: RefCounted = null
var user_name: String = "user"

var _send: Callable = Callable()
var _dock: VBoxContainer = null
var _users_list: ItemList = null
var _locks_list: ItemList = null


func _enter_tree() -> void:
	doc = SceneCRDT.new(user_name)
	locks = AssetConflicts.new()
	doc.op_generated.connect(_on_local_op)
	_dock = VBoxContainer.new()
	_dock.name = "Collab"
	var users_label := Label.new()
	users_label.text = "Connected users"
	_dock.add_child(users_label)
	_users_list = ItemList.new()
	_users_list.custom_minimum_size = Vector2(0, 80)
	_dock.add_child(_users_list)
	var locks_label := Label.new()
	locks_label.text = "Locks"
	_dock.add_child(locks_label)
	_locks_list = ItemList.new()
	_locks_list.custom_minimum_size = Vector2(0, 80)
	_dock.add_child(_locks_list)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	refresh_dock()


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


## send is called as send.call(message: Dictionary); pass Callable() to disconnect.
func set_transport(send: Callable) -> void:
	_send = send


func _on_local_op(op: Dictionary) -> void:
	if _send.is_valid():
		_send.call({"type": "op", "op": op})


## Entry point for incoming transport messages: op, presence, lock, unlock, sync_request.
func receive(msg: Dictionary) -> void:
	match msg.get("type", ""):
		"op":
			doc.apply(msg.get("op", {}))
		"presence":
			doc.apply_presence(msg.get("presence", {}))
		"lock":
			locks.lock(msg.get("path", ""), msg.get("user", ""), float(msg.get("ttl", 300.0)))
		"unlock":
			locks.unlock(msg.get("path", ""), msg.get("user", ""))
		"sync_request":
			if _send.is_valid():
				_send.call({"type": "sync", "ops": doc.ops_since(msg.get("vector", {}))})
		"sync":
			doc.merge_ops(msg.get("ops", []))
	refresh_dock()


## Requests a lock and announces it when granted. Returns whether it was granted.
func request_lock(path: String) -> bool:
	var ok: bool = locks.lock(path, user_name)
	if ok and _send.is_valid():
		_send.call({"type": "lock", "path": path, "user": user_name})
	refresh_dock()
	return ok


func refresh_dock() -> void:
	if _users_list == null:
		return
	_users_list.clear()
	var pres: Dictionary = doc.presence()
	for u in pres:
		_users_list.add_item(str(u))
	_locks_list.clear()
	var table: Dictionary = locks.active_locks()
	for p in table:
		_locks_list.add_item("%s  (%s)" % [p, table[p]])
