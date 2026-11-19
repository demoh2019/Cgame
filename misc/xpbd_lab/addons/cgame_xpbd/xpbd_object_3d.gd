extends Node3D
class_name CgameXPBDObject3D
## Opt-in visual wrapper for the pure CgameXPBDSolver3D.
## Samples are rendered as line segments. No GPU cloth mesh or rigid coupling.

const Solver = preload("res://addons/cgame_xpbd/xpbd_solver_3d.gd")

enum Mode { ROPE, CLOTH }

@export var simulation_mode: Mode = Mode.ROPE
@export_range(2, 120, 1) var segments: int = 24
@export_range(2, 60, 1) var cloth_columns: int = 20
@export_range(2, 60, 1) var cloth_rows: int = 14
@export_range(0.05, 2.0, 0.01) var cloth_spacing: float = 0.32
@export var rope_start: Vector3 = Vector3(0.0, 4.0, 0.0)
@export var rope_end: Vector3 = Vector3(5.0, 2.0, 0.0)
@export var cloth_origin: Vector3 = Vector3(-3.0, 5.0, 0.0)
@export_range(0.001, 100.0, 0.01, "or_greater") var total_mass: float = 5.0
@export_range(0.0, 0.01, 0.0000001, "or_greater") var stretch_compliance: float = 0.000001
@export_range(0.0, 0.01, 0.0000001, "or_greater") var bend_compliance: float = 0.0003
@export_range(0.0, 0.01, 0.0000001, "or_greater") var shear_compliance: float = 0.000005
@export_range(0.0, 10.0, 0.05, "or_greater") var tearing_strain: float = 0.0
@export_range(1, 30, 1) var solver_iterations: int = 12
@export_range(1, 8, 1) var simulation_substeps: int = 3
@export var gravity: Vector3 = Vector3(0.0, -9.81, 0.0)
@export var wind_velocity: Vector3 = Vector3.ZERO
@export var enable_floor: bool = true
@export var floor_world_height: float = 0.0
@export var enable_sphere: bool = false
@export var sphere_world_center: Vector3 = Vector3.ZERO
@export_range(0.01, 10.0, 0.01, "or_greater") var sphere_radius: float = 1.0
@export var line_color: Color = Color(0.25, 0.85, 1.0)

var solver: CgameXPBDSolver3D = Solver.new()
var _line_mesh: ImmediateMesh
var _visual: MeshInstance3D
var _line_material: StandardMaterial3D


func _ready() -> void:
	_line_mesh = ImmediateMesh.new()
	_visual = MeshInstance3D.new()
	_visual.mesh = _line_mesh
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_visual)
	_line_material = StandardMaterial3D.new()
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.albedo_color = line_color
	_line_material.no_depth_test = false
	rebuild()


func rebuild() -> void:
	solver.solver_iterations = solver_iterations
	solver.substeps = simulation_substeps
	solver.floor_enabled = enable_floor
	# All point coordinates live in the solver's local coordinates. World-space
	# collision markers are transformed once when the simulation is rebuilt.
	solver.floor_height = to_local(Vector3(global_position.x, floor_world_height, global_position.z)).y
	if simulation_mode == Mode.CLOTH:
		solver.create_cloth(cloth_origin, cloth_columns, cloth_rows, cloth_spacing, total_mass, stretch_compliance, shear_compliance, bend_compliance, true, tearing_strain)
	else:
		solver.create_rope(rope_start, rope_end, segments, total_mass, stretch_compliance, bend_compliance, true, false, tearing_strain)
	if enable_sphere:
		solver.add_sphere_collider(to_local(sphere_world_center), sphere_radius)
	_update_visuals()


func _physics_process(delta: float) -> void:
	solver.step(delta, global_transform.basis.inverse() * gravity, global_transform.basis.inverse() * wind_velocity)
	_update_visuals()


func _update_visuals() -> void:
	if _line_mesh == null:
		return
	_line_mesh.clear_surfaces()
	if solver.active_constraint_count() == 0:
		return
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _line_material)
	for c in solver.constraints:
		if not c["active"] or c["kind"] != "stretch":
			continue
		var a: int = c["a"]
		var b: int = c["b"]
		_line_mesh.surface_add_vertex(solver.positions[a])
		_line_mesh.surface_add_vertex(solver.positions[b])
	_line_mesh.surface_end()
