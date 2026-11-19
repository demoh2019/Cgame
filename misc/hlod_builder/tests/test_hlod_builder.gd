extends SceneTree
## Integration tests. Exit code is nonzero on failure.
## godot --headless --path misc/hlod_builder --script res://tests/test_hlod_builder.gd

const Builder := preload("res://addons/hlod_builder/hlod_mesh_builder.gd")
const Cluster := preload("res://addons/hlod_builder/hlod_cluster_3d.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _assert(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("HLOD FAILED: %s" % message)


func _mesh_source(name: String, mesh: Mesh = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh if mesh != null else BoxMesh.new()
	return instance


func _cluster() -> HLODCluster3D:
	var cluster := Cluster.new()
	root.add_child(cluster)
	return cluster


func _triangle_mesh(with_index: bool = true, with_attributes: bool = false) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-1, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, -1)
	])
	if with_index:
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	if with_attributes:
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2(0.5, 1), Vector2.ONE])
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.RED, Color.GREEN, Color.BLUE])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _test_empty_and_invalid() -> void:
	_assert(not Builder.build(null)["ok"], "null cluster rejected")
	var group := _cluster()
	_assert(not Builder.build(group)["ok"], "empty cluster rejected")
	_assert(not group.build_proxy(), "empty editor build rejected")
	_assert(group.get_proxy() == null, "no proxy created for empty cluster")
	group.add_child(_mesh_source("Box"))
	_assert(not Builder.build(group, -1)["ok"], "negative vertex budget rejected")
	_assert(not Builder.build(group, 2)["ok"], "budget under three rejected")
	_assert(not Builder.build(group, Builder.MAX_VERTICES + 1)["ok"], "budget above max rejected")
	_assert(not Builder.build(group, 10)["ok"], "source exceeding vertex budget rejected")
	group.queue_free()


func _test_basic_box_proxy() -> void:
	var group := _cluster()
	var first := _mesh_source("First")
	first.position = Vector3(5, 0, -2)
	group.add_child(first)
	var second := _mesh_source("Second")
	second.position = Vector3(-4, 0, 3)
	group.add_child(second)

	var result: Dictionary = Builder.build(group)
	_assert(result["ok"], "two boxes build successfully")
	if result["ok"]:
		_assert(result["source_count"] == 2, "two sources registered")
		_assert(result["surface_count"] == 1, "same material merged into one draw surface")
		_assert(result["vertex_count"] > 10, "aggregated proxy contains geometry")
		var mesh: ArrayMesh = result["mesh"]
		_assert(mesh.get_surface_count() == 1, "one merged ArrayMesh surface")
		var aabb: AABB = mesh.get_aabb()
		_assert(aabb.position.x < -3.9, "left world-space position included in proxy AABB")
		_assert(aabb.end.x > 4.9, "right world-space position included in proxy AABB")
		_assert(aabb.position.z < -1.9, "negative Z bounding box preserved")
		_assert(aabb.end.z > 2.9, "positive Z bounding box preserved")

	_assert(group.build_proxy(), "Build button creates proxy")
	_assert(group.get_proxy() != null, "generated child exists")
	_assert(not group.get_proxy().visible, "proxy initially hidden")
	_assert(group.get_proxy_surface_count() == 1, "surface getter works")
	_assert(group.get_proxy_vertex_count() == result["vertex_count"], "vertex getter works")
	_assert(Builder.get_sources(group).size() == 2, "proxy isn't counted as source")
	_assert(group.build_proxy(), "rebuilding proxy succeeds")
	_assert(group.get_child_count() == 3, "rebuild reuses the proxy child")
	group.clear_proxy()
	_assert(group.get_proxy() == null, "clear detaches proxy immediately")
	_assert(group.get_proxy_vertex_count() == 0, "empty proxy vertex count")
	group.queue_free()


func _test_transform_and_normals() -> void:
	var group := _cluster()
	group.position = Vector3(100, 7, -20)
	group.rotation = Vector3(0, 0.3, 0)
	var child := Node3D.new()
	child.position = Vector3(0, 3, 2)
	group.add_child(child)
	var source := _mesh_source("Triangle", _triangle_mesh(false))
	source.position = Vector3(3, 0, -1)
	source.scale = Vector3(-2, 3, 0.5)
	child.add_child(source)
	var result := Builder.build(group)
	_assert(result["ok"], "mirrored, nonuniformly scaled mesh builds")
	if result["ok"]:
		var proxy: ArrayMesh = result["mesh"]
		var arrays: Array = proxy.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		_assert(vertices.size() == 3, "triangle vertex count maintained")
		_assert(indices.size() == 3, "non-indexed triangle receives indices")
		_assert(indices[1] == 2 and indices[2] == 1, "mirroring reverses triangle winding")
		_assert(normals.size() == 3, "missing normals are computed")
		for i in normals.size():
			_assert(absf(normals[i].length() - 1.0) < 0.001, "computed normal is normalized")
			_assert(normals[i].dot(Vector3.UP) > 0.99, "mirrored triangle still faces up")
		_assert(absf(vertices[0].x - 5.0) < 0.001, "local X transform composed correctly")
		_assert(absf(vertices[0].y - 3.0) < 0.001, "nested Y transform preserved")
	group.queue_free()


func _test_uvs_colors_materials() -> void:
	var group := _cluster()
	var first := _mesh_source("First", _triangle_mesh(true, true))
	var red := StandardMaterial3D.new()
	first.material_override = red
	group.add_child(first)
	var second := _mesh_source("Second", _triangle_mesh(true, true))
	second.position.x = 5
	second.material_override = red
	group.add_child(second)
	var same := Builder.build(group)
	_assert(same["ok"], "valid textured geometry builds")
	if same["ok"]:
		_assert(same["surface_count"] == 1, "shared material uses one surface")
		var data: Array = same["mesh"].surface_get_arrays(0)
		var colors: PackedColorArray = data[Mesh.ARRAY_COLOR]
		var uvs: PackedVector2Array = data[Mesh.ARRAY_TEX_UV]
		_assert(colors.size() == 6, "vertex colors are retained for both meshes")
		_assert(uvs.size() == 6, "UVs are retained for both meshes")
		_assert(colors[0] == Color.RED and colors[5] == Color.BLUE, "colors preserve order")
		_assert(uvs[1] == Vector2(0.5, 1), "first UV retained")
		_assert(same["mesh"].surface_get_material(0) == red, "material preserved")
	var blue := StandardMaterial3D.new()
	second.material_override = blue
	var different := Builder.build(group)
	_assert(different["ok"] and different["surface_count"] == 2,
			"different materials use separate surfaces")
	group.queue_free()


func _test_visibility_hysteresis() -> void:
	var group := _cluster()
	group.switch_distance = 50.0
	group.hysteresis = 10.0
	var visible_source := _mesh_source("Visible")
	group.add_child(visible_source)
	var hidden_source := _mesh_source("Hidden")
	hidden_source.visible = false
	group.add_child(hidden_source)
	_assert(group.build_proxy(), "visibility test proxy builds")
	group.update_for_camera_position(Vector3(0, 0, 55))
	_assert(not group.is_using_proxy(), "near state remains near within outer hysteresis")
	_assert(visible_source.visible, "source visible near")
	_assert(not group.get_proxy().visible, "proxy hidden near")
	group.update_for_camera_position(Vector3(0, 0, 61))
	_assert(group.is_using_proxy(), "far distance enables proxy")
	_assert(not visible_source.visible, "original geometry hidden when far")
	_assert(group.get_proxy().visible, "proxy visible when far")
	group.update_for_camera_position(Vector3(0, 0, 45))
	_assert(group.is_using_proxy(), "far state persists inside inner hysteresis")
	group.update_for_camera_position(Vector3(0, 0, 39))
	_assert(not group.is_using_proxy(), "approaching below inner threshold restores originals")
	_assert(visible_source.visible, "source original visibility restored")
	_assert(not hidden_source.visible, "initially hidden geometry stays hidden")
	group.clear_proxy()
	group.update_for_camera_position(Vector3(0, 0, 1000))
	_assert(not group.is_using_proxy(), "missing proxy leaves source geometry active")
	group.queue_free()


func _test_build_failure_preserves_last_proxy() -> void:
	var group := _cluster()
	group.add_child(_mesh_source("Box"))
	_assert(group.build_proxy(), "initial successful proxy")
	var original: Mesh = group.get_proxy().mesh
	group.vertex_budget = 3
	_assert(not group.build_proxy(), "over-budget rebuild is rejected")
	_assert(group.get_proxy().mesh == original, "last successful proxy is not lost")
	_assert(Builder.get_sources(group).size() == 1, "source list remains unchanged")
	group.queue_free()


func _test_empty_optional_arrays_and_nonindexed_input() -> void:
	var group := _cluster()
	group.add_child(_mesh_source("Triangle", _triangle_mesh(false, false)))
	var result := Builder.build(group)
	_assert(result["ok"], "non-indexed mesh with missing attributes builds")
	if result["ok"]:
		var arrays: Array = result["mesh"].surface_get_arrays(0)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		_assert(colors.size() == 3, "default vertex colors emitted")
		_assert(colors[0] == Color.WHITE, "default vertex color is white")
		_assert(uvs.size() == 3 and uvs[0] == Vector2.ZERO, "default UV emitted")
	group.queue_free()


func _test_nontriangle_surface() -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.ONE])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var group := _cluster()
	group.add_child(_mesh_source("Line", mesh))
	_assert(not Builder.build(group)["ok"], "lines cannot be merged into triangle proxy")
	group.queue_free()


func _test_singular_transforms() -> void:
	var group := _cluster()
	var child := _mesh_source("ZeroScale")
	child.scale.x = 0.0
	group.add_child(child)
	_assert(not Builder.build(group)["ok"], "singular source rejected")
	child.scale.x = 1.0
	group.scale.y = 0.0
	_assert(not Builder.build(group)["ok"], "singular cluster rejected")
	group.queue_free()


func _test_nested_clusters_are_not_combined() -> void:
	var group := _cluster()
	group.add_child(_mesh_source("Outer"))
	var nested := Cluster.new()
	group.add_child(nested)
	nested.add_child(_mesh_source("Nested"))
	var sources := Builder.get_sources(group)
	_assert(sources.size() == 1, "nested HLOD cluster meshes remain independent")
	_assert(Builder.build(group)["source_count"] == 1, "nested cluster not merged")
	group.queue_free()


func _test_runtime_without_camera() -> void:
	var group := _cluster()
	group.add_child(_mesh_source("Box"))
	_assert(group.build_proxy(), "proxy built without camera")
	group.update_for_camera_position(Vector3(0, 0, 1000))
	_assert(group.is_using_proxy(), "manual camera position can select far")
	group._process(group.check_interval + 0.01)
	_assert(not group.is_using_proxy(), "runtime without current camera returns to near")
	group.queue_free()


func _test_many_sources_budget() -> void:
	var group := _cluster()
	for i in 20:
		var source := _mesh_source("Box_%d" % i)
		source.position.x = float(i) * 3.0
		group.add_child(source)
	var result := Builder.build(group)
	_assert(result["ok"], "20 source meshes combine")
	_assert(result["source_count"] == 20, "all 20 sources counted")
	_assert(result["surface_count"] == 1, "same material 20 sources single draw surface")
	_assert(result["vertex_count"] == Builder.build(group)["vertex_count"],
			"repeated build has deterministic vertex count")
	group.queue_free()


func _test_bounds_proxy_reduces_geometry() -> void:
	var group := _cluster()
	var source := _mesh_source("Sphere", SphereMesh.new())
	source.position = Vector3(7, 0, -5)
	source.scale = Vector3(2, 3, 4)
	var material := StandardMaterial3D.new()
	source.material_override = material
	group.add_child(source)
	var full := Builder.build(group)
	var reduced := Builder.build(group, Builder.MAX_VERTICES, true)
	_assert(full["ok"] and reduced["ok"], "both full and bounds modes build")
	if full["ok"] and reduced["ok"]:
		_assert(reduced["proxy_mode"] == "bounds", "bounds mode reported")
		_assert(full["proxy_mode"] == "merged", "merged mode reported")
		_assert(reduced["vertex_count"] < full["vertex_count"],
				"bounds proxy has fewer vertices than dense sphere")
		_assert(reduced["mesh"].surface_get_array_index_len(0) == 36,
				"bounds proxy has twelve triangles")
		_assert(reduced["mesh"].surface_get_material(0) == material,
				"bounds proxy preserves effective source material")
		var box: AABB = reduced["mesh"].get_aabb()
		_assert(box.position.x < 7 and box.end.x > 7,
				"bounds proxy is centered around original translated mesh")
		_assert(box.position.z < -5 and box.end.z > -5,
				"bounds proxy preserves original Z position")
	group.proxy_mode = 1
	_assert(group.build_proxy(), "inspector bounds mode builds")
	_assert(group.get_proxy_vertex_count() == reduced["vertex_count"],
			"saved bounds-mode proxy has reduced vertex count")
	group.queue_free()


func _test_bounds_proxy_for_flat_geometry() -> void:
	var group := _cluster()
	var source := _mesh_source("Flat", _triangle_mesh(true, false))
	group.add_child(source)
	var result := Builder.build(group, Builder.MAX_VERTICES, true)
	_assert(result["ok"], "flat mesh bounds use a nonzero thickness")
	if result["ok"]:
		_assert(result["vertex_count"] > 0, "flat bounds emit vertices")
		_assert(result["mesh"].get_aabb().size.y > 0.0,
				"flat bounds create valid volume")
	group.queue_free()


func _test_saved_scene_roundtrip() -> void:
	var group := Cluster.new()
	group.name = "SavedCluster"
	root.add_child(group)
	var source := _mesh_source("Box")
	group.add_child(source)
	_assert(group.build_proxy(), "proxy built before save")
	var pack := PackedScene.new()
	# Set scene ownership to make both source and generated mesh persistent.
	source.owner = group
	var proxy := group.get_proxy()
	proxy.owner = group
	_assert(pack.pack(group) == OK, "scene packed")
	var path := "user://hlod_test_scene.tscn"
	_assert(ResourceSaver.save(pack, path) == OK, "packed scene saved")
	var reloaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	_assert(reloaded != null, "packed scene loads")
	if reloaded != null:
		var loaded: HLODCluster3D = reloaded.instantiate()
		root.add_child(loaded)
		_assert(loaded.get_proxy() != null, "proxy child saved and restored")
		_assert(loaded.get_proxy_surface_count() == 1, "proxy mesh survives serialization")
		_assert(Builder.get_sources(loaded).size() == 1, "source meshes survive serialization")
		loaded.queue_free()
	group.queue_free()


func _run_tests() -> void:
	_test_empty_and_invalid()
	_test_basic_box_proxy()
	_test_transform_and_normals()
	_test_uvs_colors_materials()
	_test_visibility_hysteresis()
	_test_build_failure_preserves_last_proxy()
	_test_empty_optional_arrays_and_nonindexed_input()
	_test_nontriangle_surface()
	_test_singular_transforms()
	_test_nested_clusters_are_not_combined()
	_test_runtime_without_camera()
	_test_many_sources_budget()
	_test_saved_scene_roundtrip()
	_test_bounds_proxy_reduces_geometry()
	_test_bounds_proxy_for_flat_geometry()
	print("HLOD Builder: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
