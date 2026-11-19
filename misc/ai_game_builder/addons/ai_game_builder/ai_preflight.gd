@tool
extends RefCounted

const Changes = preload("res://addons/ai_game_builder/ai_changes.gd")

# This catches obvious malformed content, not all GDScript/scene compile errors.
# Do not execute generated scripts just to check a proposal.
static func check(change_set: Dictionary) -> Dictionary:
	var checked := Changes.validate_response(change_set)
	if not checked["ok"]:
		return checked
	var errors: Array[String] = []
	for entry in checked["files"]:
		var path: String = entry["path"]
		var source: String = entry["content"]
		var ext := path.get_extension().to_lower()
		if ext == "gd" and source.strip_edges().is_empty():
			errors.append(path + ": empty GDScript")
		elif ext == "gd" and source.contains("@tool"):
			errors.append(path + ": @tool GDScript is not allowed in generated proposals")
		elif ext == "tscn" and not source.strip_edges().begins_with("[gd_scene"):
			errors.append(path + ": missing [gd_scene header")
		elif ext == "tres" and not source.strip_edges().begins_with("[gd_resource"):
			errors.append(path + ": missing [gd_resource header")
		elif ext == "gdshader" and not source.contains("shader_type "):
			errors.append(path + ": missing shader_type")
		elif ext == "json":
			var parser := JSON.new()
			if parser.parse(source) != OK:
				errors.append(path + ": invalid JSON at line %d" % parser.get_error_line())
		elif ext == "svg" and not source.contains("<svg"):
			errors.append(path + ": missing SVG root")
	return {"ok": errors.is_empty(), "errors": errors}
