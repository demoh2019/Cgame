extends MainLoop

const Consumer = preload("res://consumer.gd")

func _process(_delta: float) -> bool:
	# This class must compile even though plain MainLoop does not instantiate autoload nodes.
	return true
