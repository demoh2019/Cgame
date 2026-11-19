extends SceneTree

const Consumer = preload("res://consumer.gd")

func _initialize() -> void:
	if TestAutoload == null or TestAutoload.answer != 42 or not Consumer.is_ready():
		push_error("Autoload was unavailable to a --script SceneTree.")
		quit(1)
		return
	print("CLI_AUTOLOAD_SCENE_TREE_OK")
	quit(0)
