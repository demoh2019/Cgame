extends SceneTree

# Reproducible non-asserting benchmark for Node.find_children().
# Run using: godot --headless --script res://misc/scripts/benchmarks/benchmark_node_find_children.gd
const WIDTH := 32
const DEPTH := 16
const ITERATIONS := 3000

func _initialize() -> void:
	var root_node := Node.new()
	root_node.name = "BenchmarkRoot"
	get_root().add_child(root_node)
	for branch_index in WIDTH:
		var parent := root_node
		for depth_index in DEPTH:
			var node := Node.new()
			node.name = "Child_%d_%d" % [branch_index, depth_index]
			parent.add_child(node)
			parent = node

	var count := 0
	var before := Time.get_ticks_usec()
	for index in ITERATIONS:
		count += root_node.find_children("Child_*", "", true, false).size()
	var elapsed := Time.get_ticks_usec() - before
	print("find_children: ", ITERATIONS, " queries, ", count, " hits, ", elapsed, " usec total, ", float(elapsed) / ITERATIONS, " usec/query")
	root_node.queue_free()
	quit()
