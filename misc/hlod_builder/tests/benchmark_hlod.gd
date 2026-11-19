extends SceneTree
## Deterministic CPU microbenchmark: no GPU timing claims.
## godot --headless --path misc/hlod_builder --script res://tests/benchmark_hlod.gd

const Builder := preload("res://addons/hlod_builder/hlod_mesh_builder.gd")
const Cluster := preload("res://addons/hlod_builder/hlod_cluster_3d.gd")


func _initialize() -> void:
	call_deferred("_benchmark")


func _benchmark() -> void:
	var shared_mesh := BoxMesh.new()
	var failed := false
	for count in [16, 64, 256, 512]:
		var group: HLODCluster3D = Cluster.new()
		root.add_child(group)
		for i in count:
			var child := MeshInstance3D.new()
			child.mesh = shared_mesh
			child.position = Vector3(i % 32 * 2.0, (i / 32) * 2.0, 0.0)
			group.add_child(child)
		var before := Time.get_ticks_usec()
		var result: Dictionary = Builder.build(group)
		var duration := Time.get_ticks_usec() - before
		if not result["ok"]:
			printerr("HLOD BENCHMARK ERROR: ", result["error"])
			failed = true
		else:
			var proxy: ArrayMesh = result["mesh"]
			var triangles := 0
			for surface in proxy.get_surface_count():
				triangles += int(proxy.surface_get_array_index_len(surface) / 3)
			print(JSON.stringify({
				"sources": count,
				"original_draw_surfaces": count,
				"proxy_draw_surfaces": result["surface_count"],
				"proxy_vertices": result["vertex_count"],
				"proxy_triangles": triangles,
				"cpu_build_time_us": duration,
				"scope": "CPU geometry build only; not GPU frame time"
			}))
		group.queue_free()
	quit(1 if failed else 0)
