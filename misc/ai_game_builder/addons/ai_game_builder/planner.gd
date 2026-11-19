@tool
extends RefCounted

const PlanValidator = preload("res://addons/ai_game_builder/validator.gd")

const SYSTEM_PROMPT := (
	"You are a senior Godot 4 GDScript game developer. Create a small, playable "
	"and self-contained Godot game based on the user's request. Return ONLY a JSON "
	"object shaped as {\"summary\":\"...\",\"files\":[{\"path\":\"main.tscn\","
	"\"content\":\"...\"},{\"path\":\"player.gd\",\"content\":\"...\"}]}. "
	"Paths must be relative to res://ai_generated/ and only use ASCII letters, "
	"numbers, underscores, hyphens, dots and slashes. Allowed extensions: "
	".tscn, .tres, .gd, .gdshader, .json, .md and .txt. "
	"At most 16 files, up to 65536 bytes each. Include a playable main.tscn "
	"and all GDScript dependencies. Use built-in shapes and colors; do not "
	"reference assets or autoloads outside the generated folder. "
	"Use Godot 4 syntax. Avoid @tool, OS, shell commands and network access. "
	"Ensure JSON string escaping is correct. No markdown fences or explanations."
)


static func make_request(model: String, user_prompt: String) -> String:
	return JSON.stringify({
		"model": model,
		"temperature": 0.2,
		"messages": [
			{"role": "system", "content": SYSTEM_PROMPT},
			{"role": "user", "content": user_prompt}
		]
	})


static func read_response(body: String) -> Dictionary:
	var response: Variant = JSON.parse_string(body)
	if typeof(response) != TYPE_DICTIONARY:
		return {"ok": false, "error": "The provider returned invalid JSON."}
	var choices: Variant = response.get("choices")
	if typeof(choices) != TYPE_ARRAY or choices.is_empty():
		return {"ok": false, "error": "The provider returned no completions."}
	if typeof(choices[0]) != TYPE_DICTIONARY:
		return {"ok": false, "error": "The completion has an invalid format."}
	var message: Variant = choices[0].get("message")
	if typeof(message) != TYPE_DICTIONARY:
		return {"ok": false, "error": "The completion has no message."}
	var content: Variant = message.get("content")
	if typeof(content) != TYPE_STRING or content.strip_edges().is_empty():
		return {"ok": false, "error": "The completion has no text."}

	# Tolerate one markdown JSON fence, even though the prompt forbids it.
	var cleaned: String = content.strip_edges()
	var fence := "\u0060\u0060\u0060"
	if cleaned.begins_with(fence) and cleaned.ends_with(fence):
		var first_newline := cleaned.find("\n")
		if first_newline != -1:
			cleaned = cleaned.substr(first_newline + 1, cleaned.length() - first_newline - 4).strip_edges()
	return PlanValidator.parse(cleaned)
