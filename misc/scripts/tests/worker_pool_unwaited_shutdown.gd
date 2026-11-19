extends SceneTree

# Regression smoke for Godot #125357.
# Wait until every task has completed without reclaiming its TaskID with
# wait_for_task_completion(). The script callables must be freed before the
# GDScript language is torn down when the engine exits.
const TASK_COUNT := 32
const MAX_FRAMES := 600

var task_ids: Array[int] = []
var elapsed_frames := 0

func _initialize() -> void:
	for index in TASK_COUNT:
		task_ids.append(WorkerThreadPool.add_task(Callable(self, "_noop").bind(index)))

func _noop(index: int) -> void:
	var value: int = index * index
	if value < 0:
		push_error("Unexpected arithmetic result")

func _process(_delta: float) -> bool:
	elapsed_frames += 1
	for task_id in task_ids:
		if not WorkerThreadPool.is_task_completed(task_id):
			if elapsed_frames > MAX_FRAMES:
				push_error("WorkerThreadPool tasks did not finish")
				quit(1)
				return true
			return false
	print("Unclaimed WorkerThreadPool tasks completed; testing shutdown cleanup.")
	return true
