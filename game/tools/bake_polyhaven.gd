extends SceneTree
## Bakes the Poly Haven models (assets/models/polyhaven/<id>/<id>.gltf) into light meshes the game can draw by the hundred:
## every object's transform applied, the triangle count cut with meshoptimizer to a budget, unused vertices dropped, and the
## result saved as assets/models/polyhaven/baked/<name>.res with the original materials (which point at the textures).
## The scanned rocks have 60 000-100 000 triangles each; in a MultiMesh of a forest chunk that would be far too many.
##   godot --headless --path game --script res://tools/bake_polyhaven.gd

const SOURCE := "res://assets/models/polyhaven/"
const OUTPUT := "res://assets/models/polyhaven/baked/"

# name: [model id, node name or "" for every object merged, triangle budget]
const JOBS := {
	"boulder_01": ["boulder_01", "", 1600],
	"boulder_02": ["namaqualand_boulder_02", "", 1600],
	"mossy_rock_1": ["rock_moss_set_01", "rock_moss_set_01_rock01", 1100],
	"mossy_rock_2": ["rock_moss_set_01", "rock_moss_set_01_rock02", 1100],
	"mossy_rock_3": ["rock_moss_set_01", "rock_moss_set_01_rock03", 1100],
	"mossy_rock_4": ["rock_moss_set_01", "rock_moss_set_01_rock04", 1100],
	"mossy_rock_5": ["rock_moss_set_02", "rock_moss_set_02_rock13", 1000],
	"mossy_rock_6": ["rock_moss_set_02", "rock_moss_set_02_rock10", 1000],
	"dead_trunk": ["dead_tree_trunk_02", "", 1800],
	"tree_stump": ["tree_stump_01", "", 1400],
	"fire_pit": ["stone_fire_pit", "", 1600],
	"lantern": ["wooden_lantern_01", "", 1200],
	"crate": ["wooden_crate_01", "", 1400],
	"wine_barrel": ["wine_barrel_01", "", 1600],
	"barrel_pile": ["wooden_barrels_01", "", 3200],
	"bucket": ["wooden_bucket_01", "", 900],
	"horse_statue": ["horse_statue_01", "", 3000],
	# Second batch: the leftovers of the old world, for ruins, depots, bunkers and camps.
	"oil_barrel": ["Barrel_01", "", 900],
	"fuel_barrel": ["barrel_03", "", 900],
	"fire_barrel": ["barrel_stove", "", 1200],
	"jerrycan": ["metal_jerrycan", "", 600],
	"jerrycan_green": ["metal_jerrycan_green", "", 600],
	"military_crate": ["old_military_crate", "", 900],
	"army_crate": ["wooden_military_crate", "", 900],
	"ammo_box": ["ammo_box", "", 600],
	"tyre": ["old_tyre", "", 900],
	"wheel_rim": ["rusted_wheel_rim_01", "", 700],
	"road_barrier": ["concrete_road_barrier", "", 800],
	"trash_can": ["metal_trash_can", "", 900],
	"trash_bag": ["trashbag", "", 700],
	"propane_tank": ["propane_tank", "", 900],
	"generator": ["portable_generator", "", 2000],
	"street_lamp": ["street_lamp_01", "", 1200],
	"hydrant": ["fire_hydrant", "", 1000],
	"picnic_table": ["wooden_picnic_table", "", 900],
	"plastic_crate": ["plastic_crate_01", "", 900],
	"cardboard_box": ["cardboard_box_01", "", 500],
	"wooden_crate": ["wooden_crate_02", "", 900],
	"metal_rack": ["worn_metal_rack", "", 1500],
	"tool_cart": ["tool_cart", "", 1500],
	"bench": ["painted_wooden_bench", "", 900],
	"rock_7": ["rock_07", "", 1400],
	"rock_9": ["rock_09", "", 1400],
	"boulder_04": ["namaqualand_boulder_04", "", 1400],
	"stump_2": ["tree_stump_02", "", 1200],
	"fallen_trunk": ["dead_tree_trunk", "", 1600],
	# Third batch: what a thousand years leave on the ground: branches, bark, roots, logs, and stones in groups.
	"branches": ["dry_branches_medium_01", "", 900],
	"bark_debris": ["bark_debris_01", "", 600],
	"stick_1": ["dead_quiver_branch_01", "", 600],
	"stick_2": ["dead_quiver_branch_02", "", 700],
	"old_log": ["dead_quiver_trunk", "", 1500],
	"roots": ["root_cluster_01", "", 1400],
	"pine_roots": ["pine_roots", "", 1200],
	"single_root": ["single_root", "", 600],
	"boulder_group": ["namaqualand_boulders_01", "", 2400],
	"rock_group": ["namaqualand_rocks_01", "", 1600],
	"stone_scatter": ["namaqualand_stones_01", "", 1200],
	"boulder_05": ["namaqualand_boulder_05", "", 1400],
	"shore_rocks": ["coast_rocks_01", "", 2000],
}


# Scanned ground plants, baked one mesh per variant (each gltf holds several), centred on its root.
#   godot --headless --path game --script res://tools/bake_polyhaven.gd -- --plants
# id: [triangle budget per variant, merge every part into one mesh, part names to skip]
const PLANT_OUTPUT := "res://assets/models/polyhaven/baked/plants/"
const PLANTS := {
	# Grass replaces the old procedural blades, so it is drawn by the thousand: keep it light.
	"grass_medium_01": [300, false, []],
	"grass_medium_02": [360, false, []],
	"grass_bermuda_01": [941, true, []],
	"dandelion_01": [1400, false, []],
	"celandine_01": [1000, false, []],
	"flower_heliophila": [2500, false, ["flower_heliophila_large", "flower_heliophila_medium"]],
	"nettle_plant": [1400, false, []],
	"weed_plant_02": [1000, false, []],
	"shrub_sorrel_01": [1600, true, []],
	"periwinkle_plant": [1400, false, []],
	"moss_01": [204, true, []],
	"fern_02": [1200, false, []],
	"shrub_02": [2200, false, []],
	"shrub_03": [1200, false, []],
	"shrub_04": [2400, false, []],
	"flower_empodium": [900, false, []],
	"flower_gazania": [1200, false, []],
	"flower_ursinia": [1200, false, []],
	"flower_stinkkruid": [1600, false, []],
}


func _bake_plants() -> int:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PLANT_OUTPUT))
	var manifest: Dictionary = {}
	var failures := 0
	for id in PLANTS:
		var job: Array = PLANTS[id]
		var scene := load(SOURCE + id + "/" + id + ".gltf") as PackedScene
		if scene == null:
			printerr("PLANT missing ", id)
			failures += 1
			continue
		var root: Node = scene.instantiate()
		var part_names: Array = []
		if bool(job[1]):
			part_names = [""]
		else:
			for candidate in root.find_children("*", "MeshInstance3D", true, false):
				if not (String(candidate.name) in job[2]):
					part_names.append(String(candidate.name))
		root.free()
		var variants: Array = []
		for part in part_names:
			var mesh: ArrayMesh = bake(id, part, int(job[0]))
			if mesh == null:
				continue
			_center_on_root(mesh)
			mesh = _with_lods(mesh)
			var file: String = "%s_%d.res" % [id, variants.size()]
			if ResourceSaver.save(mesh, PLANT_OUTPUT + file, ResourceSaver.FLAG_COMPRESS) == OK:
				var box: AABB = mesh.get_aabb()
				variants.append({"file": file, "height": box.size.y, "width": maxf(box.size.x, box.size.z)})
		manifest[id] = variants
		print("PLANT %-18s %d variants" % [id, variants.size()])
	var out := FileAccess.open(PLANT_OUTPUT + "manifest.json", FileAccess.WRITE)
	out.store_string(JSON.stringify(manifest, "\t"))
	return failures


## Adds automatic LODs (meshoptimizer) so distant plants draw a fraction of their triangles.
func _with_lods(mesh: ArrayMesh) -> ArrayMesh:
	var importer := ImporterMesh.new()
	for surface in mesh.get_surface_count():
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(surface), [], {}, mesh.surface_get_material(surface))
	importer.generate_lods(25.0, 60.0, [])
	var result: ArrayMesh = importer.get_mesh()
	return result if result != null else mesh


## Moves the mesh so its footprint is centred on the origin and its lowest point sits at y = 0.
func _center_on_root(mesh: ArrayMesh) -> void:
	var box: AABB = mesh.get_aabb()
	var shift := Vector3(-(box.position.x + box.size.x * 0.5), -box.position.y, -(box.position.z + box.size.z * 0.5))
	var surfaces: Array = []
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in vertices.size():
			vertices[i] += shift
		arrays[Mesh.ARRAY_VERTEX] = vertices
		surfaces.append([arrays, mesh.surface_get_material(surface)])
	mesh.clear_surfaces()
	for entry in surfaces:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, entry[0])
		mesh.surface_set_material(mesh.get_surface_count() - 1, entry[1])


func _initialize() -> void:
	if "--plants" in OS.get_cmdline_user_args():
		quit(1 if _bake_plants() > 0 else 0)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var failures := 0
	for name in JOBS:
		var job: Array = JOBS[name]
		var mesh: ArrayMesh = bake(String(job[0]), String(job[1]), int(job[2]))
		if mesh == null:
			printerr("BAKE failed: ", name)
			failures += 1
			continue
		var triangles := 0
		for surface in mesh.get_surface_count():
			triangles += mesh.surface_get_array_index_len(surface) / 3
		var error: int = ResourceSaver.save(mesh, OUTPUT + name + ".res", ResourceSaver.FLAG_COMPRESS)
		print("BAKE %-14s %6d triangles  %s" % [name, triangles, "saved" if error == OK else "SAVE ERROR %d" % error])
	quit(1 if failures > 0 else 0)


func bake(model_id: String, node_name: String, budget: int) -> ArrayMesh:
	var scene := load(SOURCE + model_id + "/" + model_id + ".gltf") as PackedScene
	if scene == null:
		return null
	var root: Node = scene.instantiate()
	var parts: Array = []
	for candidate in root.find_children("*", "MeshInstance3D", true, false):
		var instance := candidate as MeshInstance3D
		if instance.mesh == null or (node_name != "" and String(instance.name) != node_name):
			continue
		var transform := Transform3D.IDENTITY
		var walker: Node = instance
		while walker != null and walker != root:
			transform = (walker as Node3D).transform * transform
			walker = walker.get_parent()
		parts.append([instance.mesh, transform])
	if parts.is_empty():
		root.free()
		return null
	# Share the triangle budget between the parts by their size.
	var total_triangles := 0
	for part in parts:
		for surface in (part[0] as Mesh).get_surface_count():
			total_triangles += (part[0] as Mesh).surface_get_array_index_len(surface) / 3
	var result := ArrayMesh.new()
	for part in parts:
		var source: Mesh = part[0]
		var transform: Transform3D = part[1]
		for surface in source.get_surface_count():
			var arrays: Array = source.surface_get_arrays(surface)
			var triangles: int = source.surface_get_array_index_len(surface) / 3
			var share: int = maxi(24, int(float(budget) * float(triangles) / float(maxi(total_triangles, 1))))
			var reduced: Array = reduce(arrays, share)
			_apply_transform(reduced, transform)
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, reduced)
			result.surface_set_material(result.get_surface_count() - 1, source.surface_get_material(surface))
	root.free()
	return result


## The LOD of a surface closest to `budget` triangles (from meshoptimizer via ImporterMesh), with only the vertices it uses.
func reduce(arrays: Array, budget: int) -> Array:
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.size() / 3 <= budget:
		return arrays
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	importer.generate_lods(25.0, 60.0, [])
	var best: PackedInt32Array = indices
	for lod in importer.get_surface_lod_count(0):
		var candidate: PackedInt32Array = importer.get_surface_lod_indices(0, lod)
		if candidate.size() / 3 >= budget * 0.6 and absi(candidate.size() / 3 - budget) < absi(best.size() / 3 - budget):
			best = candidate
	# Keep only the vertices the chosen triangles use.
	var remap: Dictionary = {}
	var order: PackedInt32Array = PackedInt32Array()
	var new_indices := PackedInt32Array()
	new_indices.resize(best.size())
	for i in best.size():
		var old_index: int = best[i]
		if not remap.has(old_index):
			remap[old_index] = order.size()
			order.append(old_index)
		new_indices[i] = remap[old_index]
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	for slot in Mesh.ARRAY_MAX:
		var data = arrays[slot]
		if data == null or slot == Mesh.ARRAY_INDEX:
			continue
		var width: int = 1
		if slot == Mesh.ARRAY_TANGENT or slot == Mesh.ARRAY_BONES or slot == Mesh.ARRAY_WEIGHTS:
			width = 4
		var picked = data.duplicate()
		picked.resize(order.size() * width)
		for i in order.size():
			for k in width:
				picked[i * width + k] = data[order[i] * width + k]
		out[slot] = picked
	out[Mesh.ARRAY_INDEX] = new_indices
	return out


func _apply_transform(arrays: Array, transform: Transform3D) -> void:
	if transform == Transform3D.IDENTITY:
		return
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in vertices.size():
		vertices[i] = transform * vertices[i]
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if arrays[Mesh.ARRAY_NORMAL] != null:
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var normal_basis: Basis = transform.basis.inverse().transposed()
		for i in normals.size():
			normals[i] = (normal_basis * normals[i]).normalized()
		arrays[Mesh.ARRAY_NORMAL] = normals
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		for i in tangents.size() / 4:
			var turned: Vector3 = (transform.basis * Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])).normalized()
			tangents[i * 4] = turned.x
			tangents[i * 4 + 1] = turned.y
			tangents[i * 4 + 2] = turned.z
		arrays[Mesh.ARRAY_TANGENT] = tangents
