extends RefCounted
## Platform abstraction: everything the game needs from the host platform that is not rendering or input mapping.
## Game code talks to PlatformServices only; a backend supplies the platform behaviour. This file ships a
## DesktopBackend (filesystem + local JSON) and a MockConsoleBackend that reproduces generic console-style
## failure modes (quota, sign-out, controller loss, suspend) so they can be tested on any machine.
## It contains no vendor SDK code or names; a licensed port would add its own Backend subclass.

enum SaveResult { OK, QUOTA_EXCEEDED, IO_ERROR, NOT_FOUND, CORRUPT, NO_USER, INTERRUPTED, SUSPENDED }
enum RecoverSource { NONE, MAIN, BACKUP }

const MAGIC := "CGS1"


## ---- Backend contract -------------------------------------------------------------------------------------------
class Backend extends RefCounted:
	signal user_signed_out(user_id: String)
	signal user_signed_in(user_id: String)
	signal controller_disconnected(device_id: int)
	signal controller_connected(device_id: int)
	signal lifecycle_changed(suspended: bool)
	signal network_changed(available: bool)

	var quota_bytes: int = 0 ## 0 = unlimited
	## Test hook: stop a save after the temp file is written but before it is committed (power loss, suspend kill).
	var interrupt_before_commit: bool = false
	var _user_id: String = ""
	var _suspended: bool = false
	var _network: bool = true
	var _presence: String = ""
	var _entitlements: Dictionary = {}
	var _restrictions: Dictionary = {}
	var _pairs: Dictionary = {} ## device_id -> user_id
	var _connected: Dictionary = {} ## device_id -> true

	func backend_name() -> String:
		return "base"

	# Accounts
	func current_user() -> String:
		return _user_id

	func is_signed_in() -> bool:
		return _user_id != ""

	func sign_in(user_id: String) -> void:
		_user_id = user_id
		user_signed_in.emit(user_id)

	func sign_out() -> void:
		if _user_id == "":
			return
		var gone := _user_id
		_user_id = ""
		user_signed_out.emit(gone)

	# Save storage (raw bytes; the facade adds the integrity envelope)
	func write_save(_slot: String, _bytes: PackedByteArray) -> int:
		return SaveResult.IO_ERROR

	func read_save_main(_slot: String) -> PackedByteArray:
		return PackedByteArray()

	func read_save_backup(_slot: String) -> PackedByteArray:
		return PackedByteArray()

	func delete_save(_slot: String) -> void:
		pass

	func save_used_bytes() -> int:
		return 0

	# Achievements
	func unlock_achievement(_id: String) -> bool:
		return false

	func is_achievement_unlocked(_id: String) -> bool:
		return false

	func achievement_ids() -> PackedStringArray:
		return PackedStringArray()

	# Presence / entitlements
	func set_presence(text: String) -> void:
		_presence = text

	func presence() -> String:
		return _presence

	func grant_entitlement(id: String) -> void:
		_entitlements[id] = true

	func has_entitlement(id: String) -> bool:
		return _entitlements.has(id)

	# Controller to user pairing
	func pair_controller(device_id: int, user_id: String) -> void:
		_pairs[device_id] = user_id
		_connected[device_id] = true

	func controller_owner(device_id: int) -> String:
		return str(_pairs.get(device_id, ""))

	func is_controller_connected(device_id: int) -> bool:
		return _connected.has(device_id)

	func disconnect_controller(device_id: int) -> void:
		if _connected.erase(device_id):
			controller_disconnected.emit(device_id)

	func reconnect_controller(device_id: int) -> void:
		if _pairs.has(device_id) and not _connected.has(device_id):
			_connected[device_id] = true
			controller_connected.emit(device_id)

	# Lifecycle
	func is_suspended() -> bool:
		return _suspended

	func suspend() -> void:
		if not _suspended:
			_suspended = true
			lifecycle_changed.emit(true)

	func resume() -> void:
		if _suspended:
			_suspended = false
			lifecycle_changed.emit(false)

	# Network
	func network_available() -> bool:
		return _network

	func set_network(available: bool) -> void:
		if _network != available:
			_network = available
			network_changed.emit(available)

	# Text input
	func uses_native_keyboard() -> bool:
		return false

	func request_text_input(_prompt: String, _max_len: int) -> Dictionary:
		return {"ok": false, "text": ""}

	# Content restrictions / parental controls (kinds: "chat", "user_content", "purchases", "online")
	func set_restriction(kind: String, restricted: bool) -> void:
		_restrictions[kind] = restricted

	func is_restricted(kind: String) -> bool:
		return bool(_restrictions.get(kind, false))


## ---- Desktop: filesystem under user://, local achievements JSON -------------------------------------------------
class DesktopBackend extends Backend:
	var root: String

	func _init(root_dir: String = "user://platform") -> void:
		root = root_dir
		DirAccess.make_dir_recursive_absolute(root)
		_user_id = "local"
		_pairs[0] = "local"
		_connected[0] = true

	func backend_name() -> String:
		return "desktop"

	func _path(slot: String, suffix: String) -> String:
		return "%s/%s.%s" % [root, slot.validate_filename(), suffix]

	func _size_of(path: String) -> int:
		if not FileAccess.file_exists(path):
			return 0
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			return 0
		var n: int = f.get_length()
		f.close()
		return n

	func save_used_bytes() -> int:
		var total: int = 0
		for file_name in DirAccess.get_files_at(root):
			total += _size_of("%s/%s" % [root, file_name])
		return total

	func write_save(slot: String, bytes: PackedByteArray) -> int:
		var main := _path(slot, "sav")
		var tmp := _path(slot, "tmp")
		var bak := _path(slot, "bak")
		if quota_bytes > 0 and save_used_bytes() - _size_of(tmp) + bytes.size() > quota_bytes:
			return SaveResult.QUOTA_EXCEEDED
		var f := FileAccess.open(tmp, FileAccess.WRITE)
		if f == null:
			return SaveResult.IO_ERROR
		f.store_buffer(bytes)
		f.close()
		if _size_of(tmp) != bytes.size():
			return SaveResult.IO_ERROR
		if interrupt_before_commit:
			return SaveResult.INTERRUPTED
		# Commit: keep the last good file as backup, then promote the verified temp file.
		if FileAccess.file_exists(main):
			if FileAccess.file_exists(bak):
				DirAccess.remove_absolute(bak)
			if DirAccess.rename_absolute(main, bak) != OK:
				return SaveResult.IO_ERROR
		if DirAccess.rename_absolute(tmp, main) != OK:
			return SaveResult.IO_ERROR
		return SaveResult.OK

	func _read(path: String) -> PackedByteArray:
		if not FileAccess.file_exists(path):
			return PackedByteArray()
		return FileAccess.get_file_as_bytes(path)

	func read_save_main(slot: String) -> PackedByteArray:
		return _read(_path(slot, "sav"))

	func read_save_backup(slot: String) -> PackedByteArray:
		return _read(_path(slot, "bak"))

	func delete_save(slot: String) -> void:
		for suffix in ["sav", "tmp", "bak"]:
			var p := _path(slot, suffix)
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)

	## Test helper: overwrite the main file with garbage (torn write / disk fault).
	func corrupt_main(slot: String) -> void:
		var f := FileAccess.open(_path(slot, "sav"), FileAccess.WRITE)
		if f != null:
			f.store_string("garbage-not-a-save")
			f.close()

	func _ach_path() -> String:
		return root + "/achievements.json"

	func _ach_load() -> Dictionary:
		if not FileAccess.file_exists(_ach_path()):
			return {}
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_ach_path()))
		return parsed as Dictionary if parsed is Dictionary else {}

	func unlock_achievement(id: String) -> bool:
		var data := _ach_load()
		if data.has(id):
			return false
		data[id] = int(Time.get_unix_time_from_system())
		var tmp := _ach_path() + ".tmp"
		var f := FileAccess.open(tmp, FileAccess.WRITE)
		if f == null:
			return false
		f.store_string(JSON.stringify(data))
		f.close()
		return DirAccess.rename_absolute(tmp, _ach_path()) == OK

	func is_achievement_unlocked(id: String) -> bool:
		return _ach_load().has(id)

	func achievement_ids() -> PackedStringArray:
		return PackedStringArray(_ach_load().keys())


## ---- Mock console-style backend: in-memory storage with quota and scriptable failures ----------------------------
class MockConsoleBackend extends Backend:
	var _main: Dictionary = {} ## slot -> PackedByteArray
	var _tmp: Dictionary = {}
	var _bak: Dictionary = {}
	var _achievements: Dictionary = {}
	var scripted_text: Array[String] = []
	var native_keyboard: bool = true

	func _init() -> void:
		_user_id = "user1"
		pair_controller(0, "user1")

	func backend_name() -> String:
		return "mock_console"

	func save_used_bytes() -> int:
		var total: int = 0
		for d in [_main, _tmp, _bak]:
			for slot in (d as Dictionary).keys():
				total += ((d as Dictionary)[slot] as PackedByteArray).size()
		return total

	func _size(d: Dictionary, slot: String) -> int:
		return (d[slot] as PackedByteArray).size() if d.has(slot) else 0

	func write_save(slot: String, bytes: PackedByteArray) -> int:
		if _suspended:
			return SaveResult.SUSPENDED
		# Console save containers are typically charged for the new data on top of what already exists.
		if quota_bytes > 0 and save_used_bytes() - _size(_tmp, slot) + bytes.size() > quota_bytes:
			return SaveResult.QUOTA_EXCEEDED
		_tmp[slot] = bytes.duplicate()
		if interrupt_before_commit:
			return SaveResult.INTERRUPTED
		if _main.has(slot):
			_bak[slot] = _main[slot]
		_main[slot] = _tmp[slot]
		_tmp.erase(slot)
		return SaveResult.OK

	func read_save_main(slot: String) -> PackedByteArray:
		return _main[slot] if _main.has(slot) else PackedByteArray()

	func read_save_backup(slot: String) -> PackedByteArray:
		return _bak[slot] if _bak.has(slot) else PackedByteArray()

	func delete_save(slot: String) -> void:
		_main.erase(slot)
		_tmp.erase(slot)
		_bak.erase(slot)

	func corrupt_main(slot: String) -> void:
		_main[slot] = "garbage-not-a-save".to_utf8_buffer()

	func unlock_achievement(id: String) -> bool:
		if _achievements.has(id) or not is_signed_in():
			return false
		_achievements[id] = true
		return true

	func is_achievement_unlocked(id: String) -> bool:
		return _achievements.has(id)

	func achievement_ids() -> PackedStringArray:
		return PackedStringArray(_achievements.keys())

	func uses_native_keyboard() -> bool:
		return native_keyboard

	func request_text_input(_prompt: String, max_len: int) -> Dictionary:
		if scripted_text.is_empty():
			return {"ok": false, "text": ""}
		var text: String = scripted_text.pop_front()
		return {"ok": true, "text": text.substr(0, max_len)}


## ---- Facade ------------------------------------------------------------------------------------------------------
signal session_ended(reason: String)
signal pause_changed(paused: bool, reason: String)
signal achievement_unlocked(id: String)

var backend: Backend
var paused_for_controller: bool = false
var paused_for_suspend: bool = false
var session_active: bool = false
var last_session_end_reason: String = ""
var last_recover_source: int = RecoverSource.NONE
var _owner_device: int = 0


func _init(p_backend: Backend = null) -> void:
	set_backend(p_backend if p_backend != null else DesktopBackend.new())


func set_backend(p_backend: Backend) -> void:
	backend = p_backend
	backend.user_signed_out.connect(_on_user_signed_out)
	backend.controller_disconnected.connect(_on_controller_disconnected)
	backend.controller_connected.connect(_on_controller_connected)
	backend.lifecycle_changed.connect(_on_lifecycle_changed)
	session_active = backend.is_signed_in()


func start_session(device_id: int = 0) -> bool:
	if not backend.is_signed_in():
		return false
	_owner_device = device_id
	session_active = true
	paused_for_controller = not backend.is_controller_connected(device_id)
	return true


func should_pause() -> bool:
	return paused_for_controller or paused_for_suspend


func _on_user_signed_out(user_id: String) -> void:
	session_active = false
	last_session_end_reason = "signed_out:" + user_id
	session_ended.emit(last_session_end_reason)


func _on_controller_disconnected(device_id: int) -> void:
	if device_id == _owner_device and session_active:
		paused_for_controller = true
		pause_changed.emit(true, "controller_disconnected")


func _on_controller_connected(device_id: int) -> void:
	if device_id == _owner_device and paused_for_controller:
		paused_for_controller = false
		pause_changed.emit(should_pause(), "controller_reconnected")


func _on_lifecycle_changed(suspended: bool) -> void:
	paused_for_suspend = suspended
	pause_changed.emit(should_pause(), "suspend" if suspended else "resume")


## Saving: payload is wrapped in "CGS1:<hash>:<json>" so truncated or garbled files are detected on load.
static func encode_save(data: Dictionary) -> PackedByteArray:
	var body := JSON.stringify(data)
	return ("%s:%d:%s" % [MAGIC, body.hash(), body]).to_utf8_buffer()


static func decode_save(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty():
		return {}
	var parts := bytes.get_string_from_utf8().split(":", true, 2)
	if parts.size() != 3 or parts[0] != MAGIC or not parts[1].is_valid_int():
		return {}
	if parts[2].hash() != int(parts[1]):
		return {}
	var parsed: Variant = JSON.parse_string(parts[2])
	return parsed as Dictionary if parsed is Dictionary else {}


func save_game(slot: String, data: Dictionary) -> int:
	if not backend.is_signed_in():
		return SaveResult.NO_USER
	if backend.is_suspended():
		return SaveResult.SUSPENDED
	return backend.write_save(slot, encode_save(data))


## Returns {"result": SaveResult, "data": Dictionary, "source": RecoverSource}. Falls back to the backup copy when
## the main file is missing or fails validation.
func load_game(slot: String) -> Dictionary:
	last_recover_source = RecoverSource.NONE
	if not backend.is_signed_in():
		return {"result": SaveResult.NO_USER, "data": {}, "source": RecoverSource.NONE}
	if backend.is_suspended():
		return {"result": SaveResult.SUSPENDED, "data": {}, "source": RecoverSource.NONE}
	var main_bytes := backend.read_save_main(slot)
	var data := decode_save(main_bytes)
	if not data.is_empty():
		last_recover_source = RecoverSource.MAIN
		return {"result": SaveResult.OK, "data": data, "source": RecoverSource.MAIN}
	var backup_bytes := backend.read_save_backup(slot)
	data = decode_save(backup_bytes)
	if not data.is_empty():
		last_recover_source = RecoverSource.BACKUP
		return {"result": SaveResult.OK, "data": data, "source": RecoverSource.BACKUP}
	var missing := main_bytes.is_empty() and backup_bytes.is_empty()
	return {"result": SaveResult.NOT_FOUND if missing else SaveResult.CORRUPT, "data": {}, "source": RecoverSource.NONE}


func unlock_achievement(id: String) -> bool:
	var fresh := backend.unlock_achievement(id)
	if fresh:
		achievement_unlocked.emit(id)
	return fresh


func set_presence(text: String) -> void:
	backend.set_presence(text)


func has_entitlement(id: String) -> bool:
	return backend.has_entitlement(id)


func network_available() -> bool:
	return backend.network_available()


func can_use_chat() -> bool:
	return not backend.is_restricted("chat") and backend.network_available()


func can_use_online() -> bool:
	return not backend.is_restricted("online") and backend.network_available()


## Text entry: platform keyboard when the backend has one, otherwise {"ok": false} so the UI shows its own.
func request_text(prompt: String, max_len: int) -> Dictionary:
	return backend.request_text_input(prompt, max_len)
