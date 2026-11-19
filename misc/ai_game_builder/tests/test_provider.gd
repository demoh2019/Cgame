extends SceneTree

const Provider = preload("res://addons/ai_game_builder/provider.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_test_responses()
	print("AI Provider tests: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


func _decode(status: int, data: Variant) -> Dictionary:
	return Provider.extract_text(status, JSON.stringify(data).to_utf8_buffer())


func _test_responses() -> void:
	var result := _decode(200, {"choices": [{"message": {"content": "{\"files\":[]}"}}]})
	_expect(result["ok"], "read valid assistant message")
	if result["ok"]:
		_expect(result["content"] == "{\"files\":[]}", "returns text unchanged")

	_expect(_decode(201, {"choices": [{"message": {"content": "Hello"}}]})["ok"], "accept another 2xx")
	_expect(not _decode(200, {})["ok"], "reject response missing choices")
	_expect(not _decode(200, {"choices": []})["ok"], "reject empty choices")
	_expect(not _decode(200, {"choices": "invalid"})["ok"], "reject non-array choices")
	_expect(not _decode(200, {"choices": [null]})["ok"], "reject non-object choice")
	_expect(not _decode(200, {"choices": [{"message": null}]})["ok"], "reject non-object message")
	_expect(not _decode(200, {"choices": [{"message": {}}]})["ok"], "reject absent text content")
	_expect(not _decode(200, {"choices": [{"message": {"content": []}}]})["ok"], "reject structured content blocks")
	_expect(not _decode(200, {"choices": [{"message": {"content": ""}}]})["ok"], "reject empty text content")
	_expect(not _decode(200, {"choices": [{"message": {"content": "  \n "}}]})["ok"], "reject whitespace-only content")
	_expect(not _decode(200, [])["ok"], "reject JSON array root")
	_expect(not Provider.extract_text(200, "{invalid".to_utf8_buffer())["ok"], "reject invalid JSON")

	result = _decode(401, {"error": {"message": "Bad API key"}})
	_expect(not result["ok"], "recognize authentication failure")
	_expect(result.get("error", "").contains("HTTP 401"), "report status code")
	_expect(result.get("error", "").contains("Bad API key"), "report sanitized provider error")
	result = _decode(429, {"error": {"message": "Rate limit"}})
	_expect(not result["ok"], "recognize rate limiting")
	_expect(result.get("error", "").contains("Rate limit"), "keep useful error")
	result = _decode(500, {"error": {"message": "x".repeat(900)}})
	_expect(not result["ok"], "recognize internal server error")
	_expect(result.get("error", "").length() < 350, "truncate overly long error messages")
	_expect(not _decode(403, {"error": {"message": [1,2,3]}})["ok"], "ignore unsupported provider error shape")
	_expect(not _decode(503, {})["ok"], "reject generic provider error without details")

	var too_large := PackedByteArray()
	too_large.resize(Provider.MAX_RESPONSE_BYTES + 1)
	_expect(not Provider.extract_text(200, too_large)["ok"], "limit provider response bytes")
	var invalid_utf8 := PackedByteArray([255, 254])
	_expect(not Provider.extract_text(200, invalid_utf8)["ok"], "reject invalid UTF-8 / JSON")
