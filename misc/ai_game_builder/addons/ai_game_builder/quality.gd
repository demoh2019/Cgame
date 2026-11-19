@tool
extends RefCounted

## Non-executing, conservative checks for generated resources before applying.
## This is not a replacement for a Godot import, script compiler or gameplay test.

const Validator = preload("res://addons/ai_game_builder/validator.gd")


static func review_payload(payload: Variant, mode: String = "") -> Dictionary:
	var checked := Validator.validate_payload(payload)
	if not checked["ok"]:
		return {"ok": false, "errors": [checked["error"]], "warnings": []}

	var issues: Array[String] = []
	var warnings: Array[String] = []
	var paths := {}
	for file in checked["files"]:
		var path: String = file["path"]
		var content: String = file["content"]
		var stripped := content.strip_edges()
		var ext := path.get_extension().to_lower()
		paths[path] = true
		match ext:
			"tscn":
				if not stripped.begins_with("[gd_scene"):
					issues.append("%s: missing [gd_scene] header." % path)
				if not content.contains("[node "):
					issues.append("%s: no scene nodes." % path)
			"tres":
				if not stripped.begins_with("[gd_resource"):
					issues.append("%s: missing [gd_resource] header." % path)
				if not content.contains("[resource]"):
					warnings.append("%s: missing [resource] section." % path)
			"json":
				var parser := JSON.new()
				if parser.parse(content) != OK:
					issues.append("%s: invalid JSON at line %d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
			"gdshader":
				if not content.contains("shader_type "):
					warnings.append("%s: no shader_type declaration." % path)
			"svg":
				if not content.contains("<svg"):
					issues.append("%s: SVG root element missing." % path)
			"gd":
				if not content.contains("extends ") and not content.contains("class_name "):
					warnings.append("%s: script has no extends/class_name declaration." % path)

	if mode in ["2D game", "3D game"] and not paths.has("scenes/main.tscn"):
		issues.append("Game mode requires scenes/main.tscn.")
	return {"ok": issues.is_empty(), "errors": issues, "warnings": warnings}
