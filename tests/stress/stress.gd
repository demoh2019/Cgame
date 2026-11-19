extends SceneTree
## Deterministic, one-scenario-per-process Godot stress workload.
## Use run.py for watchdogs, repeatability, reporting and RSS limits.

signal sample_signal(value: int)

const PREFIX := "STRESS_RESULT:"
const ExtraStress := preload("res://extra_stress.gd")
const GridReflowStress := preload("res://grid_reflow.gd")
const BoxReflowStress := preload("res://box_reflow.gd")
const FlowReflowStress := preload("res://flow_reflow.gd")
const BitMapMorphologyStress := preload("res://bitmap_morphology.gd")
const PressureStress := preload("res://pressure_scenarios.gd")
const DensePhysicsStress := preload("res://physics_dense.gd")
const ImplicitDampingStress := preload("res://physics_implicit_damping_stress.gd")
const BoxSAT3DStress := preload("res://physics_box_box_sat_3d.gd")
const FaceClip3DStress := preload("res://physics_face_clip_3d.gd")
const SphereBox3DStress := preload("res://physics_sphere_box_3d.gd")
const BoxRadial3DStress := preload("res://physics_box_radial_axis_3d.gd")
const EmbeddedCircleRectangle2DStress := preload("res://physics_embedded_circle_rectangle_2d.gd")
const CoincidentCircles2DStress := preload("res://physics_coincident_circles_2d.gd")
const UniformFluidStress := preload("res://physics_uniform_fluid_stress.gd")
const PBFParticleFluidStress := preload("res://physics_pbf_particle_fluid_stress.gd")
const RectangleSAT2DStress := preload("res://physics_rectangle_shared_axes_2d.gd")
const PhysicsBlockSolver3DStress := preload("res://physics_block_solver_3d_stress.gd")
const LargeIsland3DStress := preload("res://physics_large_island_3d.gd")
const PhysicsLargeIslandStress := preload("res://physics_large_island_stress.gd")
const PhysicsFilterToggle := preload("res://physics_filter_toggle.gd")
const PhysicsSeparatedPairsStress := preload("res://physics_separated_pairs.gd")
const PhysicsCCDTightRotatingPairs := preload("res://physics_ccd_tight_rotating_pairs.gd")
const MotionFilterOverflow2D := preload("res://physics_motion_filter_overflow_2d.gd")
const MotionFilterOverflow3D := preload("res://physics_motion_filter_overflow_3d.gd")
const MotionExclusions3D := preload("res://physics_motion_exclusions_3d.gd")
const MotionExclusions2D := preload("res://physics_motion_exclusions_2d.gd")
const ExceptionPairs2D := preload("res://physics_exception_pairs_2d.gd")
const ExceptionPairs3D := preload("res://physics_exception_pairs_3d.gd")
const BVHStreaming2D := preload("res://physics_bvh_streaming_2d.gd")
const BVHStreaming3D := preload("res://physics_bvh_streaming_3d.gd")
const CompoundBatch2D := preload("res://physics_compound_filter_batch_2d.gd")
const CompoundBatch3D := preload("res://physics_compound_filter_batch_3d.gd")
const SoftBodyXPBDArea3D := preload("res://physics_soft_body_xpbd_area_3d.gd")
const SoftBodyXPBDVolume3D := preload("res://physics_soft_body_xpbd_volume_3d.gd")
const SoftBodyXPBDDihedral3D := preload("res://physics_soft_body_xpbd_dihedral_3d.gd")
const SoftBodySelfCollision3D := preload("res://physics_soft_body_self_collision_3d.gd")
const SoftBodyEdgeCollision3D := preload("res://physics_soft_body_edge_collision_3d.gd")
const SoftBodyCCD3D := preload("res://physics_soft_body_ccd_3d.gd")
const ContactAngularFriction3D := preload("res://physics_contact_angular_friction_3d.gd")
const OneWayOverflow2D := preload("res://physics_one_way_overflow_2d.gd")
const CachedAABBStress := preload("res://physics_proxy_same_aabb.gd")
const CanvasScenePerf := preload("res://canvas_scene_perf.gd")
const CASES := [
	"containers", "array_literals", "dictionary_snapshot", "strings", "script_vm", "math", "signals",
	"scene_tree", "packed_scene", "images", "json", "stream", "stream_bulk",
	"file_io", "threads", "physics_2d", "physics_contacts_zero_friction_2d", "physics_contacts_friction_2d", "physics_contact_manifolds_2d", "physics_contact_block_solver_2d", "physics_3d", "physics_damping_legacy_2d", "physics_damping_implicit_2d", "physics_damping_legacy_3d", "physics_damping_implicit_3d", "physics_box_box_axis_aligned_3d", "physics_box_box_rotated_3d", "physics_box_box_misaligned_3d", "physics_face_clip_dense_3d", "physics_face_clip_rotated_3d", "physics_sphere_box_identity_3d", "physics_sphere_box_rotated_3d", "physics_circle_rectangle_embedded_2d", "physics_circle_rectangle_exterior_2d", "physics_circles_coincident_2d", "physics_circles_offset_2d", "physics_fluid_2d_disabled", "physics_fluid_2d_enabled", "physics_fluid_3d_disabled", "physics_fluid_3d_enabled", "physics_pbf_3d_disabled", "physics_pbf_3d_enabled", "physics_rect_sat_axis_aligned_2d", "physics_rect_sat_shared_rotation_2d", "physics_rect_sat_misaligned_2d", "physics_box_capsule_near_3d", "physics_box_capsule_far_3d", "physics_box_cylinder_near_3d", "physics_box_cylinder_far_3d", "physics_block_solver_sequential_3d", "physics_block_solver_coupled_3d", "physics_frictionless_3d", "physics_soft_contacts_zero_friction_3d", "physics_soft_contacts_friction_3d", "physics_ccd_2d", "physics_ccd_rotational_radial_2d", "physics_ccd_rotational_tight_2d", "physics_ccd_rotational_radial_3d", "physics_ccd_rotational_tight_3d", "physics_separated_pairs_2d", "physics_separated_pairs_3d", "physics_dense_2d", "physics_dense_3d", "physics_pending_3d", "physics_ccd_3d", "physics_joint_chain_2d", "physics_large_island_serial_2d", "physics_large_island_parallel_2d", "physics_multi_island_serial_2d", "physics_multi_island_parallel_2d", "physics_joint_chain_3d", "physics_large_island_3d_serial", "physics_large_island_3d_parallel", "physics_large_island_3d_priority", "physics_large_island_3d_topology_serial", "physics_large_island_3d_topology_parallel", "physics_multi_island_3d_serial", "physics_multi_island_3d_parallel", "physics_multi_island_3d_two_large", "physics_sparse_2d", "physics_sparse_3d", "physics_proxy_same_aabb_2d", "physics_proxy_same_aabb_3d", "physics_proxies_2d", "physics_proxies_3d", "physics_rid_sparse_2d", "physics_rid_sparse_3d", "physics_rid_moving_2d", "physics_rid_moving_3d", "physics_restitution_2d", "physics_restitution_3d",
	"object_churn", "memory_churn", "astar_grid", "astar_grid_neighbors", "astar_grid_jps", "astar_grid_fill", "astar_grid_rebuild", "astar_relax_2d", "astar_relax_3d", "astar_graph", "tweens", "audio_buffers",
	"variant_codec", "packet_stream", "packet_tx_batch", "packet_rx_batch", "packet_variant_reuse", "ui_layout", "grid_reflow", "box_reflow", "flow_reflow", "render_2d", "render_3d", "render_ellipse_2d", "render_light_culling_3d",
	"resource_load",
	"input_map",
	"transform_hierarchy",
	"node_paths", "regex", "compression", "gzip_stream", "hashing",
	"resource_io", "astar_3d", "thread_contention",
	"geometry_2d", "mesh_build", "input_dispatch", "image_codec", "group_calls",
	"packed_arrays", "sorting", "animation_tracks", "physics_raycast_2d",
	"physics_raycast_3d", "render_multimesh_3d",
	"object_lifecycle", "scene_churn",
	"scene_reparent", "scene_move", "resource_roundtrip", "audio_bus_churn",
	"bitmap_rects", "bitmap_pipeline", "bitmap_morphology",
	"curve_tessellation_2d", "curve_tessellation_3d", "curve_bake", "curve_nearest",
	"canvas_transform_2d", "process_dispatch",
	"physics_filter_toggle_2d", "physics_filter_toggle_3d", "physics_motion_filter_overflow_2d", "physics_motion_filter_overflow_3d", "physics_motion_exclusions_3d", "physics_motion_exclusions_2d", "physics_exception_pairs_2d", "physics_exception_pairs_3d", "physics_bvh_streaming_2d", "physics_bvh_streaming_3d", "physics_compound_filter_batch_2d", "physics_compound_filter_batch_3d", "physics_soft_body_xpbd_area_3d", "physics_soft_body_xpbd_volume_3d", "physics_soft_body_xpbd_dihedral_3d", "physics_soft_body_self_collision_3d", "physics_soft_body_edge_collision_3d", "physics_soft_body_ccd_3d", "physics_contact_angular_friction_3d", "physics_one_way_overflow_2d",
]

var signal_total: int = 0


func _initialize() -> void:
	call_deferred("_execute")


func _execute() -> void:
	var selected := ""
	var scale := 1
	var frames := 30
	var seed := 12345
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			selected = argument.trim_prefix("--case=")
		elif argument.begins_with("--scale="):
			scale = int(argument.trim_prefix("--scale="))
		elif argument.begins_with("--frames="):
			frames = int(argument.trim_prefix("--frames="))
		elif argument.begins_with("--seed="):
			seed = int(argument.trim_prefix("--seed="))

	if not CASES.has(selected) or scale < 1 or scale > 1000 or frames < 1 or frames > 100000:
		printerr("Invalid stress arguments: case=", selected, ", scale=", scale, ", frames=", frames)
		quit(2)
		return

	var before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var started := Time.get_ticks_usec()
	var detail: Dictionary = await _run_case(selected, scale, frames, seed)
	var duration_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var after := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var failed := detail.has("error")
	var result := {
		"case": selected,
		"scale": scale,
		"frames": frames,
		"seed": seed,
		"duration_ms": duration_ms,
		"engine_memory_before_bytes": before,
		"engine_memory_after_bytes": after,
		"detail": detail,
	}
	print(PREFIX + JSON.stringify(result))
	quit(1 if failed else 0)


func _run_case(test_case: String, scale: int, frames: int, seed: int) -> Dictionary:
	match test_case:
		"object_churn":
			return _object_churn(scale)
		"array_literals":
			return _array_literals(scale)
		"dictionary_snapshot":
			return _dictionary_snapshot(scale)
		"containers":
			var length := 20000 * scale
			var array: Array[int] = []
			var dictionary: Dictionary = {}
			array.resize(length)
			for i in range(length):
				array[i] = i
				dictionary[i] = i ^ 0x5555
			var checksum := 0
			for i in range(length * 3):
				var index := (i * 4099) % length
				checksum = (checksum + array[index] + int(dictionary[index])) & 0x7fffffff
			dictionary.clear()
			array.clear()
			return {"operations": length * 5, "checksum": checksum}
		"strings":
			var checksum := 0
			for i in range(10000 * scale):
				var value := "stress:%08d:Red,Green,Blue" % i
				var split := value.split(":")
				checksum += split[1].length() + value.find("Green") + value.to_upper().length()
			return {"iterations": 10000 * scale, "checksum": checksum}
		"script_vm":
			var accumulator := 0
			var values: Array[int] = [3, 7, 11, 17, 23, 31, 41]
			for i in range(500000 * scale):
				var index := i % values.size()
				accumulator = (accumulator + values[index] * (i & 255)) & 0x7fffffff
				values[index] = (values[index] + 3) & 65535
			return {"operations": 500000 * scale, "checksum": accumulator}
		"math":
			var accumulator := 0.0
			var vec := Vector3(3.0, 4.0, 5.0)
			for i in range(50000 * scale):
				var rhs := Vector3(float(i & 63) + 1.0, 2.0, 3.0)
				vec = (vec + rhs.cross(Vector3.UP) * 0.0001).normalized() * 7.0
				accumulator += vec.dot(rhs)
			return {"operations": 50000 * scale, "checksum": accumulator}
		"signals":
			signal_total = 0
			sample_signal.connect(_on_sample)
			for i in range(50000 * scale):
				sample_signal.emit(i & 7)
			sample_signal.disconnect(_on_sample)
			return {"emissions": 50000 * scale, "checksum": signal_total}
		"scene_tree":
			var parent := Node.new()
			root.add_child(parent)
			var length := 1200 * scale
			for i in range(length):
				var node := Node2D.new()
				node.name = "StressNode%d" % i
				parent.add_child(node)
				node.add_to_group("stress_nodes")
			var found := parent.find_children("StressNode*", "Node2D", true, false)
			var total := found.size() + get_nodes_in_group("stress_nodes").size()
			parent.free()
			return {"nodes": length, "checksum": total}
		"packed_scene":
			var prototype := Node2D.new()
			for i in range(24):
				var child := Node2D.new()
				child.name = "Part%d" % i
				prototype.add_child(child)
				child.owner = prototype
			var packed := PackedScene.new()
			if packed.pack(prototype) != OK:
				prototype.free()
				return {"error": "Could not pack prototype"}
			prototype.free()
			var checksum := 0
			for i in range(150 * scale):
				var instance := packed.instantiate()
				if instance == null:
					return {"error": "Could not instantiate PackedScene"}
				checksum += instance.get_child_count()
				instance.free()
			return {"instances": 150 * scale, "checksum": checksum}
		"images":
			var checksum := 0
			for i in range(200 * scale):
				var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
				img.fill(Color(float(i & 255) / 255.0, 0.5, 0.25, 1.0))
				img.set_pixel(i % 128, int(i / 128) % 128, Color.WHITE)
				checksum += img.get_data().size()
			return {"images": 200 * scale, "checksum": checksum}
		"json":
			var objects: Array[Dictionary] = []
			for i in range(500 * scale):
				objects.append({"id": i, "name": "object_%d" % i, "position": [i, i + 1, i + 2]})
			var checksum := 0
			for i in range(10):
				var encoded := JSON.stringify(objects)
				var decoded = JSON.parse_string(encoded)
				if not (decoded is Array) or decoded.size() != objects.size():
					return {"error": "JSON roundtrip mismatch"}
				checksum += encoded.length()
			return {"records": objects.size(), "checksum": checksum}
		"stream":
			var peer := StreamPeerBuffer.new()
			var length := 20000 * scale
			for i in range(length):
				peer.put_32(i)
			peer.seek(0)
			var checksum := 0
			for i in range(length):
				var received := peer.get_32()
				if received != i:
					return {"error": "Stream corruption at %d" % i}
				checksum = (checksum + received) & 0x7fffffff
			return {"messages": length, "checksum": checksum}
		"stream_bulk":
			return _stream_bulk(scale)
		"file_io":
			return _file_io(scale)
		"object_lifecycle":
			return await _object_lifecycle(scale)
		"scene_churn":
			return await _scene_churn(scale)
		"scene_reparent":
			return PressureStress.new().scene_reparent(self, scale)
		"scene_move":
			return PressureStress.new().scene_move(self, scale)
		"resource_roundtrip":
			return PressureStress.new().resource_roundtrip(scale)
		"audio_bus_churn":
			return PressureStress.new().audio_bus_churn(scale)
		"threads":
			return _threads(scale, seed)
		"astar_grid":
			return _astar_grid(scale)
		"astar_grid_neighbors":
			return _astar_grid_neighbors(scale)
		"astar_grid_jps":
			return _astar_grid_jps(scale)
		"astar_grid_fill":
			return _astar_grid_fill(scale)
		"astar_grid_rebuild":
			return _astar_grid_rebuild(scale)
		"astar_relax_2d":
			return _astar_relax_2d(scale)
		"astar_relax_3d":
			return _astar_relax_3d(scale)
		"astar_graph":
			return _astar_graph(scale)
		"audio_buffers":
			return _audio_buffers(scale)
		"variant_codec":
			return _variant_codec(scale)
		"tweens":
			return await _tweens(scale, frames)
		"packet_stream":
			return _packet_stream(scale)
		"packet_tx_batch":
			return _packet_tx_batch(scale)
		"packet_rx_batch":
			return _packet_rx_batch(scale)
		"packet_variant_reuse":
			return _packet_variant_reuse(scale)
		"ui_layout":
			return await _ui_layout(scale, frames)
		"grid_reflow":
			return await GridReflowStress.new().run(self, scale, frames)
		"box_reflow":
			return await BoxReflowStress.new().run(self, scale, frames)
		"flow_reflow":
			return await FlowReflowStress.new().run(self, scale, frames)
		"physics_2d":
			return await _physics_2d(scale, frames)
		"physics_contacts_zero_friction_2d":
			return await _physics_contacts_2d(scale, frames, 0.0)
		"physics_contacts_friction_2d":
			return await _physics_contacts_2d(scale, frames, 1.0)
		"physics_contact_manifolds_2d":
			return await _physics_contact_manifolds_2d(scale, frames)
		"physics_contact_block_solver_2d":
			return await _physics_contact_manifolds_2d(scale, frames, true)
		"physics_3d":
			return await _physics_3d(scale, frames)
		"physics_damping_legacy_2d":
			return await ImplicitDampingStress.new().run_2d(self, scale, frames, false)
		"physics_damping_implicit_2d":
			return await ImplicitDampingStress.new().run_2d(self, scale, frames, true)
		"physics_damping_legacy_3d":
			return await ImplicitDampingStress.new().run_3d(self, scale, frames, false)
		"physics_damping_implicit_3d":
			return await ImplicitDampingStress.new().run_3d(self, scale, frames, true)
		"physics_box_box_axis_aligned_3d":
			return await BoxSAT3DStress.new().run(self, scale, frames, false)
		"physics_box_box_rotated_3d":
			return await BoxSAT3DStress.new().run(self, scale, frames, true)
		"physics_box_box_misaligned_3d":
			return await BoxSAT3DStress.new().run(self, scale, frames, true, true)
		"physics_face_clip_dense_3d":
			return await FaceClip3DStress.new().run(self, scale, frames, false)
		"physics_face_clip_rotated_3d":
			return await FaceClip3DStress.new().run(self, scale, frames, true)
		"physics_sphere_box_identity_3d":
			return await SphereBox3DStress.new().run(self, scale, frames, false)
		"physics_sphere_box_rotated_3d":
			return await SphereBox3DStress.new().run(self, scale, frames, true)
		"physics_circle_rectangle_embedded_2d":
			return await EmbeddedCircleRectangle2DStress.new().run(self, scale, frames, true)
		"physics_circle_rectangle_exterior_2d":
			return await EmbeddedCircleRectangle2DStress.new().run(self, scale, frames, false)
		"physics_circles_coincident_2d":
			return await CoincidentCircles2DStress.new().run(self, scale, frames, true)
		"physics_circles_offset_2d":
			return await CoincidentCircles2DStress.new().run(self, scale, frames, false)
		"physics_fluid_2d_disabled":
			return await UniformFluidStress.new().run(self, scale, frames, false, false)
		"physics_fluid_2d_enabled":
			return await UniformFluidStress.new().run(self, scale, frames, false, true)
		"physics_fluid_3d_disabled":
			return await UniformFluidStress.new().run(self, scale, frames, true, false)
		"physics_fluid_3d_enabled":
			return await UniformFluidStress.new().run(self, scale, frames, true, true)
		"physics_pbf_3d_disabled":
			return await PBFParticleFluidStress.new().run(self, scale, frames, false)
		"physics_pbf_3d_enabled":
			return await PBFParticleFluidStress.new().run(self, scale, frames, true)
		"physics_rect_sat_axis_aligned_2d":
			return await RectangleSAT2DStress.new().run(self, scale, frames, 0)
		"physics_rect_sat_shared_rotation_2d":
			return await RectangleSAT2DStress.new().run(self, scale, frames, 1)
		"physics_rect_sat_misaligned_2d":
			return await RectangleSAT2DStress.new().run(self, scale, frames, 2)
		"physics_box_capsule_near_3d":
			return await BoxRadial3DStress.new().run(self, scale, frames, true, false)
		"physics_box_capsule_far_3d":
			return await BoxRadial3DStress.new().run(self, scale, frames, true, true)
		"physics_box_cylinder_near_3d":
			return await BoxRadial3DStress.new().run(self, scale, frames, false, false)
		"physics_box_cylinder_far_3d":
			return await BoxRadial3DStress.new().run(self, scale, frames, false, true)
		"physics_block_solver_sequential_3d":
			return await PhysicsBlockSolver3DStress.new().run(self, scale, frames, false)
		"physics_block_solver_coupled_3d":
			return await PhysicsBlockSolver3DStress.new().run(self, scale, frames, true)
		"physics_frictionless_3d":
			return await _physics_3d(scale, frames, true)
		"physics_soft_contacts_zero_friction_3d":
			return await _physics_soft_contacts_3d(scale, frames, true)
		"physics_soft_contacts_friction_3d":
			return await _physics_soft_contacts_3d(scale, frames, false)
		"physics_ccd_2d":
			return await _physics_ccd_2d(scale, frames)
		"physics_ccd_rotational_radial_2d":
			return await PhysicsCCDTightRotatingPairs.new().run(self, scale, frames, 2, false)
		"physics_ccd_rotational_tight_2d":
			return await PhysicsCCDTightRotatingPairs.new().run(self, scale, frames, 2, true)
		"physics_ccd_rotational_radial_3d":
			return await PhysicsCCDTightRotatingPairs.new().run(self, scale, frames, 3, false)
		"physics_ccd_rotational_tight_3d":
			return await PhysicsCCDTightRotatingPairs.new().run(self, scale, frames, 3, true)
		"physics_separated_pairs_2d":
			return await PhysicsSeparatedPairsStress.new().run(self, scale, frames, 2)
		"physics_separated_pairs_3d":
			return await PhysicsSeparatedPairsStress.new().run(self, scale, frames, 3)
		"physics_dense_2d":
			return await DensePhysicsStress.new().run_2d(self, scale, frames)
		"physics_dense_3d":
			return await DensePhysicsStress.new().run_3d(self, scale, frames)
		"physics_pending_3d":
			return DensePhysicsStress.new().run_pending_3d(scale)
		"physics_ccd_3d":
			return await _physics_ccd_3d(scale, frames)
		"physics_joint_chain_2d":
			return await _physics_joint_chain_2d(scale, frames)
		"physics_large_island_serial_2d":
			return await PhysicsLargeIslandStress.new().run(self, scale, frames, false)
		"physics_large_island_parallel_2d":
			return await PhysicsLargeIslandStress.new().run(self, scale, frames, true)
		"physics_multi_island_serial_2d":
			return await PhysicsLargeIslandStress.new().run(self, scale, frames, false, 2, 48)
		"physics_multi_island_parallel_2d":
			return await PhysicsLargeIslandStress.new().run(self, scale, frames, true, 2, 48)
		"physics_joint_chain_3d":
			return await _physics_joint_chain_3d(scale, frames)
		"physics_large_island_3d_serial":
			return await LargeIsland3DStress.new().run(self, scale, frames, false)
		"physics_large_island_3d_parallel":
			return await LargeIsland3DStress.new().run(self, scale, frames, true)
		"physics_large_island_3d_priority":
			return await LargeIsland3DStress.new().run(self, scale, frames, true, true)
		"physics_large_island_3d_topology_serial":
			return await LargeIsland3DStress.new().run(self, scale, maxi(frames, 52), false, false, 0, 16, true)
		"physics_large_island_3d_topology_parallel":
			return await LargeIsland3DStress.new().run(self, scale, maxi(frames, 52), true, false, 0, 16, true)
		"physics_multi_island_3d_serial":
			return await LargeIsland3DStress.new().run(self, scale, frames, false, false, 20, 16)
		"physics_multi_island_3d_parallel":
			return await LargeIsland3DStress.new().run(self, scale, frames, true, false, 20, 16)
		"physics_multi_island_3d_two_large":
			return await LargeIsland3DStress.new().run(self, scale, frames, true, false, 1, 320)
		"physics_proxy_same_aabb_2d":
			return await _physics_proxy_same_aabb_2d(scale, frames)
		"physics_proxy_same_aabb_3d":
			return await _physics_proxy_same_aabb_3d(scale, frames)
		"physics_proxies_2d":
			return await _physics_proxies_2d(scale)
		"physics_proxies_3d":
			return await _physics_proxies_3d(scale)
		"physics_sparse_2d":
			return await _physics_sparse_2d(scale, frames)
		"physics_sparse_3d":
			return await _physics_sparse_3d(scale, frames)
		"physics_rid_sparse_2d":
			return await _physics_rid_sparse_2d(scale, frames)
		"physics_rid_sparse_3d":
			return await _physics_rid_sparse_3d(scale, frames)
		"physics_rid_moving_2d":
			return await _physics_rid_sparse_2d(scale, frames, true)
		"physics_rid_moving_3d":
			return await _physics_rid_sparse_3d(scale, frames, true)
		"physics_restitution_2d":
			return await _physics_restitution_2d()
		"physics_restitution_3d":
			return await _physics_restitution_3d()
		"memory_churn":
			return await _memory_churn(scale)
		"render_2d":
			return await _render_2d(scale, frames)
		"render_ellipse_2d":
			return _render_ellipse_2d(scale)
		"render_3d":
			return await _render_3d(scale, frames)
		"render_light_culling_3d":
			return await _render_light_culling_3d(scale, frames)
		"resource_load":
			return _resource_load(scale)
		"input_map":
			return _input_map(scale)
		"transform_hierarchy":
			return _transform_hierarchy(scale)
		"node_paths":
			return _node_paths(scale)
		"regex":
			return _regex(scale)
		"compression":
			return _compression(scale)
		"gzip_stream":
			return _gzip_stream(scale)
		"hashing":
			return _hashing(scale)
		"resource_io":
			return _resource_io(scale)
		"astar_3d":
			return _astar_3d(scale)
		"thread_contention":
			return _thread_contention(scale)
		"geometry_2d", "mesh_build", "input_dispatch", "image_codec", "group_calls":
			return ExtraStress.new().run(test_case, self, scale)
		"packed_arrays":
			return _packed_arrays(scale)
		"sorting":
			return _sorting(scale)
		"animation_tracks":
			return _animation_tracks(scale)
		"physics_raycast_2d":
			return await _physics_raycast_2d(scale)
		"physics_raycast_3d":
			return await _physics_raycast_3d(scale)
		"render_multimesh_3d":
			return await _render_multimesh_3d(scale, frames)
		"bitmap_rects":
			return _bitmap_rects(scale)
		"bitmap_pipeline":
			return _bitmap_pipeline(scale)
		"bitmap_morphology":
			return BitMapMorphologyStress.new().run(scale)
		"curve_tessellation_2d":
			return _curve_tessellation_2d(scale)
		"curve_tessellation_3d":
			return _curve_tessellation_3d(scale)
		"curve_bake":
			return _curve_bake(scale)
		"curve_nearest":
			return _curve_nearest(scale)
		"canvas_transform_2d":
			return CanvasScenePerf.new().canvas_transform(self, scale)
		"process_dispatch":
			return await CanvasScenePerf.new().process_dispatch(self, scale, frames)
		"physics_filter_toggle_2d":
			return await PhysicsFilterToggle.new().run_2d(self, scale, frames)
		"physics_filter_toggle_3d":
			return await PhysicsFilterToggle.new().run_3d(self, scale, frames)
		"physics_motion_filter_overflow_2d":
			return await MotionFilterOverflow2D.new().run(self, scale, frames)
		"physics_motion_filter_overflow_3d":
			return await MotionFilterOverflow3D.new().run(self, scale, frames)
		"physics_motion_exclusions_3d":
			return await MotionExclusions3D.new().run(self, scale, frames)
		"physics_motion_exclusions_2d":
			return await MotionExclusions2D.new().run(self, scale, frames)
		"physics_exception_pairs_2d":
			return await ExceptionPairs2D.new().run(self, scale, frames)
		"physics_exception_pairs_3d":
			return await ExceptionPairs3D.new().run(self, scale, frames)
		"physics_bvh_streaming_2d":
			return await BVHStreaming2D.new().run(self, scale, frames)
		"physics_bvh_streaming_3d":
			return await BVHStreaming3D.new().run(self, scale, frames)
		"physics_compound_filter_batch_2d":
			return await CompoundBatch2D.new().run(self, scale, frames)
		"physics_compound_filter_batch_3d":
			return await CompoundBatch3D.new().run(self, scale, frames)
		"physics_soft_body_xpbd_area_3d":
			return await SoftBodyXPBDArea3D.new().run(self, scale, frames)
		"physics_soft_body_xpbd_volume_3d":
			return await SoftBodyXPBDVolume3D.new().run(self, scale, frames)
		"physics_soft_body_xpbd_dihedral_3d":
			return await SoftBodyXPBDDihedral3D.new().run(self, scale, frames)
		"physics_soft_body_self_collision_3d":
			return await SoftBodySelfCollision3D.new().run(self, scale, frames)
		"physics_soft_body_edge_collision_3d":
			return await SoftBodyEdgeCollision3D.new().run(self, scale, frames)
		"physics_soft_body_ccd_3d":
			return await SoftBodyCCD3D.new().run(self, scale, frames)
		"physics_contact_angular_friction_3d":
			return await ContactAngularFriction3D.new().run(self, scale, frames)
		"physics_one_way_overflow_2d":
			return await OneWayOverflow2D.new().run(self, scale, frames)
	return {"error": "Unhandled case"}


func _frame_statistics(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {}
	samples.sort()
	var count := samples.size()
	return {
		"count": count,
		"p50": samples[int(float(count - 1) * 0.5)],
		"p95": samples[clampi(ceili(float(count) * 0.95) - 1, 0, count - 1)],
		"p99": samples[clampi(ceili(float(count) * 0.99) - 1, 0, count - 1)],
		"max": samples.back(),
	}


func _object_lifecycle(scale: int) -> Dictionary:
	var samples: Array[int] = []
	var checksum := 0
	for cycle in range(12):
		var objects: Array[RefCounted] = []
		for i in range(1000 * scale):
			objects.append(RefCounted.new())
		checksum += objects.size()
		objects.clear()
		await process_frame
		samples.append(int(Performance.get_monitor(Performance.MEMORY_STATIC)))
	return {"objects_created": checksum, "memory_samples_bytes": samples,
		"retained_growth_bytes": samples.back() - samples[2]}


func _scene_churn(scale: int) -> Dictionary:
	var max_memory := 0
	var checksum := 0
	var readings: Array[int] = []
	for cycle in range(30):
		var world := Node2D.new()
		root.add_child(world)
		for i in range(80 * scale):
			var child := Node2D.new()
			child.name = "Churn%d" % i
			world.add_child(child)
		checksum += world.get_child_count()
		world.free()
		await process_frame
		var retained_bytes := int(Performance.get_monitor(Performance.MEMORY_STATIC))
		readings.append(retained_bytes)
		max_memory = maxi(max_memory, retained_bytes)
	return {"nodes_created_and_freed": checksum, "cycles": 30,
		"peak_engine_static_bytes": max_memory, "retained_growth_bytes": readings.back() - readings[2]}


func _on_sample(value: int) -> void:
	signal_total += value


func _file_io(scale: int) -> Dictionary:
	var path := "user://stress_file_io.bin"
	var payload := PackedByteArray()
	payload.resize(1024 * 1024)
	for i in range(payload.size()):
		payload[i] = i & 255
	var checksum := 0
	for i in range(8 * scale):
		var output := FileAccess.open(path, FileAccess.WRITE)
		if output == null:
			return {"error": "Could not open file for write"}
		output.store_buffer(payload)
		output.close()
		var input := FileAccess.open(path, FileAccess.READ)
		if input == null:
			return {"error": "Could not open file for read"}
		var data := input.get_buffer(payload.size())
		input.close()
		if data.size() != payload.size() or data[0] != 0 or data[data.size() - 1] != 255:
			return {"error": "File roundtrip failed"}
		checksum += data.size()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return {"bytes_written_and_read": checksum * 2, "checksum": checksum}


func _thread_task(iterations: int, initial: int) -> int:
	var accumulator := initial & 0x7fffffff
	for i in range(iterations):
		accumulator = (accumulator * 1664525 + 1013904223 + i) & 0x7fffffff
	return accumulator


func _threads(scale: int, seed: int) -> Dictionary:
	var workers: Array[Thread] = []
	var count := mini(16, maxi(2, OS.get_processor_count()))
	for i in range(count):
		var worker := Thread.new()
		if worker.start(Callable(self, "_thread_task").bind(100000 * scale, seed + i)) != OK:
			for active in workers:
				active.wait_to_finish()
			return {"error": "Could not start worker thread"}
		workers.append(worker)
	var checksum := 0
	for worker in workers:
		checksum = (checksum + int(worker.wait_to_finish())) & 0x7fffffff
	return {"workers": count, "operations": count * 100000 * scale, "checksum": checksum}


func _astar_grid(scale: int) -> Dictionary:
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, 64, 64)
	astar.cell_size = Vector2.ONE
	astar.update()
	for y in range(64):
		if y != 32:
			astar.set_point_solid(Vector2i(32, y))
	var checksum := 0
	for i in range(100 * scale):
		var origin := Vector2i(i % 20, (i * 7) % 64)
		var destination := Vector2i(63 - (i % 20), 63 - ((i * 11) % 64))
		var path := astar.get_id_path(origin, destination)
		if path.is_empty() or path[0] != origin or path.back() != destination:
			return {"error": "AStar path missing or incorrect"}
		checksum += path.size()
	return {"searches": 100 * scale, "checksum": checksum}


func _audio_buffers(scale: int) -> Dictionary:
	var checksum := 0
	for k in range(50 * scale):
		var wave := PackedByteArray()
		wave.resize(16384)
		for i in range(8192):
			wave[i * 2] = (i + k) & 255
			wave[i * 2 + 1] = (i >> 8) & 255
		var audio := AudioStreamWAV.new()
		audio.format = AudioStreamWAV.FORMAT_16_BITS
		audio.mix_rate = 44100
		audio.stereo = false
		audio.data = wave
		if audio.get_length() <= 0.0:
			return {"error": "Invalid audio buffer length"}
		checksum += audio.data.size()
	return {"buffers": 50 * scale, "checksum": checksum}


func _variant_codec(scale: int) -> Dictionary:
	var value := {
		"names": PackedStringArray(["scene", "physics", "render"]),
		"positions": PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)]),
		"payload": PackedByteArray([1, 2, 3, 4, 5]),
		"nested": {"flag": true, "count": 42},
	}
	var checksum := 0
	for i in range(2000 * scale):
		var encoded := var_to_bytes(value)
		var decoded = bytes_to_var(encoded)
		if not (decoded is Dictionary) or decoded["nested"]["count"] != 42:
			return {"error": "Variant roundtrip mismatch"}
		checksum += encoded.size()
	return {"roundtrips": 2000 * scale, "checksum": checksum}


func _tweens(scale: int, frames: int) -> Dictionary:
	var world := Node2D.new()
	root.add_child(world)
	var count := 300 * scale
	for i in range(count):
		var node := Node2D.new()
		world.add_child(node)
		var tween := node.create_tween()
		tween.set_loops()
		tween.tween_property(node, "position", Vector2(float(i & 31), 20.0), 0.1)
		tween.tween_property(node, "position", Vector2.ZERO, 0.1)
	var peak_frame_ms := 0.0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for i in range(frames):
		await process_frame
		var frame_tick := Time.get_ticks_usec()
		frame_intervals.append(float(frame_tick - last_tick) / 1000.0)
		last_tick = frame_tick
		peak_frame_ms = maxf(peak_frame_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	world.queue_free()
	await process_frame
	var frame_statistics := _frame_statistics(frame_intervals)
	return {"active_tweens": count, "frames": frames, "peak_frame_ms": peak_frame_ms, "frame_interval_ms": frame_statistics, "frame_p95_ms": frame_statistics["p95"]}



func _packet_stream(scale: int) -> Dictionary:
	# Exercises the framing and ring-buffer path, including boundary sizes.
	var checksum := 0
	var lengths := PackedInt32Array([1, 7, 64, 1024, 8191, 16384])
	for i in range(120 * scale):
		var length := lengths[i % lengths.size()]
		var payload := PackedByteArray()
		payload.resize(length)
		for j in range(length):
			payload[j] = (i * 17 + j * 29) & 255
		var memory_stream := StreamPeerBuffer.new()
		var packet_peer := PacketPeerStream.new()
		packet_peer.input_buffer_max_size = 32768
		packet_peer.output_buffer_max_size = 32768
		packet_peer.stream_peer = memory_stream
		if packet_peer.put_packet(payload) != OK:
			return {"error": "Packet write failed at %d" % i}
		memory_stream.seek(0)
		var received := packet_peer.get_packet()
		if packet_peer.get_packet_error() != OK or received != payload:
			return {"error": "Packet corruption at %d (%d bytes)" % [i, length]}
		checksum += received.size()
	return {"packets": 120 * scale, "bytes": checksum, "checksum": checksum}


func _ui_layout(scale: int, frames: int) -> Dictionary:
	var viewport_ui := PanelContainer.new()
	viewport_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(viewport_ui)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(800, 600)
	viewport_ui.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 12
	scroll.add_child(grid)
	var length := 250 * scale
	for i in range(length):
		var button := Button.new()
		button.text = "Test Button %05d" % i
		button.custom_minimum_size = Vector2(120, 24)
		grid.add_child(button)
	var peak_frame_ms := 0.0
	for frame in range(frames):
		if frame % 8 == 0:
			grid.columns = 8 + (frame % 16)
		await process_frame
		peak_frame_ms = maxf(peak_frame_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	viewport_ui.queue_free()
	await process_frame
	return {"controls": length, "frames": frames, "peak_frame_ms": peak_frame_ms}



func _physics_2d(scale: int, frames: int) -> Dictionary:
	var world := Node2D.new()
	root.add_child(world)
	var circle := CircleShape2D.new()
	circle.radius = 4.0
	var length := 180 * scale
	for i in range(length):
		var body := RigidBody2D.new()
		body.position = Vector2(float(i % 40) * 7.0, float(i / 40) * 7.0)
		var collider := CollisionShape2D.new()
		collider.shape = circle
		body.add_child(collider)
		world.add_child(body)
	var peak_physics_ms := 0.0
	var peak_pairs := 0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for i in range(frames):
		await physics_frame
		var frame_tick := Time.get_ticks_usec()
		frame_intervals.append(float(frame_tick - last_tick) / 1000.0)
		last_tick = frame_tick
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))
	world.queue_free()
	await process_frame
	var frame_statistics := _frame_statistics(frame_intervals)
	return {"bodies": length, "physics_frames": frames, "peak_physics_ms": peak_physics_ms, "peak_collision_pairs": peak_pairs, "frame_interval_ms": frame_statistics, "frame_p95_ms": frame_statistics["p95"]}


# Dense low-level 2D contact benchmarks avoid SceneTree overhead. Each scenario
# uses identical geometry and a fixed friction coefficient, with sleeping
# disabled. Use same-hardware before/after builds to measure solver changes.
func _physics_contacts_2d(scale: int, frames: int, friction: float) -> Dictionary:
	var space := PhysicsServer2D.space_create()
	var floor_shape := PhysicsServer2D.rectangle_shape_create()
	var circle_shape := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(floor_shape, Vector2(40.0, 0.7))
	PhysicsServer2D.shape_set_data(circle_shape, 0.55)

	var floor := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(floor, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(floor, floor_shape)
	PhysicsServer2D.body_set_param(floor, PhysicsServer2D.BODY_PARAM_FRICTION, friction)
	PhysicsServer2D.body_set_space(floor, space)

	var count := 128 * scale
	var bodies: Array[RID] = []
	bodies.resize(count)
	for i in range(count):
		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(body, circle_shape)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_FRICTION, friction)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		# Raw GodotSpace2D defaults to -Y gravity; fall onto the +Y floor.
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, -1.0)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, Vector2(float(i % 64) - 31.5, -1.35 - float(int(i / 64)) * 1.05)))
		PhysicsServer2D.body_set_space(body, space)
		bodies[i] = body

	PhysicsServer2D.space_set_active(space, true)
	var peak_physics_ms := 0.0
	var peak_pairs := 0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for i in range(frames):
		await physics_frame
		var now := Time.get_ticks_usec()
		frame_intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))

	var probe: Transform2D = PhysicsServer2D.body_get_state(bodies[0], PhysicsServer2D.BODY_STATE_TRANSFORM)
	var state_valid := probe.origin.is_finite()
	PhysicsServer2D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	bodies.clear()
	PhysicsServer2D.free_rid(floor)
	PhysicsServer2D.free_rid(circle_shape)
	PhysicsServer2D.free_rid(floor_shape)
	PhysicsServer2D.free_rid(space)

	var stats := _frame_statistics(frame_intervals)
	return {"bodies": count, "friction": friction, "physics_frames": frames,
		"peak_physics_ms": peak_physics_ms, "peak_collision_pairs": peak_pairs,
		"frame_interval_ms": stats, "frame_p95_ms": stats["p95"], "state_valid": state_valid}


# Persistent 2-point box manifolds. This case complements the circle stress
# scenarios: contact point order can change as boxes rotate and slide.
func _physics_contact_manifolds_2d(scale: int, frames: int, block_solver: bool = false) -> Dictionary:
	# A new physics space reads the block solver mode at its creation.
	var setting := "physics/2d/solver/block_solver_enabled"
	var original_setting: Variant = ProjectSettings.get_setting(setting, false)
	ProjectSettings.set_setting(setting, block_solver)
	var space := PhysicsServer2D.space_create()
	var floor_shape := PhysicsServer2D.rectangle_shape_create()
	var box_shape := PhysicsServer2D.rectangle_shape_create()
	PhysicsServer2D.shape_set_data(floor_shape, Vector2(60.0, 0.7))
	PhysicsServer2D.shape_set_data(box_shape, Vector2(0.7, 0.45))

	var floor := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(floor, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(floor, floor_shape)
	PhysicsServer2D.body_set_param(floor, PhysicsServer2D.BODY_PARAM_FRICTION, 0.8)
	PhysicsServer2D.body_set_space(floor, space)

	var count := 128 * scale
	var bodies: Array[RID] = []
	bodies.resize(count)
	for i in range(count):
		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(body, box_shape)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_FRICTION, 0.8)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		# Raw GodotSpace2D defaults to -Y gravity; fall onto the +Y floor.
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, -1.0)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, Vector2(float(i % 64) * 1.65 - 52.0, -1.20 - float(int(i / 64)) * 0.94)))
		if i % 2 == 0:
			PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, 0.1)
			PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2(0.06, 0.0))
		else:
			PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, -0.1)
			PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2(-0.06, 0.0))
		PhysicsServer2D.body_set_space(body, space)
		bodies[i] = body

	PhysicsServer2D.space_set_active(space, true)
	var peak_physics_ms := 0.0
	var peak_pairs := 0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for i in range(frames):
		await physics_frame
		var now := Time.get_ticks_usec()
		frame_intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))

	var probe: Transform2D = PhysicsServer2D.body_get_state(bodies[0], PhysicsServer2D.BODY_STATE_TRANSFORM)
	var state_valid := probe.origin.is_finite()
	PhysicsServer2D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	bodies.clear()
	PhysicsServer2D.free_rid(floor)
	PhysicsServer2D.free_rid(box_shape)
	PhysicsServer2D.free_rid(floor_shape)
	PhysicsServer2D.free_rid(space)
	ProjectSettings.set_setting(setting, original_setting)

	var stats := _frame_statistics(frame_intervals)
	return {"bodies": count, "block_solver_enabled": block_solver, "physics_frames": frames,
		"peak_physics_ms": peak_physics_ms, "peak_collision_pairs": peak_pairs,
		"frame_interval_ms": stats, "frame_p95_ms": stats["p95"], "state_valid": state_valid}


func _physics_3d(scale: int, frames: int, p_frictionless: bool = false) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var sphere := SphereShape3D.new()
	sphere.radius = 0.6
	var frictionless_material := PhysicsMaterial.new()
	frictionless_material.friction = 0.0
	var length := 100 * scale
	for i in range(length):
		var body := RigidBody3D.new()
		if p_frictionless:
			body.physics_material_override = frictionless_material
		body.position = Vector3(float(i % 20), float(i / 20), 0.0)
		var collider := CollisionShape3D.new()
		collider.shape = sphere
		body.add_child(collider)
		world.add_child(body)
	var peak_physics_ms := 0.0
	var peak_pairs := 0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for i in range(frames):
		await physics_frame
		var frame_tick := Time.get_ticks_usec()
		frame_intervals.append(float(frame_tick - last_tick) / 1000.0)
		last_tick = frame_tick
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
	world.queue_free()
	await process_frame
	var frame_statistics := _frame_statistics(frame_intervals)
	return {"bodies": length, "physics_frames": frames, "peak_physics_ms": peak_physics_ms, "peak_collision_pairs": peak_pairs, "frame_interval_ms": frame_statistics, "frame_p95_ms": frame_statistics["p95"]}




# Stress 2D CCD ray casts where the first leading support misses a target
# but the second support intersects it. Isolated lanes avoid unrelated pairs.

# Dense rigid/soft contacts: compare the hot paths with and without friction.
# A separate soft mesh is used per lane so no cross-lane interaction is needed.
func _physics_soft_contacts_3d(scale: int, frames: int, frictionless: bool) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var mesh := SphereMesh.new()
	mesh.radius = 0.75
	mesh.height = 1.5
	mesh.radial_segments = 8
	mesh.rings = 4
	var rigid_shape := SphereShape3D.new()
	rigid_shape.radius = 0.5
	var material := PhysicsMaterial.new()
	material.friction = 0.0 if frictionless else 0.8

	var count := 16 * scale
	var soft_bodies: Array[SoftBody3D] = []
	var rigid_bodies: Array[RigidBody3D] = []
	soft_bodies.resize(count)
	rigid_bodies.resize(count)
	for i in range(count):
		var lane_x := float(i) * 4.0
		var soft := SoftBody3D.new()
		soft.mesh = mesh
		soft.simulation_precision = 3
		soft.total_mass = 1.0
		soft.position = Vector3(lane_x, 2.1, 0.0)
		world.add_child(soft)
		soft_bodies[i] = soft

		var body := RigidBody3D.new()
		body.gravity_scale = 0.0
		body.can_sleep = false
		body.physics_material_override = material
		body.position = Vector3(lane_x, 3.1, 0.0)
		var collider := CollisionShape3D.new()
		collider.shape = rigid_shape
		body.add_child(collider)
		world.add_child(body)
		body.linear_velocity = Vector3(0.0, -0.25, 0.0)
		rigid_bodies[i] = body

	var peak_physics_ms := 0.0
	var peak_pairs := 0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for frame in range(frames):
		await physics_frame
		var now := Time.get_ticks_usec()
		frame_intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))

	# Sample different lanes to catch numerical failures across a larger grid.
	var state_valid := true
	for index in [0, int(count / 2), count - 1]:
		var point: Vector3 = soft_bodies[index].get_point_transform(0)
		var body: RigidBody3D = rigid_bodies[index]
		if not point.is_finite() or not body.position.is_finite() or not body.linear_velocity.is_finite():
			state_valid = false
	world.queue_free()
	await process_frame
	if not state_valid:
		return {"error": "Rigid/soft 3D contacts produced non-finite positions or velocities", "frictionless": frictionless}
	if peak_pairs == 0:
		return {"error": "Rigid/soft 3D benchmark did not generate collision pairs", "frictionless": frictionless}
	var stats := _frame_statistics(frame_intervals)
	return {"soft_bodies": count, "rigid_bodies": count, "frictionless": frictionless, "physics_frames": frames,
			"peak_physics_ms": peak_physics_ms, "peak_collision_pairs": peak_pairs,
			"frame_interval_ms": stats, "frame_p95_ms": stats["p95"], "state_valid": state_valid}



func _physics_ccd_2d(scale: int, frames: int) -> Dictionary:
	var world := Node2D.new()
	root.add_child(world)
	var projectile_shape := RectangleShape2D.new()
	projectile_shape.size = Vector2(0.7, 3.0)
	var target_shape := CircleShape2D.new()
	target_shape.radius = 0.3
	var count := 64 * scale
	var projectiles: Array[RigidBody2D] = []
	projectiles.resize(count)

	for i in range(count):
		var lane_y := float(i) * 4.0
		var target := StaticBody2D.new()
		target.position = Vector2(0.0, lane_y - 1.5)
		var target_collider := CollisionShape2D.new()
		target_collider.shape = target_shape
		target.add_child(target_collider)
		world.add_child(target)

		var body := RigidBody2D.new()
		body.gravity_scale = 0.0
		body.can_sleep = false
		body.continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
		body.position = Vector2(-3.5, lane_y)
		var body_collider := CollisionShape2D.new()
		body_collider.shape = projectile_shape
		body.add_child(body_collider)
		world.add_child(body)
		projectiles[i] = body

	var peak_physics_ms := 0.0
	var peak_pairs := 0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for frame in range(frames):
		for i in range(count):
			var body := projectiles[i]
			body.global_position = Vector2(-3.5, float(i) * 4.0)
			body.linear_velocity = Vector2(420.0, 0.0)
			body.angular_velocity = 0.0
		await physics_frame
		var frame_tick := Time.get_ticks_usec()
		frame_intervals.append(float(frame_tick - last_tick) / 1000.0)
		last_tick = frame_tick
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))

	world.queue_free()
	await process_frame
	var frame_statistics := _frame_statistics(frame_intervals)
	return {"projectiles": count, "targets": count, "physics_frames": frames,
			"ccd_enabled": true, "peak_physics_ms": peak_physics_ms,
			"peak_collision_pairs": peak_pairs, "frame_interval_ms": frame_statistics,
			"frame_p95_ms": frame_statistics["p95"]}


# Repeated high-velocity CCD casts against isolated static targets.
# One projectile + one thin static collider per lane, with no cross-lane pairs.
# Resetting projectiles each frame ensures the CCD path stays hot rather than
# measuring mostly resting contacts after the first hit.
func _physics_ccd_3d(scale: int, frames: int) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var projectile_shape := BoxShape3D.new()
	projectile_shape.size = Vector3(0.4, 0.4, 0.4)
	var target_shape := BoxShape3D.new()
	target_shape.size = Vector3(0.25, 1.0, 1.0)
	var count := 64 * scale
	var projectiles: Array[RigidBody3D] = []
	projectiles.resize(count)

	for i in range(count):
		var lane_y := float(i) * 3.0
		var wall := StaticBody3D.new()
		wall.position = Vector3(0.0, lane_y, 0.0)
		var wall_collider := CollisionShape3D.new()
		wall_collider.shape = target_shape
		wall.add_child(wall_collider)
		world.add_child(wall)

		var body := RigidBody3D.new()
		body.gravity_scale = 0.0
		body.can_sleep = false
		body.continuous_cd = true
		body.position = Vector3(-3.5, lane_y, 0.0)
		var body_collider := CollisionShape3D.new()
		body_collider.shape = projectile_shape
		body.add_child(body_collider)
		world.add_child(body)
		projectiles[i] = body

	var peak_physics_ms := 0.0
	var peak_pairs := 0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for frame in range(frames):
		for i in range(count):
			var body := projectiles[i]
			body.global_position = Vector3(-3.5, float(i) * 3.0, 0.0)
			body.linear_velocity = Vector3(420.0, 0.0, 0.0)
			body.angular_velocity = Vector3.ZERO
		await physics_frame
		var frame_tick := Time.get_ticks_usec()
		frame_intervals.append(float(frame_tick - last_tick) / 1000.0)
		last_tick = frame_tick
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))

	world.queue_free()
	await process_frame
	var frame_statistics := _frame_statistics(frame_intervals)
	return {"projectiles": count, "targets": count, "physics_frames": frames,
			"ccd_enabled": true, "peak_physics_ms": peak_physics_ms,
			"peak_collision_pairs": peak_pairs, "frame_interval_ms": frame_statistics,
			"frame_p95_ms": frame_statistics["p95"]}


# Low-level sparse physics stress, without SceneTree/Node overhead.
# Each body has a real broadphase shape, zero gravity and disabled sleeping.
# At scale=977 there are 1,000,448 rigid bodies per workload.
func _physics_rid_sparse_2d(scale: int, frames: int, moving: bool = false) -> Dictionary:
	var space := PhysicsServer2D.space_create()
	PhysicsServer2D.space_set_active(space, true)
	var circle := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(circle, 0.5)
	var count := 1024 * scale
	var bodies: Array[RID] = []
	bodies.resize(count)
	var creation_started := Time.get_ticks_usec()
	for i in range(count):
		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_add_shape(body, circle)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(0.0, Vector2(float(i % 1024) * 4.0, float(int(i / 1024)) * 4.0)))
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		if moving:
			PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2(1.0, 0.0))
		PhysicsServer2D.body_set_space(body, space)
		bodies[i] = body
	var creation_ms := float(Time.get_ticks_usec() - creation_started) / 1000.0

	var peak_physics_ms := 0.0
	var peak_pairs := 0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for i in range(frames):
		await physics_frame
		var now := Time.get_ticks_usec()
		frame_intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))

	# Even at extreme body counts, isolated stationary bodies must not drift
	# or accidentally enter sleeping state when sleeping is disabled.
	var state_error := false
	for index in [0, int(count / 2), count - 1]:
		var probe: Transform2D = PhysicsServer2D.body_get_state(bodies[index], PhysicsServer2D.BODY_STATE_TRANSFORM)
		var expected := Vector2(float(index % 1024) * 4.0, float(int(index / 1024)) * 4.0)
		if moving:
			if frames > 1 and index == 0 and probe.origin.x <= expected.x:
				state_error = true
		elif not probe.origin.is_equal_approx(expected):
			state_error = true
		if bool(PhysicsServer2D.body_get_state(bodies[index], PhysicsServer2D.BODY_STATE_SLEEPING)):
			state_error = true

	var cleanup_started := Time.get_ticks_usec()
	PhysicsServer2D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer2D.free_rid(body)
	bodies.clear()
	PhysicsServer2D.free_rid(circle)
	PhysicsServer2D.free_rid(space)
	var cleanup_ms := float(Time.get_ticks_usec() - cleanup_started) / 1000.0
	if peak_pairs != 0:
		return {"error": "Sparse 2D RID bodies unexpectedly collided", "pairs": peak_pairs}
	if state_error:
		return {"error": "Sparse 2D RID bodies drifted or slept unexpectedly"}
	var frame_statistics := _frame_statistics(frame_intervals)
	return {"bodies": count, "moving": moving, "physics_frames": frames, "creation_ms": creation_ms, "cleanup_ms": cleanup_ms,
			"peak_physics_ms": peak_physics_ms, "peak_collision_pairs": peak_pairs,
			"frame_interval_ms": frame_statistics, "frame_p95_ms": frame_statistics["p95"]}


func _physics_rid_sparse_3d(scale: int, frames: int, moving: bool = false) -> Dictionary:
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var sphere := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(sphere, 0.5)
	var count := 1024 * scale
	var bodies: Array[RID] = []
	bodies.resize(count)
	var creation_started := Time.get_ticks_usec()
	for i in range(count):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_add_shape(body, sphere)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(float(i % 128) * 4.0, float(int(i / 128) % 128) * 4.0, float(int(i / 16384)) * 4.0)))
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		if moving:
			PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3(1.0, 0.0, 0.0))
		PhysicsServer3D.body_set_space(body, space)
		bodies[i] = body
	var creation_ms := float(Time.get_ticks_usec() - creation_started) / 1000.0

	var peak_physics_ms := 0.0
	var peak_pairs := 0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for i in range(frames):
		await physics_frame
		var now := Time.get_ticks_usec()
		frame_intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))

	var state_error := false
	for index in [0, int(count / 2), count - 1]:
		var probe: Transform3D = PhysicsServer3D.body_get_state(bodies[index], PhysicsServer3D.BODY_STATE_TRANSFORM)
		var expected := Vector3(float(index % 128) * 4.0, float(int(index / 128) % 128) * 4.0, float(int(index / 16384)) * 4.0)
		if moving:
			if frames > 1 and index == 0 and probe.origin.x <= expected.x:
				state_error = true
		elif not probe.origin.is_equal_approx(expected):
			state_error = true
		if bool(PhysicsServer3D.body_get_state(bodies[index], PhysicsServer3D.BODY_STATE_SLEEPING)):
			state_error = true

	var cleanup_started := Time.get_ticks_usec()
	PhysicsServer3D.space_set_active(space, false)
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	bodies.clear()
	PhysicsServer3D.free_rid(sphere)
	PhysicsServer3D.free_rid(space)
	var cleanup_ms := float(Time.get_ticks_usec() - cleanup_started) / 1000.0
	if peak_pairs != 0:
		return {"error": "Sparse 3D RID bodies unexpectedly collided", "pairs": peak_pairs}
	if state_error:
		return {"error": "Sparse 3D RID bodies drifted or slept unexpectedly"}
	var frame_statistics := _frame_statistics(frame_intervals)
	return {"bodies": count, "moving": moving, "physics_frames": frames, "creation_ms": creation_ms, "cleanup_ms": cleanup_ms,
			"peak_physics_ms": peak_physics_ms, "peak_collision_pairs": peak_pairs,
			"frame_interval_ms": frame_statistics, "frame_p95_ms": frame_statistics["p95"]}



func _physics_proxy_same_aabb_2d(scale: int, frames: int) -> Dictionary:
	return await CachedAABBStress.new().run_2d(self, scale, frames)


func _physics_proxy_same_aabb_3d(scale: int, frames: int) -> Dictionary:
	return await CachedAABBStress.new().run_3d(self, scale, frames)


func _physics_proxies_2d(scale: int) -> Dictionary:
	# A million simple broadphase proxies without a million scene-tree Nodes.
	# Static bodies deliberately have no overlapping shapes.
	var count := 1000 * scale
	var body_rids: Array[RID] = []
	body_rids.resize(count)
	var shape_rid := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape_rid, 0.5)
	var space_rid := root.get_world_2d().space
	var create_start := Time.get_ticks_usec()
	for i in range(count):
		var pos := Vector2(float(i & 1023) * 8.0, float(i >> 10) * 8.0)
		var body_rid := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body_rid, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(body_rid, shape_rid)
		PhysicsServer2D.body_set_state(body_rid, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, pos))
		PhysicsServer2D.body_set_space(body_rid, space_rid)
		body_rids[i] = body_rid
	var create_ms := float(Time.get_ticks_usec() - create_start) / 1000.0

	await physics_frame
	await process_frame
	var engine_memory_bytes := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var collision_pairs := int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS))
	var last_position := Vector2(float((count - 1) & 1023) * 8.0, float((count - 1) >> 10) * 8.0)
	var state := root.get_world_2d().direct_space_state
	var query_start := Time.get_ticks_usec()
	var first_hit := state.intersect_ray(PhysicsRayQueryParameters2D.create(Vector2(-4.0, 0.0), Vector2(4.0, 0.0)))
	var last_hit := state.intersect_ray(PhysicsRayQueryParameters2D.create(
		last_position + Vector2(-4.0, 0.0), last_position + Vector2(4.0, 0.0)))
	var query_ms := float(Time.get_ticks_usec() - query_start) / 1000.0
	var valid_hits := not first_hit.is_empty() and not last_hit.is_empty()
	if valid_hits:
		valid_hits = absf(first_hit.position.x + 0.5) < 0.05 and absf(last_hit.position.x - (last_position.x - 0.5)) < 0.05

	var free_start := Time.get_ticks_usec()
	for body_rid in body_rids:
		PhysicsServer2D.free_rid(body_rid)
	PhysicsServer2D.free_rid(shape_rid)
	body_rids.clear()
	var free_ms := float(Time.get_ticks_usec() - free_start) / 1000.0
	if collision_pairs != 0:
		return {"error": "Sparse 2D proxies unexpectedly collided", "pairs": collision_pairs}
	if not valid_hits:
		return {"error": "2D proxy raycasts returned incorrect nearest hits"}
	return {"bodies": count, "create_ms": create_ms, "free_ms": free_ms, "query_ms": query_ms,
		"collision_pairs": collision_pairs, "engine_memory_bytes": engine_memory_bytes}


func _physics_proxies_3d(scale: int) -> Dictionary:
	# Exercise the 3D BVH itself rather than the cost of creating Node3D objects.
	var count := 1000 * scale
	var body_rids: Array[RID] = []
	body_rids.resize(count)
	var shape_rid := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape_rid, 0.5)
	var space_rid := root.get_world_3d().space
	var create_start := Time.get_ticks_usec()
	for i in range(count):
		var pos := Vector3(float(i & 1023) * 8.0, 0.0, float(i >> 10) * 8.0)
		var body_rid := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body_rid, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(body_rid, shape_rid)
		PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), pos))
		PhysicsServer3D.body_set_space(body_rid, space_rid)
		body_rids[i] = body_rid
	var create_ms := float(Time.get_ticks_usec() - create_start) / 1000.0

	await physics_frame
	await process_frame
	var engine_memory_bytes := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var collision_pairs := int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))
	var last_position := Vector3(float((count - 1) & 1023) * 8.0, 0.0, float((count - 1) >> 10) * 8.0)
	var state := root.get_world_3d().direct_space_state
	var query_start := Time.get_ticks_usec()
	var first_hit := state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0)))
	var last_hit := state.intersect_ray(PhysicsRayQueryParameters3D.create(
		last_position + Vector3(-4.0, 0.0, 0.0), last_position + Vector3(4.0, 0.0, 0.0)))
	var query_ms := float(Time.get_ticks_usec() - query_start) / 1000.0
	var valid_hits := not first_hit.is_empty() and not last_hit.is_empty()
	if valid_hits:
		valid_hits = absf(first_hit.position.x + 0.5) < 0.05 and absf(last_hit.position.x - (last_position.x - 0.5)) < 0.05

	var free_start := Time.get_ticks_usec()
	for body_rid in body_rids:
		PhysicsServer3D.free_rid(body_rid)
	PhysicsServer3D.free_rid(shape_rid)
	body_rids.clear()
	var free_ms := float(Time.get_ticks_usec() - free_start) / 1000.0
	if collision_pairs != 0:
		return {"error": "Sparse 3D proxies unexpectedly collided", "pairs": collision_pairs}
	if not valid_hits:
		return {"error": "3D proxy raycasts returned incorrect nearest hits"}
	return {"bodies": count, "create_ms": create_ms, "free_ms": free_ms, "query_ms": query_ms,
		"collision_pairs": collision_pairs, "engine_memory_bytes": engine_memory_bytes}



# The restitution tests use two equal-mass bodies with zero gravity.
# Below the configured threshold they should settle instead of rebounding;
# above it, their x velocities should reverse after impact.
func _restitution_trial_2d(speed: float, steps: int) -> float:
	var server := PhysicsServer2D
	var space := server.space_create()
	var circle := server.circle_shape_create()
	server.shape_set_data(circle, 1.0)
	var a := server.body_create()
	var b := server.body_create()
	for body in [a, b]:
		server.body_add_shape(body, circle)
		server.body_set_param(body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		server.body_set_param(body, PhysicsServer2D.BODY_PARAM_BOUNCE, 1.0)
		server.body_set_state(body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
	server.body_set_state(a, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(-3.0, 0.0)))
	server.body_set_state(b, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(3.0, 0.0)))
	server.body_set_state(a, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2(speed, 0.0))
	server.body_set_state(b, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2(-speed, 0.0))
	server.space_set_active(space, true)
	server.body_set_space(a, space)
	server.body_set_space(b, space)
	for i in range(steps):
		await physics_frame
	var final_velocity: Vector2 = server.body_get_state(a, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	server.space_set_active(space, false)
	server.free_rid(a)
	server.free_rid(b)
	server.free_rid(circle)
	server.free_rid(space)
	return final_velocity.x


func _physics_restitution_2d() -> Dictionary:
	var threshold := float(ProjectSettings.get_setting("physics/2d/solver/restitution_velocity_threshold", 30.0))
	if threshold <= 0.0:
		return {"error": "Restitution test requires a positive 2D velocity threshold"}
	var slow_speed := threshold * 0.25
	var fast_speed := threshold * 2.0
	var low_vx: float = await _restitution_trial_2d(slow_speed, 90)
	var high_vx: float = await _restitution_trial_2d(fast_speed, 90)
	if low_vx < -slow_speed * 0.25:
		return {"error": "Low-speed 2D impact unexpectedly rebounded", "vx": low_vx}
	if low_vx > slow_speed * 0.75:
		return {"error": "Low-speed 2D impact did not reach a contact", "vx": low_vx}
	if high_vx >= -fast_speed * 0.25:
		return {"error": "High-speed 2D impact failed to rebound", "vx": high_vx}
	return {"threshold": threshold, "low_speed": slow_speed, "high_speed": fast_speed,
			"low_final_x_velocity": low_vx, "high_final_x_velocity": high_vx}


func _restitution_trial_3d(speed: float, steps: int) -> float:
	var server := PhysicsServer3D
	var space := server.space_create()
	var sphere := server.sphere_shape_create()
	server.shape_set_data(sphere, 0.5)
	var a := server.body_create()
	var b := server.body_create()
	for body in [a, b]:
		server.body_add_shape(body, sphere)
		server.body_set_param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		server.body_set_param(body, PhysicsServer3D.BODY_PARAM_BOUNCE, 1.0)
		server.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	server.body_set_state(a, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(-1.0, 0.0, 0.0)))
	server.body_set_state(b, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(1.0, 0.0, 0.0)))
	server.body_set_state(a, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3(speed, 0.0, 0.0))
	server.body_set_state(b, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3(-speed, 0.0, 0.0))
	server.space_set_active(space, true)
	server.body_set_space(a, space)
	server.body_set_space(b, space)
	for i in range(steps):
		await physics_frame
	var final_velocity: Vector3 = server.body_get_state(a, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	server.space_set_active(space, false)
	server.free_rid(a)
	server.free_rid(b)
	server.free_rid(sphere)
	server.free_rid(space)
	return final_velocity.x


func _physics_restitution_3d() -> Dictionary:
	var threshold := float(ProjectSettings.get_setting("physics/3d/solver/restitution_velocity_threshold", 1.0))
	if threshold <= 0.0:
		return {"error": "Restitution test requires a positive 3D velocity threshold"}
	var slow_speed := threshold * 0.25
	var fast_speed := threshold * 2.0
	var low_vx: float = await _restitution_trial_3d(slow_speed, 180)
	var high_vx: float = await _restitution_trial_3d(fast_speed, 180)
	if low_vx < -slow_speed * 0.25:
		return {"error": "Low-speed 3D impact unexpectedly rebounded", "vx": low_vx}
	if low_vx > slow_speed * 0.75:
		return {"error": "Low-speed 3D impact did not reach a contact", "vx": low_vx}
	if high_vx >= -fast_speed * 0.25:
		return {"error": "High-speed 3D impact failed to rebound", "vx": high_vx}
	return {"threshold": threshold, "low_speed": slow_speed, "high_speed": fast_speed,
			"low_final_x_velocity": low_vx, "high_final_x_velocity": high_vx}



func _physics_sparse_2d(scale: int, frames: int) -> Dictionary:
	# Many separate active islands exercise worst-case per-island allocations.
	# Zero contacts distinguishes sparse topology from the dense physics case.
	var world := Node2D.new()
	root.add_child(world)
	var circle := CircleShape2D.new()
	circle.radius = 1.0
	var count := 128 * scale
	for i in range(count):
		var body := RigidBody2D.new()
		body.gravity_scale = 0.0
		body.can_sleep = false
		body.position = Vector2(float(i) * 16.0, 0.0)
		var collider := CollisionShape2D.new()
		collider.shape = circle
		body.add_child(collider)
		world.add_child(body)

	var peak_physics_ms := 0.0
	var peak_pairs := 0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for i in range(frames):
		await physics_frame
		var now := Time.get_ticks_usec()
		frame_intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))
	world.queue_free()
	await process_frame
	if peak_pairs != 0:
		return {"error": "Sparse 2D physics bodies unexpectedly collided", "pairs": peak_pairs}
	var frame_statistics := _frame_statistics(frame_intervals)
	return {"bodies": count, "physics_frames": frames, "peak_physics_ms": peak_physics_ms, "peak_collision_pairs": peak_pairs, "frame_interval_ms": frame_statistics, "frame_p95_ms": frame_statistics["p95"]}


func _physics_sparse_3d(scale: int, frames: int) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	var count := 64 * scale
	for i in range(count):
		var body := RigidBody3D.new()
		body.gravity_scale = 0.0
		body.can_sleep = false
		body.position = Vector3(float(i) * 8.0, 0.0, 0.0)
		var collider := CollisionShape3D.new()
		collider.shape = sphere
		body.add_child(collider)
		world.add_child(body)

	var peak_physics_ms := 0.0
	var peak_pairs := 0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for i in range(frames):
		await physics_frame
		var now := Time.get_ticks_usec()
		frame_intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
	world.queue_free()
	await process_frame
	if peak_pairs != 0:
		return {"error": "Sparse 3D physics bodies unexpectedly collided", "pairs": peak_pairs}
	var frame_statistics := _frame_statistics(frame_intervals)
	return {"bodies": count, "physics_frames": frames, "peak_physics_ms": peak_physics_ms, "peak_collision_pairs": peak_pairs, "frame_interval_ms": frame_statistics, "frame_p95_ms": frame_statistics["p95"]}


func _memory_churn(scale: int) -> Dictionary:
	var readings: Array[int] = []
	for cycle in range(12):
		var allocations: Array[PackedByteArray] = []
		for i in range(300 * scale):
			var block := PackedByteArray()
			block.resize(4096)
			block[0] = i & 255
			allocations.append(block)
		allocations.clear()
		await process_frame
		readings.append(int(Performance.get_monitor(Performance.MEMORY_STATIC)))
	var retained := readings.back() - readings[2]
	return {"cycles": readings.size(), "sample_bytes": readings, "retained_growth_bytes": retained}


func _render_ellipse_2d(scale: int) -> Dictionary:
	# A display renderer is required: headless dummy bypasses tessellation.
	# Include queued render-server work with force_sync at both boundaries.
	var item := RenderingServer.canvas_item_create()
	var count := 256 * scale
	RenderingServer.force_sync()
	var begin := Time.get_ticks_usec()
	for i in range(count):
		var pos := Vector2(float(i % 64) * 5.0, float(i / 64) * 5.0)
		var radius := 2.0 + float(i & 15)
		var color := Color(0.8, 0.5, 0.3, 1.0)
		if i & 1:
			RenderingServer.canvas_item_add_circle(item, pos, radius, color, (i & 2) != 0)
		else:
			RenderingServer.canvas_item_add_ellipse(item, pos, radius, radius * 0.65, color, (i & 2) != 0)
	RenderingServer.force_sync()
	var tessellate_ms := float(Time.get_ticks_usec() - begin) / 1000.0
	RenderingServer.free_rid(item)
	RenderingServer.force_sync()
	return {"commands": count, "antialiased_commands": count / 2, "ellipse_cpu_ms": tessellate_ms}


func _render_2d(scale: int, frames: int) -> Dictionary:
	var world := Node2D.new()
	root.add_child(world)
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.4, 0.6, 0.8))
	var shared_texture := ImageTexture.create_from_image(image)
	for i in range(600 * scale):
		var sprite := Sprite2D.new()
		sprite.texture = shared_texture
		sprite.position = Vector2(float(i % 120) * 9.0, float(i / 120) * 9.0)
		world.add_child(sprite)
	var peak_frame_ms := 0.0
	var peak_draw_calls := 0
	var peak_video_memory := 0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for i in range(frames):
		await process_frame
		var frame_tick := Time.get_ticks_usec()
		frame_intervals.append(float(frame_tick - last_tick) / 1000.0)
		last_tick = frame_tick
		peak_frame_ms = maxf(peak_frame_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		peak_draw_calls = maxi(peak_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		peak_video_memory = maxi(peak_video_memory, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
	world.queue_free()
	await process_frame
	var frame_statistics := _frame_statistics(frame_intervals)
	return {"sprites": 600 * scale, "frames": frames, "peak_frame_ms": peak_frame_ms, "peak_draw_calls": peak_draw_calls, "peak_video_memory_bytes": peak_video_memory, "frame_interval_ms": frame_statistics, "frame_p95_ms": frame_statistics["p95"]}


func _render_light_culling_3d(scale: int, frames: int) -> Dictionary:
	# Move overlapping omni lights every frame to repeatedly exercise the
	# light-to-mesh ranking path, instead of only measuring initial setup.
	var world := Node3D.new()
	root.add_child(world)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 35.0, 55.0)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true

	var mesh := BoxMesh.new()
	var mesh_count := 24 * scale
	for i in range(mesh_count):
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.position = Vector3(float(i % 24) * 2.0 - 23.0, 0.0, float(i / 24) * 2.0 - 7.0)
		world.add_child(instance)

	var lights: Array[OmniLight3D] = []
	var light_count := 12 * scale
	for i in range(light_count):
		var light := OmniLight3D.new()
		light.position = Vector3(float(i % 12) * 3.0 - 16.5, 4.0, float(i / 12) * 3.0 - 7.5)
		light.omni_range = 35.0
		light.light_energy = 1.0 + float(i % 5) * 0.25
		world.add_child(light)
		lights.append(light)

	var frame_intervals: Array[float] = []
	var peak_frame_ms := 0.0
	var peak_draw_calls := 0
	var last_tick := Time.get_ticks_usec()
	for frame in range(frames):
		# Toggle movement so lights remain inside the same influence region.
		# This deliberately marks their mesh-light associations dirty.
		var movement := 0.03 if (frame & 1) == 0 else -0.03
		for light in lights:
			light.position.x += movement
		await process_frame
		var now := Time.get_ticks_usec()
		frame_intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		peak_frame_ms = maxf(peak_frame_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		peak_draw_calls = maxi(peak_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))

	world.queue_free()
	await process_frame
	var stats := _frame_statistics(frame_intervals)
	return {"meshes": mesh_count, "lights": light_count, "frames": frames, "peak_frame_ms": peak_frame_ms, "peak_draw_calls": peak_draw_calls, "frame_interval_ms": stats, "frame_p95_ms": stats["p95"]}


func _render_3d(scale: int, frames: int) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 30, 60)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var light := DirectionalLight3D.new()
	world.add_child(light)
	var box := BoxMesh.new()
	for i in range(200 * scale):
		var mesh := MeshInstance3D.new()
		mesh.mesh = box
		mesh.position = Vector3(float(i % 40) - 20.0, 0.0, float(i / 40) - 10.0)
		world.add_child(mesh)
	var peak_frame_ms := 0.0
	var peak_draw_calls := 0
	var peak_video_memory := 0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for i in range(frames):
		await process_frame
		var frame_tick := Time.get_ticks_usec()
		frame_intervals.append(float(frame_tick - last_tick) / 1000.0)
		last_tick = frame_tick
		peak_frame_ms = maxf(peak_frame_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		peak_draw_calls = maxi(peak_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		peak_video_memory = maxi(peak_video_memory, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
	world.queue_free()
	await process_frame
	var frame_statistics := _frame_statistics(frame_intervals)
	return {"meshes": 200 * scale, "frames": frames, "peak_frame_ms": peak_frame_ms, "peak_draw_calls": peak_draw_calls, "peak_video_memory_bytes": peak_video_memory, "frame_interval_ms": frame_statistics, "frame_p95_ms": frame_statistics["p95"]}


## Additional cross-subsystem workloads. Each one has an explicit integrity check.

func _node_paths(scale: int) -> Dictionary:
	var group := Node.new()
	root.add_child(group)
	var paths: Array[NodePath] = []
	var count := 400 * scale
	for i in range(count):
		var child := Node.new()
		child.name = "Target%d" % i
		group.add_child(child)
		paths.append(NodePath("Target%d" % i))
	var started := Time.get_ticks_usec()
	var found := 0
	for i in range(count * 10):
		if group.get_node_or_null(paths[i % count]) != null:
			found += 1
	var lookup_ms := float(Time.get_ticks_usec() - started) / 1000.0
	group.free()
	if found != count * 10:
		return {"error": "NodePath lookup count mismatch"}
	return {"nodes": count, "lookups": found, "lookup_ms": lookup_ms}


func _regex(scale: int) -> Dictionary:
	var pattern := RegEx.new()
	if pattern.compile("item_[0-9]{4}:[A-Z]+") != OK:
		return {"error": "RegEx could not compile"}
	var matches_found := 0
	for i in range(400 * scale):
		var value := "item_%04d:ALPHA item_%04d:BETA no-match" % [i % 10000, (i + 1) % 10000]
		var matches := pattern.search_all(value)
		if matches.size() != 2:
			return {"error": "RegEx match count mismatch"}
		matches_found += matches.size()
	return {"inputs": 400 * scale, "matches": matches_found}


func _compression(scale: int) -> Dictionary:
	var data := PackedByteArray()
	data.resize(256 * 1024)
	for i in range(data.size()):
		data[i] = (i * 31 + (i >> 3)) & 255
	var compressed_bytes := 0
	for i in range(35 * scale):
		var compressed := data.compress(FileAccess.COMPRESSION_ZSTD)
		if compressed.is_empty():
			return {"error": "Zstd compression failed"}
		var restored := compressed.decompress(data.size(), FileAccess.COMPRESSION_ZSTD)
		if restored != data:
			return {"error": "Compressed payload differs after decompression"}
		compressed_bytes += compressed.size()
	return {"roundtrips": 35 * scale, "source_bytes": data.size(), "total_compressed_bytes": compressed_bytes}


func _hashing(scale: int) -> Dictionary:
	var bytes := PackedByteArray()
	bytes.resize(64 * 1024)
	for i in range(bytes.size()):
		bytes[i] = (i * 17 + (i >> 5)) & 255
	var first_digest := PackedByteArray()
	for i in range(120 * scale):
		var context := HashingContext.new()
		if context.start(HashingContext.HASH_SHA256) != OK:
			return {"error": "Could not initialize SHA-256 context"}
		if context.update(bytes) != OK:
			return {"error": "Could not hash input"}
		var digest := context.finish()
		if digest.size() != 32:
			return {"error": "Unexpected SHA-256 digest size"}
		if i == 0:
			first_digest = digest
		elif digest != first_digest:
			return {"error": "Unstable hash digest"}
	return {"hashes": 120 * scale, "bytes_per_hash": bytes.size(), "digest_prefix": first_digest.hex_encode().substr(0, 8)}


func _resource_io(scale: int) -> Dictionary:
	var path := "user://stress_resource_io.tres"
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(1.0, 1.0))
	var completed := 0
	var failure := ""
	for i in range(20 * scale):
		if ResourceSaver.save(curve, path) != OK:
			failure = "ResourceSaver failed"
			break
		var loaded := ResourceLoader.load(path, "Curve", ResourceLoader.CACHE_MODE_IGNORE) as Curve
		if loaded == null or loaded.get_point_count() != 2:
			failure = "ResourceLoader failed to restore Curve"
			break
		completed += 1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not failure.is_empty():
		return {"error": failure}
	return {"roundtrips": completed, "resource_type": "Curve"}


func _astar_3d(scale: int) -> Dictionary:
	var finder := AStar3D.new()
	const SIDE := 20
	for y in range(SIDE):
		for x in range(SIDE):
			var point_id := y * SIDE + x
			finder.add_point(point_id, Vector3(x, 0.0, y))
			if x > 0:
				finder.connect_points(point_id, point_id - 1)
			if y > 0:
				finder.connect_points(point_id, point_id - SIDE)
	var checksum := 0
	for i in range(100 * scale):
		var path := finder.get_id_path(0, SIDE * SIDE - 1)
		if path.is_empty() or path[0] != 0 or path.back() != SIDE * SIDE - 1:
			return {"error": "AStar3D path incorrect"}
		checksum += path.size()
	return {"vertices": SIDE * SIDE, "searches": 100 * scale, "checksum": checksum}


var contention_lock := Mutex.new()
var contention_counter: int = 0


func _contention_worker(operations: int) -> void:
	for i in range(operations):
		contention_lock.lock()
		contention_counter += 1
		contention_lock.unlock()


func _thread_contention(scale: int) -> Dictionary:
	var workers: Array[Thread] = []
	var count := mini(8, maxi(2, OS.get_processor_count()))
	var operations := 10000 * scale
	contention_counter = 0
	for i in range(count):
		var worker := Thread.new()
		if worker.start(Callable(self, "_contention_worker").bind(operations)) != OK:
			for active in workers:
				active.wait_to_finish()
			return {"error": "Could not start contention worker"}
		workers.append(worker)
	for worker in workers:
		worker.wait_to_finish()
	if contention_counter != count * operations:
		return {"error": "Mutex-protected counter mismatch"}
	return {"workers": count, "lock_operations": contention_counter}


# Independently validated CPU/physics/GPU pressure scenarios.

func _packed_arrays(scale: int) -> Dictionary:
	var count := 50000 * scale
	var values := PackedFloat32Array()
	values.resize(count)
	for i in range(count):
		values[i] = float(i % 1000) * 0.125
	var raw := values.to_byte_array()
	var restored := raw.to_float32_array()
	if restored.size() != count:
		return {"error": "Packed float roundtrip size mismatch"}
	var checksum := 0.0
	for i in range(0, count, 37):
		if restored[i] != values[i]:
			return {"error": "Packed float roundtrip data mismatch"}
		checksum += restored[i]
	return {"elements": count, "bytes": raw.size(), "checksum": checksum}


func _sorting(scale: int) -> Dictionary:
	var count := 10000 * scale
	var values: Array[int] = []
	values.resize(count)
	for i in range(count):
		values[i] = count - 1 - i
	values.sort()
	var checksum := 0
	for i in range(count * 2):
		var target := (i * 4099) % count
		var found := values.bsearch(target)
		if found >= count or values[found] != target:
			return {"error": "Binary search mismatch"}
		checksum = (checksum + found) & 0x7fffffff
	return {"elements": count, "searches": count * 2, "checksum": checksum}


func _animation_tracks(scale: int) -> Dictionary:
	var world := Node2D.new()
	root.add_child(world)
	var animated := Node2D.new()
	animated.name = "Animated"
	world.add_child(animated)
	var player := AnimationPlayer.new()
	world.add_child(player)
	player.root_node = NodePath("..")
	var animation := Animation.new()
	animation.length = 1.0
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("Animated:position"))
	animation.track_insert_key(track, 0.0, Vector2.ZERO)
	animation.track_insert_key(track, 1.0, Vector2(100, 0))
	var library := AnimationLibrary.new()
	if library.add_animation("move", animation) != OK:
		world.free()
		return {"error": "AnimationLibrary registration failed"}
	if player.add_animation_library("", library) != OK:
		world.free()
		return {"error": "AnimationPlayer registration failed"}
	player.play("move")
	var checksum := 0.0
	for i in range(1000 * scale):
		player.seek(float(i % 100) / 100.0, true)
		checksum += animated.position.x
	world.free()
	if checksum <= 0:
		return {"error": "AnimationPlayer did not update animated track"}
	return {"seeks": 1000 * scale, "checksum": checksum}


func _physics_raycast_2d(scale: int) -> Dictionary:
	var world := Node2D.new()
	root.add_child(world)
	var shape := CircleShape2D.new()
	shape.radius = 2.0
	var bodies := 100 * scale
	for i in range(bodies):
		var body := StaticBody2D.new()
		body.position = Vector2(float(i) * 8.0, 0.0)
		var collider := CollisionShape2D.new()
		collider.shape = shape
		body.add_child(collider)
		world.add_child(body)
	await physics_frame
	await process_frame
	var hits := 0
	var started := Time.get_ticks_usec()
	for i in range(150 * scale):
		var y := float((i % 3) - 1)
		var query := PhysicsRayQueryParameters2D.create(Vector2(-5, y), Vector2(float(bodies) * 8.0 + 5.0, y))
		var hit := root.get_world_2d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			hits += 1
	var query_ms := float(Time.get_ticks_usec() - started) / 1000.0
	# Verify that the unordered broadphase still returns the nearest body in both directions.
	var ray_from := Vector2(-5.0, 0.0)
	var ray_to := Vector2(float(bodies) * 8.0 + 5.0, 0.0)
	var space_state := root.get_world_2d().direct_space_state
	var first_hit := space_state.intersect_ray(PhysicsRayQueryParameters2D.create(ray_from, ray_to))
	var last_hit := space_state.intersect_ray(PhysicsRayQueryParameters2D.create(ray_to, ray_from))
	var nearest_valid := not first_hit.is_empty() and not last_hit.is_empty()
	if nearest_valid:
		nearest_valid = absf(first_hit.position.x + 2.0) < 0.05 and absf(last_hit.position.x - (float(bodies - 1) * 8.0 + 2.0)) < 0.05
	world.queue_free()
	await process_frame
	if not nearest_valid:
		return {"error": "Physics2D raycasts returned the wrong nearest hit"}
	if hits != 150 * scale:
		return {"error": "Physics2D raycasts missed shapes", "hits": hits, "expected": 150 * scale}
	return {"bodies": bodies, "queries": 150 * scale, "hits": hits, "query_ms": query_ms}


func _physics_raycast_3d(scale: int) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var shape := SphereShape3D.new()
	shape.radius = 2.0
	var bodies := 80 * scale
	for i in range(bodies):
		var body := StaticBody3D.new()
		body.position = Vector3(float(i) * 8.0, 0.0, 0.0)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		world.add_child(body)
	await physics_frame
	await process_frame
	var hits := 0
	var started := Time.get_ticks_usec()
	for i in range(150 * scale):
		var z := float((i % 3) - 1)
		var query := PhysicsRayQueryParameters3D.create(Vector3(-5, 0, z), Vector3(float(bodies) * 8.0 + 5.0, 0, z))
		var hit := root.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			hits += 1
	var query_ms := float(Time.get_ticks_usec() - started) / 1000.0
	# Verify nearest-hit selection when the broadphase reports many candidates.
	var ray_from := Vector3(-5.0, 0.0, 0.0)
	var ray_to := Vector3(float(bodies) * 8.0 + 5.0, 0.0, 0.0)
	var space_state := root.get_world_3d().direct_space_state
	var first_hit := space_state.intersect_ray(PhysicsRayQueryParameters3D.create(ray_from, ray_to))
	var last_hit := space_state.intersect_ray(PhysicsRayQueryParameters3D.create(ray_to, ray_from))
	var nearest_valid := not first_hit.is_empty() and not last_hit.is_empty()
	if nearest_valid:
		nearest_valid = absf(first_hit.position.x + 2.0) < 0.05 and absf(last_hit.position.x - (float(bodies - 1) * 8.0 + 2.0)) < 0.05
	world.queue_free()
	await process_frame
	if not nearest_valid:
		return {"error": "Physics3D raycasts returned the wrong nearest hit"}
	if hits != 150 * scale:
		return {"error": "Physics3D raycasts missed shapes", "hits": hits, "expected": 150 * scale}
	return {"bodies": bodies, "queries": 150 * scale, "hits": hits, "query_ms": query_ms}


func _render_multimesh_3d(scale: int, frames: int) -> Dictionary:
	# Requires a real display; dummy headless RenderingServer provides no GPU data.
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 75.0, 120.0)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var instances := 2000 * scale
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = BoxMesh.new()
	multimesh.instance_count = instances
	for i in range(instances):
		var pos := Vector3(float(i % 100) - 50.0, 0.0, float(i / 100) - float(instances / 200))
		multimesh.set_instance_transform(i, Transform3D(Basis(), pos))
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	world.add_child(node)
	var frame_ms: Array[float] = []
	var peak_draw_calls := 0
	for i in range(frames):
		await process_frame
		frame_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		peak_draw_calls = maxi(peak_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	frame_ms.sort()
	var p95_frame_ms := frame_ms[maxi(0, int(ceil(float(frames) * 0.95)) - 1)]
	var peak_frame_ms := frame_ms.back()
	world.queue_free()
	await process_frame
	return {"instances": instances, "frames": frames, "p95_frame_ms": p95_frame_ms, "peak_frame_ms": peak_frame_ms, "peak_draw_calls": peak_draw_calls}


func _resource_load(scale: int) -> Dictionary:
	var path := "user://stress_generated_scene.tscn"
	var prototype := Node2D.new()
	for i in range(12):
		var child := Node2D.new()
		child.name = "Child%d" % i
		prototype.add_child(child)
		child.owner = prototype
	var scene := PackedScene.new()
	if scene.pack(prototype) != OK:
		prototype.free()
		return {"error": "Could not pack resource prototype"}
	prototype.free()
	if ResourceSaver.save(scene, path) != OK:
		return {"error": "ResourceSaver failed"}
	scene = null
	var checksum := 0
	for i in range(40 * scale):
		# Cache bypass deliberately exercises disk IO + text resource parsing.
		var loaded := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if not (loaded is PackedScene):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			return {"error": "ResourceLoader failed"}
		var instance := loaded.instantiate()
		if instance == null or instance.get_child_count() != 12:
			if instance != null:
				instance.free()
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			return {"error": "Loaded scene contents mismatch"}
		checksum += instance.get_child_count()
		instance.free()
	var cleanup := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if cleanup != OK:
		return {"error": "Could not remove generated test resource"}
	return {"reloads": 40 * scale, "checksum": checksum}


func _input_map(scale: int) -> Dictionary:
	var action := &"stress_generated_input_action"
	var event := InputEventKey.new()
	event.keycode = KEY_A
	event.pressed = true
	var matches := 0
	for i in range(3000 * scale):
		InputMap.add_action(action)
		InputMap.action_add_event(action, event)
		if not InputMap.event_is_action(event, action, true):
			InputMap.erase_action(action)
			return {"error": "Input action lookup mismatch"}
		matches += 1
		InputMap.erase_action(action)
	return {"registrations": matches, "checksum": matches}


func _transform_hierarchy(scale: int) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var nodes: Array[Node3D] = [world]
	var count := 300 * scale
	for i in range(count):
		var node := Node3D.new()
		node.position = Vector3(float(i & 7), 1.0, float(i & 15))
		nodes[int(i / 2)].add_child(node)
		nodes.append(node)
	var checksum := 0.0
	for pass_index in range(3):
		for i in range(1, nodes.size()):
			var node := nodes[i]
			node.position.x += 0.25
			checksum += node.global_position.x
	world.free()
	return {"nodes": count, "transform_reads": count * 3, "checksum": checksum}

func _astar_graph(scale: int) -> Dictionary:
	var graph := AStar2D.new()
	const WIDTH = 32
	for y in range(WIDTH):
		for x in range(WIDTH):
			var id := y * WIDTH + x
			graph.add_point(id, Vector2(x, y))
			if x > 0:
				graph.connect_points(id, id - 1)
			if y > 0:
				graph.connect_points(id, id - WIDTH)
	var checksum := 0
	for i in range(40 * scale):
		var start := i % WIDTH
		var finish := WIDTH * WIDTH - 1 - (i % WIDTH)
		var path := graph.get_id_path(start, finish)
		if path.is_empty() or path[0] != start or path[path.size() - 1] != finish:
			return {"error": "AStar graph path mismatch"}
		checksum += path.size()
	return {"vertices": WIDTH * WIDTH, "searches": 40 * scale, "checksum": checksum}


# Stress RefCounted creation and destruction separately from byte-buffer churn.
func _object_churn(scale: int) -> Dictionary:
	var checksum := 0
	for cycle in range(8):
		var objects: Array[RefCounted] = []
		for i in range(3000 * scale):
			objects.append(RefCounted.new())
		checksum += objects.size()
		objects.clear()
	return {"objects_created": 8 * 3000 * scale, "checksum": checksum}

# Exercise bulk byte-range writes, clipping, and packed popcount in a real engine.
func _bitmap_rects(scale: int) -> Dictionary:
	var bitmap := BitMap.new()
	bitmap.create(Vector2i(2048, 2048))
	const SIZE := 2048
	var rectangles := 200 * scale
	var start := Time.get_ticks_usec()
	for i in range(rectangles):
		bitmap.set_bit_rect(Rect2i((i * 17) % 1536, (i * 37) % 1536, 512, 512), (i & 1) == 0)
	var fill_ms := float(Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	var retained := bitmap.get_true_bit_count()
	var count_ms := float(Time.get_ticks_usec() - start) / 1000.0
	if retained < 0 or retained > SIZE * SIZE:
		return {"error": "BitMap popcount out of range"}
	bitmap.set_bit_rect(Rect2i(0, 0, SIZE, SIZE), true)
	if bitmap.get_true_bit_count() != SIZE * SIZE:
		return {"error": "BitMap full-rectangle fill corrupted pixels"}
	bitmap.set_bit_rect(Rect2i(17, 0, 1, SIZE), false)
	if bitmap.get_true_bit_count() != SIZE * SIZE - SIZE:
		return {"error": "BitMap unaligned clear corrupted other bits"}
	return {"rectangles": rectangles, "fill_ms": fill_ms, "popcount_ms": count_ms,
			"checksum": retained}


# Every candidate begins with a high-cost direct route, then receives a
# cheaper path via the same intermediate vertex, stressing the indexed heap.
func _astar_relax_2d(scale: int) -> Dictionary:
	var graph := AStar2D.new()
	graph.add_point(0, Vector2.ZERO)
	graph.add_point(1, Vector2(99, 0))
	graph.add_point(3, Vector2(101, 0))
	graph.connect_points(0, 1, false)
	var count := 128 * scale
	for i in range(count):
		var node_id := 2 if i == 0 else i + 3
		graph.add_point(node_id, Vector2(100.0 + float(i) * 0.0001, 0), 10.0)
		graph.connect_points(0, node_id, false)
		graph.connect_points(1, node_id, false)
		if i == 0:
			graph.connect_points(node_id, 3, false)

	var started := Time.get_ticks_usec()
	var checksum := 0
	for repeat in range(40):
		var path := graph.get_id_path(0, 3)
		if path.size() != 4 or path[0] != 0 or path[1] != 1 or path[2] != 2 or path[3] != 3:
			return {"error": "AStar2D decrease-key produced an incorrect route"}
		checksum += path.size()
	return {"nodes": count + 3, "queries": 40, "search_ms": float(Time.get_ticks_usec() - started) / 1000.0, "checksum": checksum}


func _astar_relax_3d(scale: int) -> Dictionary:
	var graph := AStar3D.new()
	graph.add_point(0, Vector3.ZERO)
	graph.add_point(1, Vector3(99, 0, 0))
	graph.add_point(3, Vector3(101, 0, 0))
	graph.connect_points(0, 1, false)
	var count := 128 * scale
	for i in range(count):
		var node_id := 2 if i == 0 else i + 3
		graph.add_point(node_id, Vector3(100.0 + float(i) * 0.0001, 0, 0), 10.0)
		graph.connect_points(0, node_id, false)
		graph.connect_points(1, node_id, false)
		if i == 0:
			graph.connect_points(node_id, 3, false)

	var started := Time.get_ticks_usec()
	var checksum := 0
	for repeat in range(40):
		var path := graph.get_id_path(0, 3)
		if path.size() != 4 or path[0] != 0 or path[1] != 1 or path[2] != 2 or path[3] != 3:
			return {"error": "AStar3D decrease-key produced an incorrect route"}
		checksum += path.size()
	return {"nodes": count + 3, "queries": 40, "search_ms": float(Time.get_ticks_usec() - started) / 1000.0, "checksum": checksum}

# Exercise BitMap blit, nearest-neighbor resize, image conversion and LA8 input.
func _bitmap_pipeline(scale: int) -> Dictionary:
	var source := BitMap.new()
	source.create(Vector2i(257, 193))
	source.set_bit_rect(Rect2i(3, 5, 250, 180), true)
	var la8 := Image.create(257, 193, false, Image.FORMAT_LA8)
	la8.fill(Color(0.4, 0.4, 0.4, 0.8))
	var blit_ms := 0.0
	var resize_ms := 0.0
	var image_ms := 0.0
	var alpha_ms := 0.0
	var checksum := 0
	var iterations := 40 * scale
	for i in range(iterations):
		var dest := BitMap.new()
		dest.create(Vector2i(512, 384))
		var started := Time.get_ticks_usec()
		dest.blit(Vector2i((i * 7) % 50 - 25, (i * 11) % 50 - 25), source)
		blit_ms += float(Time.get_ticks_usec() - started) / 1000.0
		started = Time.get_ticks_usec()
		dest.resize(Vector2i(320, 256))
		resize_ms += float(Time.get_ticks_usec() - started) / 1000.0
		started = Time.get_ticks_usec()
		var image := dest.convert_to_image()
		image_ms += float(Time.get_ticks_usec() - started) / 1000.0
		if image.get_width() != 320 or image.get_height() != 256:
			return {"error": "BitMap image size changed after pipeline"}
		checksum += dest.get_true_bit_count()
		started = Time.get_ticks_usec()
		var alpha_mask := BitMap.new()
		alpha_mask.create_from_image_alpha(la8, 0.5)
		alpha_ms += float(Time.get_ticks_usec() - started) / 1000.0
		if alpha_mask.get_true_bit_count() != 257 * 193:
			return {"error": "BitMap LA8 import lost alpha pixels"}
	if checksum <= 0:
		return {"error": "BitMap clipped blit produced no pixels"}
	return {"iterations": iterations, "blit_ms": blit_ms, "resize_ms": resize_ms,
			"convert_ms": image_ms, "alpha_import_ms": alpha_ms, "checksum": checksum}


func _stream_bulk(scale: int) -> Dictionary:
	# Measure bulk reads and writes independently of small primitive calls.
	var peer := StreamPeerBuffer.new()
	var payload := PackedByteArray()
	payload.resize(8192)
	for i in range(payload.size()):
		payload[i] = i & 255
	if peer.put_data(payload) != OK:
		return {"error": "Initial bulk stream write failed"}

	var checksum := 0
	var bytes_read := 0
	var started := Time.get_ticks_usec()
	for repeat in range(300 * scale):
		peer.seek(0)
		if peer.put_data(payload) != OK:
			return {"error": "Bulk stream write failed"}
		peer.seek(0)
		var response: Array = peer.get_data(payload.size())
		if response[0] != OK:
			return {"error": "Bulk stream read failed"}
		var received: PackedByteArray = response[1]
		if received.size() != payload.size() or received[0] != 0 or received[8191] != 255:
			return {"error": "Bulk stream data mismatch"}
		checksum += received[repeat % received.size()]
		bytes_read += received.size()
		if repeat % 16 == 0:
			peer.seek(0)
			var partial: Array = peer.get_partial_data(payload.size() + 1024)
			if partial[0] != OK:
				return {"error": "Partial bulk read returned error"}
			var partial_data: PackedByteArray = partial[1]
			if partial_data.size() != payload.size() or partial_data[8191] != 255:
				return {"error": "Partial bulk read length/data mismatch"}
			checksum += partial_data[repeat % partial_data.size()]
	return {
		"operations": 300 * scale,
		"bytes_read": bytes_read,
		"read_write_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"checksum": checksum,
	}


# Profile Curve2D creation, adaptive subdivision, even-length subdivision,
# and full baked-cache regeneration separately (no rendering/GPU overhead).
func _curve_tessellation_2d(scale: int) -> Dictionary:
	var started := Time.get_ticks_usec()
	var count := 48 * scale
	var curve := Curve2D.new()
	for i in range(count + 1):
		curve.add_point(Vector2(float(i) * 1.2, sin(float(i) * 0.38) * 7.0),
				Vector2(-0.45, -3.0), Vector2(0.45, 3.0))
	var construction_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var checksum := 0

	started = Time.get_ticks_usec()
	for repeat in range(6):
		var samples := curve.tessellate(7, 3.0)
		if samples.size() < count + 1:
			return {"error": "Curve2D adaptive subdivision dropped control points"}
		if not samples[0].is_equal_approx(curve.get_point_position(0)) or not samples[samples.size() - 1].is_equal_approx(curve.get_point_position(count)):
			return {"error": "Curve2D adaptive endpoints changed"}
		checksum += samples.size()
	var adaptive_ms := float(Time.get_ticks_usec() - started) / 1000.0

	started = Time.get_ticks_usec()
	for repeat in range(6):
		var samples := curve.tessellate_even_length(9, 0.75)
		if samples.size() < count + 1:
			return {"error": "Curve2D even-length subdivision dropped control points"}
		checksum += samples.size()
	var even_ms := float(Time.get_ticks_usec() - started) / 1000.0

	started = Time.get_ticks_usec()
	for repeat in range(6):
		curve.set_bake_interval(0.75 + float(repeat) * 0.01)
		var samples := curve.get_baked_points()
		if samples.size() < count + 1:
			return {"error": "Curve2D cached subdivision dropped control points"}
		if not samples[0].is_equal_approx(curve.get_point_position(0)) or not samples[samples.size() - 1].is_equal_approx(curve.get_point_position(count)):
			return {"error": "Curve2D baked endpoints changed"}
		checksum += samples.size()
	var bake_ms := float(Time.get_ticks_usec() - started) / 1000.0

	return {"control_points": count + 1, "passes": 6,
		"construction_ms": construction_ms, "adaptive_ms": adaptive_ms,
		"even_ms": even_ms, "bake_ms": bake_ms, "checksum": checksum}


# Closed Curve3D also benchmarks wrapping intervals and baked path frames.
func _curve_tessellation_3d(scale: int) -> Dictionary:
	var started := Time.get_ticks_usec()
	var count := 48 * scale
	var radius := float(count) * 0.5
	var curve := Curve3D.new()
	for i in range(count):
		var angle := TAU * float(i) / float(count)
		var position := Vector3(cos(angle) * radius, sin(angle) * radius, sin(angle * 3.0) * 4.0)
		var tangent := Vector3(-sin(angle) * 2.0, cos(angle) * 2.0, cos(angle * 3.0))
		curve.add_point(position, -tangent, tangent)
	curve.set_closed(true)
	var construction_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var checksum := 0

	started = Time.get_ticks_usec()
	for repeat in range(6):
		var samples := curve.tessellate(7, 3.0)
		if samples.size() < count + 1 or not samples[0].is_equal_approx(samples[samples.size() - 1]):
			return {"error": "Closed Curve3D adaptive subdivision invalid"}
		checksum += samples.size()
	var adaptive_ms := float(Time.get_ticks_usec() - started) / 1000.0

	started = Time.get_ticks_usec()
	for repeat in range(6):
		var samples := curve.tessellate_even_length(9, 0.75)
		if samples.size() < count + 1 or not samples[0].is_equal_approx(samples[samples.size() - 1]):
			return {"error": "Closed Curve3D even-length subdivision invalid"}
		checksum += samples.size()
	var even_ms := float(Time.get_ticks_usec() - started) / 1000.0

	started = Time.get_ticks_usec()
	for repeat in range(6):
		curve.set_bake_interval(0.75 + float(repeat) * 0.01)
		var samples := curve.get_baked_points()
		if samples.size() < count + 1 or not samples[0].is_equal_approx(samples[samples.size() - 1]):
			return {"error": "Closed Curve3D baked-cache rebuild invalid"}
		checksum += samples.size()
	var bake_ms := float(Time.get_ticks_usec() - started) / 1000.0

	return {"control_points": count, "closed": true, "passes": 6,
		"construction_ms": construction_ms, "adaptive_ms": adaptive_ms,
		"even_ms": even_ms, "bake_ms": bake_ms, "checksum": checksum}


# Separate scalar bake, baked distance search, and projection timings.
# Run in the existing isolated process/RSS watchdog, with deterministic input.
func _curve_bake(scale: int) -> Dictionary:
	var curve := Curve.new()
	curve.set_bake_resolution(1000)
	var points_count := mini(32 * scale, 512)
	for i in range(points_count):
		var x := float(i) / float(points_count - 1)
		var y := float((i * 73) % 257) / 257.0
		curve.add_point(Vector2(x, y))

	var initial_count := curve.get_point_count()
	curve.clean_dupes()
	if initial_count != points_count or curve.get_point_count() != points_count:
		return {"error": "Curve clean_dupes removed distinct points"}

	var bake_usec := 0
	var sample_usec := 0
	var checksum := 0.0
	var iterations := mini(12 * scale, 1200)
	for i in range(iterations):
		var index := i % points_count
		curve.set_point_value(index, float((i * 37) % 251) / 251.0)
		var start := Time.get_ticks_usec()
		curve.bake()
		bake_usec += Time.get_ticks_usec() - start
		start = Time.get_ticks_usec()
		for sample in range(16):
			checksum += curve.sample_baked(float((i * 17 + sample * 23) % 997) / 997.0)
		sample_usec += Time.get_ticks_usec() - start
	if is_nan(checksum) or is_inf(checksum):
		return {"error": "Non-finite Curve sample checksum"}
	return {"control_points": points_count, "rebakes": iterations, "samples": iterations * 16,
			"bake_ms": float(bake_usec) / 1000.0, "sample_ms": float(sample_usec) / 1000.0,
			"checksum": checksum}


func _curve_nearest(scale: int) -> Dictionary:
	var path2 := Curve2D.new()
	var path3 := Curve3D.new()
	path2.set_bake_interval(2.0)
	path3.set_bake_interval(2.0)
	path3.set_up_vector_enabled(false)
	for i in range(16):
		var x := float(i) * 20.0
		var y := float((i * 37) % 41)
		path2.add_point(Vector2(x, y))
		path3.add_point(Vector3(x, y, float((i * 29) % 31)))
	var len2 := path2.get_baked_length()
	var len3 := path3.get_baked_length()
	if len2 <= 0.0 or len3 <= 0.0:
		return {"error": "Curve2D/3D baking produced invalid lengths"}

	var queries := mini(500 * scale, 100000)
	var checksum := 0.0
	var started := Time.get_ticks_usec()
	for i in range(queries):
		var point2 := Vector2(float((i * 17) % 310), float((i * 19) % 100 - 30))
		var point3 := Vector3(point2.x, point2.y, float((i * 31) % 67))
		checksum += path2.get_closest_offset(point2)
		checksum += path3.get_closest_offset(point3)
	var offsets_ms := float(Time.get_ticks_usec() - started) / 1000.0

	started = Time.get_ticks_usec()
	for i in range(queries):
		var point2 := Vector2(float((i * 17) % 310), float((i * 19) % 100 - 30))
		var point3 := Vector3(point2.x, point2.y, float((i * 31) % 67))
		checksum += path2.get_closest_point(point2).x
		checksum += path3.get_closest_point(point3).x
	var points_ms := float(Time.get_ticks_usec() - started) / 1000.0

	started = Time.get_ticks_usec()
	for i in range(queries):
		var fraction := float((i * 37) % 997) / 997.0
		checksum += path2.sample_baked(fraction * len2).x
		checksum += path3.sample_baked(fraction * len3).x
	var sample_ms := float(Time.get_ticks_usec() - started) / 1000.0

	if is_nan(checksum) or is_inf(checksum):
		return {"error": "Non-finite Curve2D/3D projection checksum"}
	return {"queries_per_operation": queries, "baked_points_2d": path2.get_baked_points().size(),
			"baked_points_3d": path3.get_baked_points().size(),
			"closest_offset_ms": offsets_ms, "closest_point_ms": points_ms,
			"sample_baked_ms": sample_ms, "checksum": checksum}


func _astar_grid_rebuild(scale: int) -> Dictionary:
	# Alternate wide/tall layouts to stress construction and row-major indexing.
	# Cap the dimensions for opt-in brutal presets, to avoid 4-billion-cell OOM.
	var side := mini(64 * scale, 2048)
	var grid := AStarGrid2D.new()
	var builds_ms := 0.0
	var shrinks_ms := 0.0
	var checksum := 0
	var mem_before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	for cycle in range(3):
		var region_size := Vector2i(side, side >> 1) if cycle % 2 == 0 else Vector2i(side >> 1, side)
		var region := Rect2i(Vector2i(-17, -9), region_size)
		var started := Time.get_ticks_usec()
		grid.set_region(region)
		grid.update()
		builds_ms += float(Time.get_ticks_usec() - started) / 1000.0
		var last := region.position + region.size - Vector2i.ONE
		if grid.is_dirty() or grid.get_point_position(last) != Vector2(last):
			return {"error": "Grid rebuild changed cell positions"}
		if grid.is_point_solid(last):
			return {"error": "Grid rebuild kept an obstacle in a new region"}
		var start := region.position
		var target := start + Vector2i(0, 3)
		var path := grid.get_id_path(start, target)
		if path.size() != 4 or path[0] != start or path[3] != target:
			return {"error": "Grid rebuilt with an invalid route"}
		grid.set_point_solid(last, true)
		checksum += path.size() + int(grid.is_point_solid(last))

		started = Time.get_ticks_usec()
		grid.set_region(Rect2i(10, 20, 8, 8))
		grid.update()
		shrinks_ms += float(Time.get_ticks_usec() - started) / 1000.0
		if grid.get_point_position(Vector2i(17, 27)) != Vector2(17, 27):
			return {"error": "Grid shrink corrupted cell indices"}
		if grid.is_point_solid(Vector2i(17, 27)):
			return {"error": "Grid shrink retained a stale obstacle"}
	var mem_after_shrink := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	grid.clear()
	var mem_after_clear := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	return {
		"cycles": 3,
		"max_grid_cells": side * (side >> 1),
		"build_ms": builds_ms,
		"shrink_ms": shrinks_ms,
		"static_memory_after_shrink_delta_bytes": mem_after_shrink - mem_before,
		"static_memory_after_clear_delta_bytes": mem_after_clear - mem_before,
		"checksum": checksum,
	}


# Isolate send throughput from packet parsing and incoming stream polling.
func _packet_tx_batch(scale: int) -> Dictionary:
	var stream := StreamPeerBuffer.new()
	var packets := PacketPeerStream.new()
	packets.set_stream_peer(stream)
	packets.set_output_buffer_max_size(32768)
	var payload := PackedByteArray([0, 2, 3, 4, 5, 6, 7, 8])
	var count := 1200 * scale
	var started := Time.get_ticks_usec()
	for i in range(count):
		payload[0] = i & 255
		if packets.put_packet(payload) != OK:
			return {"error": "Packet transmit batch write failed"}
	var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
	var expected_bytes := count * (payload.size() + 4)
	if stream.get_size() != expected_bytes:
		return {"error": "Packet transmit batch changed framing lengths"}
	var wire := stream.get_data_array()
	if wire[0] != payload.size() or wire[4] != 0 or wire[expected_bytes - payload.size()] != ((count - 1) & 255):
		return {"error": "Packet transmit batch corrupted framing payload"}
	return {"packets": count, "wire_bytes": expected_bytes,
		"send_ms": elapsed, "checksum": int(wire[4]) + int(wire[expected_bytes - payload.size()])}


# Isolate receive throughput by constructing all complete frames outside timing.
func _packet_rx_batch(scale: int) -> Dictionary:
	var count := 1200 * scale
	var wire := PackedByteArray()
	wire.resize(count * 5)
	for i in range(count):
		var offset := i * 5
		wire[offset] = 1
		wire[offset + 1] = 0
		wire[offset + 2] = 0
		wire[offset + 3] = 0
		wire[offset + 4] = i & 255
	var stream := StreamPeerBuffer.new()
	stream.set_data_array(wire)
	var packets := PacketPeerStream.new()
	packets.set_input_buffer_max_size(32768)
	packets.set_stream_peer(stream)
	var checksum := 0
	var started := Time.get_ticks_usec()
	for i in range(count):
		var payload := packets.get_packet()
		if packets.get_packet_error() != OK or payload.size() != 1 or payload[0] != (i & 255):
			return {"error": "Packet receive batch lost frame %d" % i}
		checksum += int(payload[0])
	var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
	return {"packets": count, "wire_bytes": wire.size(),
		"receive_ms": elapsed, "checksum": checksum}


# Alternate small and large variants to expose scratch allocation churn.
func _packet_variant_reuse(scale: int) -> Dictionary:
	var stream := StreamPeerBuffer.new()
	var packets := PacketPeerStream.new()
	packets.set_stream_peer(stream)
	packets.set_encode_buffer_max_size(32768)
	packets.set_input_buffer_max_size(32768)
	packets.set_output_buffer_max_size(32768)
	var inputs: Array[String] = ["x".repeat(16), "y".repeat(256),
			"z".repeat(4096), "q".repeat(32), "r".repeat(8192)]
	var checksum := 0
	var count := 250 * scale
	var started := Time.get_ticks_usec()
	for i in range(count):
		stream.clear()
		var original := inputs[i % inputs.size()]
		if packets.put_var(original) != OK:
			return {"error": "Packet Variant encode failed"}
		stream.seek(0)
		var decoded = packets.get_var()
		if not (decoded is String) or decoded != original:
			return {"error": "Packet Variant roundtrip failed at %d" % i}
		checksum += original.length()
	var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
	return {"packets": count, "variant_characters": checksum,
		"roundtrip_ms": elapsed, "checksum": checksum}


# Isolate end-to-end streaming GZIP/DEFLATE (including multi-chunk finish).
# The content is deliberately difficult to compress to stress the output
# queue and the bounded zlib scratch buffer.
func _gzip_stream(scale: int) -> Dictionary:
	var payload := PackedByteArray()
	var input_size := mini(1024 * scale, 32768)
	payload.resize(input_size)
	var seed := 0x519a07f3
	for i in range(input_size):
		seed = (seed * 1664525 + 1013904223) & 0xffffffff
		payload[i] = (seed >> 24) & 255

	var compression_ms := 0.0
	var decompression_ms := 0.0
	var bytes_encoded := 0
	var checksum := 0
	var runs := mini(20 * scale, 1000)
	for i in range(runs):
		var use_deflate := i % 2 == 0
		var started := Time.get_ticks_usec()
		var encoder := StreamPeerGZIP.new()
		if encoder.start_compression(use_deflate) != OK:
			return {"error": "GZIP stream initialization failed"}
		if encoder.put_data(payload) != OK or encoder.finish() != OK:
			return {"error": "GZIP stream compression failed"}
		var raw_result: Array = encoder.get_data(encoder.get_available_bytes())
		if raw_result[0] != OK:
			return {"error": "GZIP compressed data read failed"}
		var encoded: PackedByteArray = raw_result[1]
		compression_ms += float(Time.get_ticks_usec() - started) / 1000.0

		started = Time.get_ticks_usec()
		var decoder := StreamPeerGZIP.new()
		if decoder.start_decompression(use_deflate) != OK:
			return {"error": "GZIP stream decoder initialization failed"}
		if decoder.put_data(encoded) != OK:
			return {"error": "GZIP stream decompression failed"}
		var restored_result: Array = decoder.get_data(input_size)
		if restored_result[0] != OK:
			return {"error": "GZIP restored data read failed"}
		var restored: PackedByteArray = restored_result[1]
		decompression_ms += float(Time.get_ticks_usec() - started) / 1000.0
		if restored != payload:
			return {"error": "GZIP or DEFLATE stream changed payload bytes"}
		bytes_encoded += encoded.size()
		checksum += restored[i % restored.size()]
	return {
		"roundtrips": runs,
		"input_size": input_size,
		"encoded_total_bytes": bytes_encoded,
		"compression_ms": compression_ms,
		"decompression_ms": decompression_ms,
		"checksum": checksum,
	}


# Isolate the per-expanded-cell neighbor hot path. A narrow gate in a long
# barrier forces both cardinal and diagonal searches to expand many cells.
# Keep grid construction outside the four timed search modes.
func _astar_grid_neighbors(scale: int) -> Dictionary:
	var width := mini(64 * scale, 1024)
	var height: int = width >> 1
	var grid := AStarGrid2D.new()
	var region := Rect2i(-23, 11, width, height)
	var started := Time.get_ticks_usec()
	grid.region = region
	grid.update()
	var wall_x := region.position.x + (width >> 1)
	var gate_y := region.position.y + (height >> 1)
	for y in range(region.position.y + 1, region.position.y + height - 1):
		if y != gate_y:
			grid.set_point_solid(Vector2i(wall_x, y), true)
	var build_ms := float(Time.get_ticks_usec() - started) / 1000.0

	var modes: Array[int] = [
		AStarGrid2D.DIAGONAL_MODE_NEVER,
		AStarGrid2D.DIAGONAL_MODE_ALWAYS,
		AStarGrid2D.DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE,
		AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES,
	]
	var timings: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var checksum := 0
	const QUERIES = 12
	for mode_index in range(modes.size()):
		grid.diagonal_mode = modes[mode_index]
		started = Time.get_ticks_usec()
		for q in range(QUERIES):
			var origin := region.position + Vector2i(1, (q * 13) % height)
			var target := region.position + Vector2i(width - 2, (q * 17 + 5) % height)
			var path := grid.get_id_path(origin, target)
			if path.is_empty() or path.front() != origin or path.back() != target:
				return {"error": "AStarGrid neighbor search failed for mode %d" % mode_index}
			checksum += path.size()
		timings[mode_index] = float(Time.get_ticks_usec() - started) / 1000.0

	return {
		"cells": width * height,
		"queries_per_mode": QUERIES,
		"build_ms": build_ms,
		"cardinal_ms": timings[0],
		"diagonal_always_ms": timings[1],
		"diagonal_one_walkable_ms": timings[2],
		"diagonal_no_obstacles_ms": timings[3],
		"checksum": checksum,
	}


# Exercises OPCODE_CONSTRUCT_ARRAY with runtime-dependent values, not
# compile-time constants or typed-array construction.
func _array_literals(scale: int) -> Dictionary:
	var iterations := mini(60000 * scale, 1200000)
	var checksum := 0
	var started := Time.get_ticks_usec()
	for i in range(iterations):
		var row: Array = [
			i, i + 1, i + 2, i + 3,
			i + 4, i + 5, i + 6, i + 7,
			i + 8, i + 9, i + 10, i + 11,
			i + 12, i + 13, i + 14, i + 15,
		]
		if row.size() != 16 or row[0] != i or row[15] != i + 15:
			return {"error": "Array literal contents changed"}
		checksum = (checksum + int(row[3]) + int(row[12])) & 0x7fffffff
	var duration_ms := float(Time.get_ticks_usec() - started) / 1000.0
	return {"arrays": iterations, "elements": 16 * iterations,
		"construction_ms": duration_ms, "checksum": checksum}


# Checks that Dictionary.keys() and values() maintain the insertion-order
# pairing and avoid repeated indexed destination writes.
func _dictionary_snapshot(scale: int) -> Dictionary:
	var count := mini(256 * scale, 8192)
	var rounds := mini(100 * scale, 1500)
	var values_by_key: Dictionary = {}
	for i in range(count):
		values_by_key[i] = i * 3 + 17
	var checksum := 0
	var started := Time.get_ticks_usec()
	for i in range(rounds):
		var keys := values_by_key.keys()
		var values := values_by_key.values()
		if keys.size() != count or values.size() != count:
			return {"error": "Dictionary snapshot size mismatch"}
		var index := i % count
		if values_by_key[keys[index]] != values[index]:
			return {"error": "Dictionary keys/values misaligned"}
		checksum = (checksum + int(keys[index]) + int(values[index])) & 0x7fffffff
	var duration_ms := float(Time.get_ticks_usec() - started) / 1000.0
	return {"entries": count, "snapshots": rounds,
		"snapshot_ms": duration_ms, "checksum": checksum}

# Stress long Jump Point Search scans independently from ordinary grid A*.
# An empty large grid is deliberately adversarial for JPS scanning because
# it has few forced neighbors and requires long straight/diagonal sweeps.
func _astar_grid_jps(scale: int) -> Dictionary:
	var side: int = mini(48 * scale, 512)
	var region := Rect2i(-23, 11, side, side)
	var grid := AStarGrid2D.new()
	var start := Time.get_ticks_usec()
	grid.region = region
	grid.update()
	grid.jumping_enabled = true
	var setup_ms := float(Time.get_ticks_usec() - start) / 1000.0

	var modes: Array[int] = [
		AStarGrid2D.DIAGONAL_MODE_NEVER,
		AStarGrid2D.DIAGONAL_MODE_ALWAYS,
		AStarGrid2D.DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE,
		AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES,
	]
	var mode_ms: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var count: int = 24 * scale
	var checksum := 0

	for mode_index in range(modes.size()):
		grid.diagonal_mode = modes[mode_index]
		start = Time.get_ticks_usec()
		for q in range(count):
			var y := region.position.y + 1 + (q * 17) % (side - 2)
			var from := Vector2i(region.position.x + 1, y)
			var target := Vector2i(region.position.x + side - 2, y)
			var path := grid.get_id_path(from, target)
			if path.is_empty() or path.front() != from or path.back() != target:
				return {"error": "Jump Point Search horizontal path corrupted in mode %d" % mode_index}
			checksum += path.size()
		mode_ms[mode_index] = float(Time.get_ticks_usec() - start) / 1000.0

	# Diagonal sweeps force the JPS main loop, not just the straight
	# _forced_successor() fast path. They are not valid in cardinal-only mode.
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	start = Time.get_ticks_usec()
	var from_diag := region.position + Vector2i.ONE
	var to_diag := region.position + region.size - Vector2i(2, 2)
	for q in range(count):
		var route := grid.get_id_path(from_diag, to_diag)
		if route.is_empty() or route.front() != from_diag or route.back() != to_diag:
			return {"error": "Jump Point Search diagonal path corrupted"}
		checksum += route.size()
	var diagonal_ms := float(Time.get_ticks_usec() - start) / 1000.0

	return {
		"cells": side * side,
		"queries_per_mode": count,
		"setup_ms": setup_ms,
		"cardinal_ms": mode_ms[0],
		"diagonal_always_ms": mode_ms[1],
		"diagonal_one_walkable_ms": mode_ms[2],
		"diagonal_no_obstacles_ms": mode_ms[3],
		"diagonal_sweep_ms": diagonal_ms,
		"checksum": checksum,
	}


# Long connected chains stress GodotPhysics island traversal depth. With a
# recursive implementation these can exhaust the native physics thread stack.
func _physics_joint_chain_2d(scale: int, frames: int) -> Dictionary:
	var world := Node2D.new()
	root.add_child(world)
	var count := mini(64 * scale, 4096)
	var circle := CircleShape2D.new()
	circle.radius = 0.3
	var previous: RigidBody2D = null
	for i in range(count):
		var body := RigidBody2D.new()
		body.name = "body_%d" % i
		body.gravity_scale = 0.0
		body.can_sleep = false
		body.position = Vector2(float(i) * 3.0, 0.0)
		var shape := CollisionShape2D.new()
		shape.shape = circle
		body.add_child(shape)
		world.add_child(body)
		if previous != null:
			var joint := PinJoint2D.new()
			joint.position = (previous.position + body.position) * 0.5
			world.add_child(joint)
			joint.node_a = joint.get_path_to(previous)
			joint.node_b = joint.get_path_to(body)
		previous = body
	if world.get_child_count() != count * 2 - 1:
		world.queue_free()
		return {"error": "2D chain construction lost joints"}

	var peak_physics_ms := 0.0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for i in range(frames):
		await physics_frame
		var now := Time.get_ticks_usec()
		frame_intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	world.queue_free()
	await process_frame
	var statistics := _frame_statistics(frame_intervals)
	return {"bodies": count, "joints": count - 1, "physics_frames": frames,
		"peak_physics_ms": peak_physics_ms, "frame_interval_ms": statistics,
		"frame_p95_ms": statistics["p95"]}


func _physics_joint_chain_3d(scale: int, frames: int) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var count := mini(32 * scale, 3072)
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	var previous: RigidBody3D = null
	for i in range(count):
		var body := RigidBody3D.new()
		body.name = "body_%d" % i
		body.gravity_scale = 0.0
		body.can_sleep = false
		body.position = Vector3(float(i) * 3.0, 0.0, 0.0)
		var shape := CollisionShape3D.new()
		shape.shape = sphere
		body.add_child(shape)
		world.add_child(body)
		if previous != null:
			var joint := PinJoint3D.new()
			joint.position = (previous.position + body.position) * 0.5
			world.add_child(joint)
			joint.node_a = joint.get_path_to(previous)
			joint.node_b = joint.get_path_to(body)
		previous = body
	if world.get_child_count() != count * 2 - 1:
		world.queue_free()
		return {"error": "3D chain construction lost joints"}

	var peak_physics_ms := 0.0
	var frame_intervals: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for i in range(frames):
		await physics_frame
		var now := Time.get_ticks_usec()
		frame_intervals.append(float(now - last_tick) / 1000.0)
		last_tick = now
		peak_physics_ms = maxf(peak_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	world.queue_free()
	await process_frame
	var statistics := _frame_statistics(frame_intervals)
	return {"bodies": count, "joints": count - 1, "physics_frames": frames,
		"peak_physics_ms": peak_physics_ms, "frame_interval_ms": statistics,
		"frame_p95_ms": statistics["p95"]}



# High-bandwidth bulk region writes: profile obstruction masks and point
# weight updates independently of construction and pathfinding.
func _astar_grid_fill(scale: int) -> Dictionary:
	var side: int = mini(64 * scale, 1024)
	var region := Rect2i(-17, 23, side, side)
	var grid := AStarGrid2D.new()
	grid.region = region
	var started := Time.get_ticks_usec()
	grid.update()
	var build_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var interior := Rect2i(region.position + Vector2i.ONE, region.size - Vector2i(2, 2))
	var clipped := Rect2i(region.position - Vector2i(5, 5), region.size + Vector2i(10, 10))
	var cycles: int = 12 * scale
	var memory_before := int(Performance.get_monitor(Performance.MEMORY_STATIC))

	started = Time.get_ticks_usec()
	for i in range(cycles):
		grid.fill_solid_region(clipped, true)
		grid.fill_solid_region(interior, false)
	var mask_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var border := region.position
	var center := region.position + Vector2i(side >> 1, side >> 1)
	if not grid.is_point_solid(border) or grid.is_point_solid(center):
		return {"error": "AStarGrid bulk obstacle fill changed border clipping"}

	started = Time.get_ticks_usec()
	for i in range(cycles):
		grid.fill_weight_scale_region(clipped, 2.0 + float(i))
		grid.fill_weight_scale_region(interior, 1.0)
	var weight_ms := float(Time.get_ticks_usec() - started) / 1000.0
	if not is_equal_approx(grid.get_point_weight_scale(border), 1.0 + float(cycles)):
		return {"error": "AStarGrid bulk weight fill changed border cells"}
	if not is_equal_approx(grid.get_point_weight_scale(center), 1.0):
		return {"error": "AStarGrid bulk weight fill changed inner cells"}

	return {
		"cells": side * side,
		"passes": cycles,
		"build_ms": build_ms,
		"solid_mask_ms": mask_ms,
		"weight_scale_ms": weight_ms,
		"static_memory_change_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)) - memory_before,
		"checksum": int(grid.is_point_solid(border)) + int(grid.get_point_weight_scale(border)),
	}
