extends Resource
class_name OWWorldCell
## One world partition cell. The scene's local origin maps to cell's world origin.

@export var coordinate: Vector2i = Vector2i.ZERO
@export_file("*.tscn", "*.scn") var scene_path: String = ""