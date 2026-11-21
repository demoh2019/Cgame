@tool
extends EditorPlugin
## Hosts the Cgame MCP server in the editor (see docs/cgame/ai-agents.md).
##
## Port: env CGAME_MCP_PORT, else ProjectSettings `cgame_mcp/port`, else random (0).
## Token: env CGAME_MCP_TOKEN (optional bearer token). The chosen port is written to
## user://cgame_mcp_port.txt and res://.cgame_mcp.json (the stdio bridge reads the latter).

const Server = preload("res://addons/cgame_mcp/mcp_server.gd")
const CONFIG_FILE := "res://.cgame_mcp.json"
const PORT_FILE := "user://cgame_mcp_port.txt"
const LOG_CAP := 2000

## Captures editor-process log lines (prints and errors) into a ring buffer for logs_tail.
class LogRing extends Logger:
	var lines: Array[String]

	func _log_message(message: String, error: bool) -> void:
		_push(("[err] " if error else "") + message.strip_edges(false, true))

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		var tag: String = "[warn] " if error_type == Logger.ERROR_TYPE_WARNING else "[err] "
		_push("%s%s:%d %s (%s)" % [tag, file.get_file(), line, rationale if not rationale.is_empty() else code, function])

	func _push(text: String) -> void:
		lines.append(text.left(500))
		if lines.size() > 2400:
			lines = lines.slice(lines.size() - 2000)

var _server: Server
var _ring: LogRing


func _enter_tree() -> void:
	_ring = LogRing.new()
	_ring.lines = []
	OS.add_logger(_ring)
	_server = Server.new()
	var want: int = int(OS.get_environment("CGAME_MCP_PORT")) if OS.has_environment("CGAME_MCP_PORT") \
			else int(ProjectSettings.get_setting("cgame_mcp/port", 0))
	var err: Error = _server.start(want, OS.get_environment("CGAME_MCP_TOKEN"))
	if err != OK:
		push_error("Cgame MCP: cannot listen on 127.0.0.1:%d (%s)" % [want, error_string(err)])
		return
	_write_port_files()
	set_process(true)
	print("Cgame MCP: http://127.0.0.1:%d/mcp (%s)" % [_server.port, "token required" if _server.token != "" else "no token"])


func _exit_tree() -> void:
	set_process(false)
	if _server != null:
		_server.stop()
		_remove_port_files()
	if _ring != null:
		OS.remove_logger(_ring)
	_server = null
	_ring = null


func _process(_delta: float) -> void:
	if _server != null:
		_server.tools.log_lines = _ring.lines
		_server.poll()


func _write_port_files() -> void:
	var f: FileAccess = FileAccess.open(PORT_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(str(_server.port))
		f.close()
	var info: Dictionary = {
		"port": _server.port,
		"url": "http://127.0.0.1:%d/mcp" % _server.port,
		"pid": OS.get_process_id(),
		"auth": _server.token != "",
		"project": str(ProjectSettings.get_setting("application/config/name", "")),
		"started_unix": int(Time.get_unix_time_from_system()),
	}
	var j: FileAccess = FileAccess.open(CONFIG_FILE, FileAccess.WRITE)
	if j != null:
		j.store_string(JSON.stringify(info))
		j.close()


func _remove_port_files() -> void:
	DirAccess.remove_absolute(CONFIG_FILE)
	DirAccess.remove_absolute(PORT_FILE)
