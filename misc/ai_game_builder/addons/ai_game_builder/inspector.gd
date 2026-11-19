@tool
extends RefCounted

const PlanValidator = preload("res://addons/ai_game_builder/validator.gd")

# This is a conservative, non-executing check; it does not compile scripts.
# Every res:// reference used by generated code/scenes must point to another
# generated file. The model cannot rely on installed addons or project assets.
const SCRIPT_WARNINGS := [
	"@tool", "OS.execute(", "OS.create_process(", "FileAccess.open(",
	"DirAccess.remove_absolute(", "JavaScriptBridge", "HTTPClient", "HTTPRequest"
]


static func inspect(plan: Dictionary) -> Dictionary:
	var valid := PlanValidator.validate(plan)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if not valid.ok:
		errors.append(String(valid.error))
		return {"ok": false, "errors": errors, "warnings": warnings}

	var contents := {}
	for file in valid.plan.files:
		contents[String(file.path)] = String(file.content)

	if not contents.has("main.tscn"):
		errors.append("Missing main.tscn: the game needs an entry scene.")
	elif not String(contents["main.tscn"]).strip_edges().begins_with("[gd_scene "):
		errors.append("main.tscn does not begin with a [gd_scene] header.")

	var resource_path := RegEx.new()
	var compile_error := resource_path.compile("res://[A-Za-z0-9_./-]+")
	if compile_error != OK:
		errors.append("Internal resource path checker is unavailable.")
		return {"ok": false, "errors": errors, "warnings": warnings}

	var checked_references := {}
	for file in valid.plan.files:
		var path: String = file.path
		var code: String = file.content
		if path.ends_with(".gd"):
			for indicator in SCRIPT_WARNINGS:
				if code.contains(indicator):
					warnings.append("%s: review use of %s" % [path, indicator])
		if not ["tscn", "tres", "gd", "gdshader"].has(path.get_extension()):
			continue
		for matched in resource_path.search_all(code):
			var source: String = matched.get_string()
			var diagnostic_key := path + "|" + source
			if checked_references.has(diagnostic_key):
				continue
			checked_references[diagnostic_key] = true
			if not source.begins_with(PlanValidator.OUTPUT_PREFIX):
				errors.append("%s: external resource reference %s is not allowed." % [path, source])
				continue
			var referenced_path := source.trim_prefix(PlanValidator.OUTPUT_PREFIX)
			if not contents.has(referenced_path):
				errors.append("%s: missing generated dependency %s." % [path, source])

	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}


static func repair_prompt(original_request: String, candidate: Dictionary, problems: Array[String]) -> String:
	# No autonomous loops or automatic writes. The user explicitly requests
	# each regeneration; model output passes the same validation again.
	return (
		"Fix the generated Godot 4 game so that it is self-contained and playable. " +
		"Respond with a COMPLETE replacement JSON plan using the same schema, " +
		"not a patch or markdown. Respect the original request and all system rules.\n\n" +
		"ORIGINAL REQUEST:\n" + original_request + "\n\n" +
		"STATIC DIAGNOSTICS:\n" + JSON.stringify(problems) + "\n\n" +
		"PREVIOUS PLAN:\n" + JSON.stringify(candidate)
	)


static func refine_prompt(original_request: String, change_request: String, candidate: Dictionary) -> String:
	# Refinement does not touch files. A complete regenerated plan is inspected
	# and explicitly approved before Writer.apply() can be called.
	return (
		"Improve the following Godot 4 game. Return a COMPLETE replacement JSON " +
		"plan (not a patch) in the original schema. Preserve working features " +
		"unless the new request explicitly changes them. Keep the game self-contained " +
		"within res://ai_generated/ and obey every system constraint.\n\n" +
		"ORIGINAL GAME DESCRIPTION:\n" + original_request + "\n\n" +
		"NEW CHANGES:\n" + change_request + "\n\n" +
		"CURRENT GENERATED FILES:\n" + JSON.stringify(candidate)
	)
