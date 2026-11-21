extends RefCounted
## Visuals for a homestead crop plot: a tilled soil bed with plants that grow with
## the server-reported progress and turn their ripe colour when ready to harvest.

const PLANTS := 6
const RIPE_COLORS := {
	"carrot": Color(0.95, 0.5, 0.12),
	"potato": Color(0.72, 0.62, 0.38),
	"wheat": Color(0.9, 0.78, 0.35),
}
const GROW_COLOR := Color(0.28, 0.6, 0.2)


static func make(crop: String) -> Node3D:
	var bed := Node3D.new()
	bed.name = "FarmPlot"
	var soil := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 0.12, 1.2)
	soil.mesh = box
	soil.position.y = 0.04
	var soil_mat := StandardMaterial3D.new()
	soil_mat.albedo_color = Color(0.24, 0.16, 0.1)
	soil_mat.roughness = 1.0
	soil.material_override = soil_mat
	bed.add_child(soil)
	var plants := Node3D.new()
	plants.name = "Plants"
	bed.add_child(plants)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GROW_COLOR
	mat.roughness = 0.8
	var tall: bool = crop == "wheat"
	for i in PLANTS:
		var plant := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.06 if tall else 0.1
		cone.height = 0.6 if tall else 0.35
		cone.radial_segments = 5
		plant.mesh = cone
		plant.material_override = mat
		plant.position = Vector3(-0.35 + 0.35 * float(i % 3), 0.1, -0.2 + 0.4 * float(i / 3))
		plants.add_child(plant)
	plants.set_meta("material", mat)
	plants.set_meta("crop", crop)
	return bed


## Scales plants with growth (0..1) and switches to the ripe colour at 100%.
static func update(root: Node, plot: Dictionary) -> void:
	if root == null:
		return
	var plants := root.get_node_or_null("FarmPlot/Plants") as Node3D
	if plants == null:
		return
	var p: float = clampf(float(plot.get("progress", 0.0)), 0.0, 1.0)
	var s: float = lerpf(0.15, 1.0, p)
	plants.scale = Vector3(s, s, s)
	var mat := plants.get_meta("material") as StandardMaterial3D
	var ripe: Color = RIPE_COLORS.get(str(plants.get_meta("crop", "")), GROW_COLOR)
	var target: Color = ripe if p >= 1.0 else GROW_COLOR.lerp(GROW_COLOR.lightened(0.15), p)
	if mat != null and not mat.albedo_color.is_equal_approx(target):
		mat.albedo_color = target
