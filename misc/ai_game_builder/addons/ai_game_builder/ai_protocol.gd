@tool
extends RefCounted

const SYSTEM_PROMPT := """You are a senior Godot 4.8 game developer and careful editor assistant.
Produce ONLY valid JSON. Do not use Markdown or explanations outside JSON.
Schema: {"summary":"short explanation","files":[{"path":"res://scenes/main.tscn","content":"full UTF-8 text"}],"main_scene":"res://scenes/main.tscn"}.
Use file paths within res:// and only these text extensions: gd, tscn, tres, gdshader, json, txt, md, csv, svg, cfg.
Never output project.godot, secrets, file deletions, terminal commands or arbitrary executable tools.
Return complete file contents, not diffs. Use Godot 4.x valid scene/resource formats, GDScript 2.0, and consistent script references.
Prefer minimal working games, one playable main scene, input via built-in Input events and no external assets.
If updating existing files, preserve functionality and include complete updated contents.
Limit to 24 files and 256 KiB of content. Provide main_scene only when the user requests a runnable main game scene.
If a task is too large, deliver a coherent playable vertical slice rather than unfinished placeholders.
"""

static func request_body(model: String, task: String, context: String) -> String:
	var messages := [
		{"role": "system", "content": SYSTEM_PROMPT},
		{"role": "user", "content": "Request:\n" + task + "\n\nProject context (may be empty):\n" + context}
	]
	return JSON.stringify({"model": model, "messages": messages, "temperature": 0.2})


static func is_allowed_endpoint(endpoint: String) -> bool:
	if endpoint.begins_with("https://"):
		return true
	# Never transmit API credentials over unencrypted non-loopback connections.
	return endpoint.begins_with("http://localhost:") or endpoint.begins_with("http://127.0.0.1:") or endpoint.begins_with("http://[::1]:")
