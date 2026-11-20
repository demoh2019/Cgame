extends RefCounted
## Hover outline: one target at a time, colours by kind, never steals overlays.
const HoverOutline = preload("res://scripts/client/hover_outline.gd")


func run(t) -> void:
	t.current = "hover outline"
	var outline := HoverOutline.new()
	var a := Node3D.new()
	var a_mesh := MeshInstance3D.new()
	a.add_child(a_mesh)
	var b := Node3D.new()
	var b_mesh := MeshInstance3D.new()
	b.add_child(b_mesh)
	outline.set_target({"node": a, "kind": "zombie"})
	t.check(a_mesh.material_overlay != null, "hovered zombie is outlined")
	outline.set_target({"node": b, "kind": "bag"})
	t.check(a_mesh.material_overlay == null, "previous target loses its outline")
	t.check(b_mesh.material_overlay != null, "new target gains it")
	var other := ShaderMaterial.new()
	var c := Node3D.new()
	var c_mesh := MeshInstance3D.new()
	c_mesh.material_overlay = other
	c.add_child(c_mesh)
	outline.set_target({"node": c, "kind": "player"})
	t.check(c_mesh.material_overlay == other, "existing overlays are never replaced")
	outline.set_target({})
	t.check(b_mesh.material_overlay == null, "clearing removes the outline")
	a.free()
	b.free()
	c.free()
