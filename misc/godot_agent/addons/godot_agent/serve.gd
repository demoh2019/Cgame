extends SceneTree
## Godot Agent: a tiny MCP server (Streamable HTTP, JSON responses) for AI coding agents.
##
##   godot --headless --path <project> --script res://addons/godot_agent/serve.gd -- [--port 7777] [--token SECRET]
##
## Listens on 127.0.0.1 only. Endpoint: POST http://127.0.0.1:7777/mcp
## Add to an agent, e.g.:  claude mcp add --transport http godot http://127.0.0.1:7777/mcp

const Tools = preload("tools.gd")

const MAX_BODY := 4 * 1024 * 1024
const PROTOCOL := "2025-03-26"

var _server := TCPServer.new()
var _clients: Array = []  # [StreamPeerTCP, PackedByteArray, started_msec]
var _tools: RefCounted
var _token := ""
var _port := 7777
var _quit_requested := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--port":
				i += 1
				_port = int(args[i]) if i < args.size() else _port
			"--token":
				i += 1
				_token = args[i] if i < args.size() else ""
		i += 1
	var dir: String = get_script().resource_path.get_base_dir()
	_tools = Tools.new(dir)
	var err := _server.listen(_port, "127.0.0.1")
	if err != OK:
		printerr("godot_agent: cannot listen on 127.0.0.1:%d (%s)" % [_port, error_string(err)])
		quit(2)
		return
	print("godot_agent: MCP at http://127.0.0.1:%d/mcp  project=%s" % [_port, ProjectSettings.globalize_path("res://")])


func _process(_delta: float) -> bool:
	while _server.is_connection_available():
		_clients.append([_server.take_connection(), PackedByteArray(), Time.get_ticks_msec()])
	var keep: Array = []
	for c in _clients:
		var peer: StreamPeerTCP = c[0]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var got := peer.get_data(n)
			if got[0] == OK:
				c[1].append_array(got[1])
		var consumed := _try_handle(peer, c[1])
		if consumed:
			peer.disconnect_from_host()
		elif Time.get_ticks_msec() - int(c[2]) < 30000 and c[1].size() < MAX_BODY + 65536:
			keep.append(c)
		else:
			peer.disconnect_from_host()
	_clients = keep
	OS.delay_msec(2)
	return _quit_requested


## Returns true when a full request was handled (response written).
func _try_handle(peer: StreamPeerTCP, buf: PackedByteArray) -> bool:
	var text_end := _find_header_end(buf)
	if text_end < 0:
		return false
	var head := buf.slice(0, text_end).get_string_from_utf8()
	var lines := head.split("\r\n")
	var req := lines[0].split(" ")
	var headers := {}
	for li in range(1, lines.size()):
		var colon := lines[li].find(":")
		if colon > 0:
			headers[lines[li].substr(0, colon).strip_edges().to_lower()] = lines[li].substr(colon + 1).strip_edges()
	var length := int(headers.get("content-length", "0"))
	if length > MAX_BODY:
		_respond(peer, 413, "")
		return true
	if buf.size() < text_end + 4 + length:
		return false
	var body := buf.slice(text_end + 4, text_end + 4 + length).get_string_from_utf8()
	var method := req[0] if req.size() > 0 else ""
	if headers.has("origin"):
		var o: String = headers["origin"]
		if not (o.contains("://127.0.0.1") or o.contains("://localhost") or o.contains("://[::1]")):
			_respond(peer, 403, "")
			return true
	if _token != "" and headers.get("authorization", "") != "Bearer " + _token:
		_respond(peer, 401, "")
		return true
	if method == "GET" or method == "DELETE":
		_respond(peer, 405, "", {"Allow": "POST"})
		return true
	if method != "POST":
		_respond(peer, 400, "")
		return true
	var msg: Variant = JSON.parse_string(body)
	if msg == null:
		_respond(peer, 400, JSON.stringify({"jsonrpc": "2.0", "id": null, "error": {"code": -32700, "message": "parse error"}}))
		return true
	var reply: Variant
	if msg is Array:
		var arr: Array = []
		for m in msg:
			var r: Variant = handle_rpc(m)
			if r != null:
				arr.append(r)
		reply = arr if not arr.is_empty() else null
	else:
		reply = handle_rpc(msg)
	if reply == null:
		_respond(peer, 202, "")
	else:
		_respond(peer, 200, JSON.stringify(reply))
	return true


static func _find_header_end(buf: PackedByteArray) -> int:
	for i in range(0, buf.size() - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1


func _respond(peer: StreamPeerTCP, code: int, body: String, extra: Dictionary = {}) -> void:
	var reasons := {200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 405: "Method Not Allowed", 413: "Payload Too Large"}
	var data := body.to_utf8_buffer()
	var h := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n" % [code, reasons.get(code, "OK"), data.size()]
	for k in extra:
		h += "%s: %s\r\n" % [k, extra[k]]
	h += "\r\n"
	peer.put_data(h.to_utf8_buffer())
	if data.size() > 0:
		peer.put_data(data)


## JSON-RPC dispatcher. Returns a response Dictionary, or null for notifications.
func handle_rpc(msg: Variant) -> Variant:
	if not (msg is Dictionary):
		return {"jsonrpc": "2.0", "id": null, "error": {"code": -32600, "message": "invalid request"}}
	var m: Dictionary = msg
	var id: Variant = m.get("id")
	if id is float and is_equal_approx(id, floor(id)):
		id = int(id)  # JSON numbers parse as floats; echo integer ids unchanged
	var method := String(m.get("method", ""))
	if id == null:
		return null  # notification (e.g. notifications/initialized)
	var params: Dictionary = m.get("params", {}) if m.get("params") is Dictionary else {}
	match method:
		"initialize":
			return _ok(id, {
				"protocolVersion": PROTOCOL,
				"capabilities": {"tools": {"listChanged": false}},
				"serverInfo": {"name": "godot-agent", "version": "0.1"},
				"instructions": Tools.INSTRUCTIONS,
			})
		"ping":
			return _ok(id, {})
		"tools/list":
			return _ok(id, {"tools": _tools.list()})
		"tools/call":
			var name := String(params.get("name", ""))
			var args: Dictionary = params.get("arguments", {}) if params.get("arguments") is Dictionary else {}
			var text: String = _tools.call_tool(name, args)
			return _ok(id, {"content": [{"type": "text", "text": text}], "isError": text.begins_with("ERR")})
	return {"jsonrpc": "2.0", "id": id, "error": {"code": -32601, "message": "method not found: " + method}}


static func _ok(id: Variant, result: Dictionary) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "result": result}
