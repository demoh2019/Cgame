extends RefCounted
## On-demand Unreal MemReport-style object population diagnostics.
## No per-frame work, no automatic polling, no retained scene objects, and
## no native class dependency in regular release/stock Godot builds.

const TRACKED_CLASSES := [
	"Node3D",
	"MeshInstance3D",
	"MultiMeshInstance3D",
	"AnimationPlayer",
	"AudioStreamPlayer3D",
	"GPUParticles3D",
	"CollisionShape3D",
	"ShaderMaterial",
	"StandardMaterial3D",
	"ImageTexture",
]

var _native: Object = null
var _previous: Dictionary = {}


func _init() -> void:
	if ClassDB.class_exists("ObjectDBRuntimeProfiler"):
		var candidate: Object = ClassDB.instantiate("ObjectDBRuntimeProfiler")
		if candidate != null and candidate.has_method("sample_classes"):
			_native = candidate


func available() -> bool:
	return _native != null


## Sample only when the user explicitly requests it. Each result contains
## exact native-class counts (not subclass totals) and differences relative
## to the previous explicit sample; growth does not by itself prove a leak.
func sample() -> Dictionary:
	if _native == null:
		return {}
	var result: Dictionary = _native.call("sample_classes", PackedStringArray(TRACKED_CLASSES))
	if not result.has("total") or not result.has("classes"):
		return {}
	var counts: Dictionary = result["classes"]
	if counts.size() != TRACKED_CLASSES.size():
		return {}
	var had_previous: bool = not _previous.is_empty()
	var old_counts: Dictionary = _previous.get("classes", {})
	var changes := {}
	for name in TRACKED_CLASSES:
		changes[name] = int(counts.get(name, 0)) - int(old_counts.get(name, 0)) 			if had_previous else 0
	var total: int = int(result["total"])
	var previous_total: int = int(_previous.get("total", total))
	_previous = result.duplicate(true)
	return {
		"total": total,
		"counts": counts,
		"delta": total - previous_total,
		"changes": changes,
		"has_previous": had_previous,
	}


static func format_report(snapshot: Dictionary) -> String:
	if snapshot.is_empty():
		return "Object census needs the Cgame debug engine."
	var total: int = int(snapshot.get("total", 0))
	var text: String = "Objects: %d" % total
	if bool(snapshot.get("has_previous", false)):
		var change: int = int(snapshot.get("delta", 0))
		text += " (%s%d)" % ["+" if change > 0 else "", change]
	var counts: Dictionary = snapshot.get("counts", {})
	var changes: Dictionary = snapshot.get("changes", {})
	for name in ["MultiMeshInstance3D", "MeshInstance3D"]:
		var amount: int = int(counts.get(name, 0))
		text += " | %s %d" % [name, amount]
		if bool(snapshot.get("has_previous", false)):
			var delta: int = int(changes.get(name, 0))
			text += " (%s%d)" % ["+" if delta > 0 else "", delta]
	return text


func reset_baseline() -> void:
	_previous.clear()
