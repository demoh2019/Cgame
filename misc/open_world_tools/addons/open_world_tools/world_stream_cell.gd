extends Resource
class_name WorldStreamCell
## A scene is placed at grid_coord * cell_size on load.

@export var grid_coord: Vector2i = Vector2i.ZERO
@export var scene: PackedScene