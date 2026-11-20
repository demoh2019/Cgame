extends RefCounted
## Occlusion silhouette overlay: applied to every mesh and shared.
const Silhouette = preload("res://scripts/client/occlusion_silhouette.gd")


func run(t) -> void:
	t.current = "X-ray silhouette overlay"
	var root := Node3D.new()
	var a := MeshInstance3D.new()
	var b := MeshInstance3D.new()
	root.add_child(a)
	a.add_child(b)
	t.eq(Silhouette.apply(root), 2, "every nested mesh gets the overlay")
	t.check(a.material_overlay == b.material_overlay and a.material_overlay != null, "one shared material")
	Silhouette.apply(root, Silhouette.SELF_TINT, false)
	t.check(a.material_overlay == null, "can be removed again")
	t.check(Silhouette.SHADER.code.contains("depth_test_inverted"), "only draws where hidden")
	root.free()
