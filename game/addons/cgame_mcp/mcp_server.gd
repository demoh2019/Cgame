@tool
extends RefCounted
## Minimal MCP server (JSON-RPC 2.0 over the Streamable HTTP transport, request/response mode).
##
## - Binds 127.0.0.1 only; rejects non-local Host/Origin headers (DNS-rebinding guard).
## - POST /mcp with a JSON-RPC message or batch. Requests get one application/json response,
##   notifications/responses get 202 with no body. GET/DELETE /mcp return 405 (no server push).
## - GET /health returns a small JSON status (no auth needed, no secrets).
## - Optional bearer token (env CGAME_MCP_TOKEN): `Authorization: Bearer <token>`.
## Spec: https://modelcontextprotocol.io/specification/2025-06-18/basic/transports

const Tools = preload("res://addons/cgame_mcp/mcp_tools.gd")
const LATEST := "2025-06-18"
const SUPPORTED: Array[String] = ["2025-06-18", "2025-03-26", "2024-11-05"]
const SERVER_NAME := "cgame-mcp"
const SERVER_VERSION := "1.0.0"
const MAX_BODY := 4194304
const MAX_HEADER := 16384
const IDLE_MS := 30000
const JOB_MAX_MS := 900000
const INSTRUCTIONS := "Cgame Godot editor. Edits target the currently edited scene and are undoable. Node paths are relative to the scene root ('.' = root). Prefer scene_tree(depth/filter/limit) and node_get(props) over dumping everything; use script_check/check_scripts after editing GDScript (warnings are errors); run_tests with suite names, not 'all', while iterating."

class Conn extends RefCounted:
	var peer: StreamPeerTCP
	var buf: PackedByteArray = PackedByteArray()
	var born_ms: int = Time.get_ticks_msec()
	var job: Tools.RunJob = null
	var job_id: Variant = null
	var closing: bool = false

var tools: Tools = Tools.new()
var port: int = 0
var token: String = ""
var _server: TCPServer = TCPServer.new()
var _conns: Array[Conn] = []


func start(want_port: int, auth_token: String) -> Error:
	token = auth_token
	var err: Error = _server.listen(want_port, "127.0.0.1")
	if err != OK:
		return err
	port = _server.get_local_port()
	return OK


func stop() -> void:
	for c in _conns:
		c.peer.disconnect_from_host()
	_conns.clear()
	if _server.is_listening():
		_server.stop()


func is_running() -> bool:
	return _server.is_listening()


func poll() -> void:
	if not _server.is_listening():
		return
	while _server.is_connection_available():
		var c: Conn = Conn.new()
		c.peer = _server.take_connection()
		_conns.append(c)
	var now: int = Time.get_ticks_msec()
	for i in range(_conns.size() - 1, -1, -1):
		var c: Conn = _conns[i]
		c.peer.poll()
		var status: int = c.peer.get_status()
		var drop: bool = status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR
		if c.job != null:
			if c.job.finished():
				var result: Dictionary = c.job.collect()
				_send_rpc(c, _tool_result(result), c.job_id)
				c.job = null
			elif now - c.job.started_ms > JOB_MAX_MS:
				_send_rpc(c, _tool_result({"error": "job timed out"}), c.job_id)
				c.job = null
			continue
		if not drop and c.closing:
			c.peer.disconnect_from_host()
			drop = true
		if not drop and status == StreamPeerTCP.STATUS_CONNECTED:
			_read(c)
			if c.closing:
				continue
			if now - c.born_ms > IDLE_MS:
				drop = true
		if drop:
			c.peer.disconnect_from_host()
			_conns.remove_at(i)


func _read(c: Conn) -> void:
	var avail: int = c.peer.get_available_bytes()
	if avail > 0:
		var r: Array = c.peer.get_data(avail)
		if int(r[0]) != OK:
			c.closing = true
			return
		c.buf.append_array(r[1])
	if c.buf.size() > MAX_BODY + MAX_HEADER:
		_send(c, 413, "request too large")
		return
	var hdr_end: int = _find_header_end(c.buf)
	if hdr_end < 0:
		if c.buf.size() > MAX_HEADER:
			_send(c, 431, "headers too large")
		return
	var head: String = c.buf.slice(0, hdr_end).get_string_from_utf8()
	var lines: PackedStringArray = head.split("\r\n")
	var req_line: PackedStringArray = lines[0].split(" ")
	if req_line.size() < 2:
		_send(c, 400, "bad request")
		return
	var headers: Dictionary = {}
	for k in range(1, lines.size()):
		var idx: int = lines[k].find(":")
		if idx > 0:
			headers[lines[k].substr(0, idx).strip_edges().to_lower()] = lines[k].substr(idx + 1).strip_edges()
	var length: int = int(headers.get("content-length", "0"))
	if length > MAX_BODY:
		_send(c, 413, "request too large")
		return
	if c.buf.size() < hdr_end + 4 + length:
		return
	var body: String = c.buf.slice(hdr_end + 4, hdr_end + 4 + length).get_string_from_utf8()
	_route(c, req_line[0], req_line[1].split("?")[0], headers, body)


static func _find_header_end(buf: PackedByteArray) -> int:
	var n: int = mini(buf.size() - 3, MAX_HEADER)
	for i in range(0, n):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1


static func _local_host(value: String) -> bool:
	var v: String = value.to_lower()
	for prefix in ["http://", "https://"]:
		v = v.trim_prefix(prefix)
	v = v.split("/")[0]
	var host: String = v.rsplit(":", true, 1)[0] if not v.begins_with("[") else v.split("]")[0] + "]"
	return host == "127.0.0.1" or host == "localhost" or host == "[::1]"


func _route(c: Conn, method: String, path: String, headers: Dictionary, body: String) -> void:
	if headers.has("host") and not _local_host(str(headers["host"])):
		_send(c, 403, "forbidden host")
		return
	if headers.has("origin") and not _local_host(str(headers["origin"])):
		_send(c, 403, "forbidden origin")
		return
	if method == "GET" and path == "/health":
		_send(c, 200, JSON.stringify({"ok": true, "server": SERVER_NAME, "version": SERVER_VERSION, "port": port,
			"auth": not token.is_empty()}))
		return
	if token != "" and str(headers.get("authorization", "")) != "Bearer " + token:
		_send(c, 401, JSON.stringify({"error": "unauthorized"}), "application/json", "WWW-Authenticate: Bearer\r\n")
		return
	if path != "/mcp":
		_send(c, 404, "not found")
		return
	if method == "OPTIONS":
		_send(c, 204, "")
		return
	if method != "POST":
		_send(c, 405, "", "text/plain", "Allow: POST\r\n")
		return
	var parsed: Variant = JSON.parse_string(body)
	if parsed == null:
		_send_json(c, _rpc_error(null, -32700, "parse error"))
		return
	if parsed is Array:
		var batch: Array = parsed
		var out: Array = []
		for m: Variant in batch:
			var r: Dictionary = _handle_message(m, true, c)
			if not r.is_empty():
				out.append(r)
		if out.is_empty():
			_send(c, 202, "")
		else:
			_send_json(c, out)
		return
	var r1: Dictionary = _handle_message(parsed, false, c)
	if c.job != null:
		return # response is sent when the job finishes
	if r1.is_empty():
		_send(c, 202, "")
	else:
		_send_json(c, r1)


func _handle_message(msg: Variant, in_batch: bool, c: Conn) -> Dictionary:
	if not (msg is Dictionary):
		return _rpc_error(null, -32600, "invalid request")
	var m: Dictionary = msg
	var has_id: bool = m.has("id")
	if not m.has("method"):
		return {} # a response from the client; nothing to do
	var method: String = str(m["method"])
	var params: Dictionary = m.get("params", {}) if m.get("params") is Dictionary else {}
	if not has_id:
		return {} # notification (initialized, cancelled, ...)
	var id: Variant = m["id"]
	if id is float and is_equal_approx(floorf(id), id):
		id = int(id) # JSON parses all numbers as float; echo integer ids back as integers
	match method:
		"initialize":
			var wanted: String = str(params.get("protocolVersion", LATEST))
			return _rpc_ok(id, {
				"protocolVersion": wanted if SUPPORTED.has(wanted) else LATEST,
				"capabilities": {"tools": {"listChanged": false}, "resources": {"listChanged": false, "subscribe": false}},
				"serverInfo": {"name": SERVER_NAME, "title": "Cgame Godot Editor", "version": SERVER_VERSION},
				"instructions": INSTRUCTIONS,
			})
		"ping":
			return _rpc_ok(id, {})
		"tools/list":
			return _rpc_ok(id, {"tools": tools.tool_defs()})
		"tools/call":
			var tool_name: String = str(params.get("name", ""))
			var args: Dictionary = params.get("arguments", {}) if params.get("arguments") is Dictionary else {}
			var res: Dictionary = tools.call_tool(tool_name, args)
			if res.has("_job"):
				var job: Tools.RunJob = res["_job"]
				if in_batch:
					while not job.finished():
						OS.delay_msec(50)
					return {"jsonrpc": "2.0", "id": id, "result": _tool_result(job.collect())}
				c.job = job
				c.job_id = id
				return {}
			return {"jsonrpc": "2.0", "id": id, "result": _tool_result(res)}
		"resources/list":
			return _rpc_ok(id, {"resources": tools.list_resources()})
		"resources/templates/list":
			return _rpc_ok(id, {"resourceTemplates": []})
		"resources/read":
			var content: Dictionary = tools.read_resource(str(params.get("uri", "")))
			if content.is_empty():
				return _rpc_error(id, -32002, "resource not found")
			return _rpc_ok(id, {"contents": [content]})
		"prompts/list":
			return _rpc_ok(id, {"prompts": []})
		_:
			return _rpc_error(id, -32601, "method not found: " + method)


static func _tool_result(res: Dictionary) -> Dictionary:
	var is_error: bool = res.has("error")
	var content: Array = []
	var image: Variant = res.get("_image")
	var clean: Dictionary = res.duplicate()
	clean.erase("_image")
	content.append({"type": "text", "text": JSON.stringify(clean)})
	if image is Dictionary:
		content.append({"type": "image", "data": image["data"], "mimeType": image["mimeType"]})
	return {"content": content, "isError": is_error}


static func _rpc_ok(id: Variant, result: Dictionary) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "result": result}


static func _rpc_error(id: Variant, code: int, message: String) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}


func _send_rpc(c: Conn, result: Dictionary, id: Variant) -> void:
	_send_json(c, {"jsonrpc": "2.0", "id": id, "result": result})


func _send_json(c: Conn, data: Variant) -> void:
	_send(c, 200, JSON.stringify(data))


const _REASONS := {200: "OK", 202: "Accepted", 204: "No Content", 400: "Bad Request", 401: "Unauthorized",
	403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large",
	431: "Request Header Fields Too Large"}


func _send(c: Conn, status: int, body: String, content_type: String = "application/json", extra: String = "") -> void:
	var payload: PackedByteArray = body.to_utf8_buffer()
	var head: String = "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n%s\r\n" % [
		status, _REASONS.get(status, "OK"), content_type, payload.size(), extra]
	var out: PackedByteArray = head.to_utf8_buffer()
	out.append_array(payload)
	c.peer.put_data(out)
	c.closing = true
