extends Node3D
## Siege outposts in the world: a banner pole whose flag shows the owner, a ring on the ground for the capture
## radius, and a floating label with the fortification, the capture progress and any war in progress.

const TerritoryControl = preload("res://scripts/shared/territory_control.gd")

var _nodes: Dictionary = {} # site id -> Node3D


func update_from(client) -> void:
	var seen: Dictionary = {}
	var group_id: int = int(client.you.get("party", {}).get("id", 0))
	for site in client.outposts:
		var id: int = int(site["id"])
		seen[id] = true
		if not _nodes.has(id):
			_nodes[id] = _make(site, client.world.height_at(float(site["x"]), float(site["z"])))
			add_child(_nodes[id])
		_refresh(_nodes[id], site, group_id)
	for id in _nodes.keys():
		if not seen.has(id):
			_nodes[id].queue_free()
			_nodes.erase(id)


func _make(site: Dictionary, ground: float) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(float(site["x"]), ground, float(site["z"]))
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.09
	pole_mesh.bottom_radius = 0.14
	pole_mesh.height = 7.0
	pole.mesh = pole_mesh
	pole.position.y = 3.5
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.22, 0.14)
	pole.material_override = wood
	root.add_child(pole)
	var flag := MeshInstance3D.new()
	flag.name = "Flag"
	var flag_mesh := BoxMesh.new()
	flag_mesh.size = Vector3(2.4, 1.5, 0.06)
	flag.mesh = flag_mesh
	flag.position = Vector3(1.3, 6.1, 0.0)
	flag.material_override = StandardMaterial3D.new()
	root.add_child(flag)
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = TerritoryControl.CAPTURE_RADIUS - 0.18
	ring_mesh.outer_radius = TerritoryControl.CAPTURE_RADIUS
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 6
	ring.mesh = ring_mesh
	ring.scale.y = 0.12
	ring.position.y = 0.12
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = ring_material
	root.add_child(ring)
	# A visible rough timber field workbench, positioned inside the flag's 6.5m
	# authoritative crafting radius. It is not an independent client station.
	var bench_material := StandardMaterial3D.new()
	bench_material.albedo_color = Color(0.33, 0.21, 0.12)
	var bench_top := MeshInstance3D.new()
	bench_top.name = "FieldWorkbench"
	var top_mesh := BoxMesh.new()
	top_mesh.size = Vector3(2.3, 0.25, 1.25)
	bench_top.mesh = top_mesh
	bench_top.position = Vector3(3.0, 1.05, -2.5)
	bench_top.material_override = bench_material
	root.add_child(bench_top)
	for support_x in [-0.85, 0.85]:
		var support := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.23, 0.9, 0.9)
		support.mesh = leg_mesh
		support.position = Vector3(3.0 + support_x, 0.5, -2.5)
		support.material_override = bench_material
		root.add_child(support)
	var label := Label3D.new()
	label.name = "Label"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 40
	label.pixel_size = 0.009
	label.outline_size = 10
	label.position.y = 8.4
	root.add_child(label)
	return root


func _refresh(root: Node3D, site: Dictionary, group_id: int) -> void:
	var owner: int = int(site["owner"])
	var color := Color(0.65, 0.66, 0.7)
	var status := "Neutral"
	if owner != 0:
		if owner == group_id and group_id != 0:
			color = Color(0.3, 0.85, 0.4)
			status = "YOURS"
		else:
			color = Color(0.95, 0.35, 0.3)
			status = "Held by party %d" % owner
	if bool(site["contested"]):
		color = Color(1.0, 0.8, 0.2)
		status = "CONTESTED"
	elif int(site["challenger"]) != 0:
		status = "Capture %d%%" % int(100.0 * float(site["progress"]) / maxf(1.0, float(site.get("capture_target", 30.0))))
	var guild: Dictionary = site.get("guild", {})
	if not guild.is_empty():
		status += "  [%s]" % str(guild.get("tag", guild.get("name", "")))
	var flag_material := (root.get_node("Flag") as MeshInstance3D).material_override as StandardMaterial3D
	flag_material.albedo_color = color
	flag_material.emission_enabled = true
	flag_material.emission = color * 0.45
	var ring_material := (root.get_node("Ring") as MeshInstance3D).material_override as StandardMaterial3D
	ring_material.albedo_color = Color(color.r, color.g, color.b, 0.6)
	var label := root.get_node("Label") as Label3D
	label.modulate = color.lightened(0.3)
	var field_bench: String = "Field bench LOCKED" if owner == 0 else (
		"Field bench CONTESTED" if bool(site.get("contested", false)) else "Field bench: defending party/guild")
	label.text = "OUTPOST #%d  Fort T%d\n%s\n%s" % [
		int(site["id"]), int(site.get("fortification", 0)), status, field_bench]
