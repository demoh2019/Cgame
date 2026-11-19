@tool
extends RefCounted

# Decode one OpenAI-compatible Chat Completions response without a live provider.
const MAX_RESPONSE_BYTES := 2097152


static func extract_text(status: int, body: PackedByteArray) -> Dictionary:
	if body.size() > MAX_RESPONSE_BYTES:
		return _error("Provider response exceeds 2 MiB.")
	var decoded: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(decoded) != TYPE_DICTIONARY:
		return _error("Provider returned invalid JSON (HTTP %d)." % status)

	if status < 200 or status >= 300:
		var response_error: Variant = decoded.get("error", {})
		var message := "Request failed"
		if typeof(response_error) == TYPE_DICTIONARY:
			var raw: Variant = response_error.get("message", "Request failed")
			if typeof(raw) == TYPE_STRING:
				message = raw
		return _error("Provider HTTP %d: %s" % [status, message.substr(0, 300)])

	var choices: Variant = decoded.get("choices", [])
	if typeof(choices) != TYPE_ARRAY or choices.is_empty() or typeof(choices[0]) != TYPE_DICTIONARY:
		return _error("Provider response has no chat choices.")
	var message: Variant = choices[0].get("message", {})
	if typeof(message) != TYPE_DICTIONARY or typeof(message.get("content")) != TYPE_STRING:
		return _error("Provider did not return textual content.")
	var content: String = message["content"]
	if content.strip_edges().is_empty():
		return _error("Provider returned an empty message.")
	return {"ok": true, "content": content}


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
