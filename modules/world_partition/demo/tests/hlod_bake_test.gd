extends SceneTree

# Run after building at least a 3x3 region with --radius=1 --stride=8.
const OUTPUT := "res://generated/forest_proxy_%d_%d.tscn"
const Manifest = preload("res://tools/hlod_bake_manifest.gd")

func _initialize() -> void:
    call_deferred("_check")

func _check() -> void:
    var manifest: Dictionary = Manifest.read_valid_manifest(8)
    assert(not manifest.is_empty())
    assert(manifest.get("schema") == 1)
    assert(manifest.get("stride") == 8)
    var manifest_cells: Dictionary = manifest.get("cells", {})
    assert(manifest_cells.size() == 9)
    assert(Manifest.is_cached_proxy_valid(Vector2i(0, 0), manifest))
    assert(Manifest.is_cached_proxy_valid(Vector2i(1, 0), manifest))
    assert(not Manifest.is_cached_proxy_valid(Vector2i(1000, 1000), manifest))

    var scene_a := load(OUTPUT % [0, 0]) as PackedScene
    var scene_b := load(OUTPUT % [1, 0]) as PackedScene
    assert(scene_a != null and scene_b != null)

    var a := scene_a.instantiate() as Node3D
    var b := scene_b.instantiate() as Node3D
    assert(a != null and b != null)
    assert(a.get_script() == null)
    assert(b.get_script() == null)
    assert(a.get_node_or_null("Ground") is MeshInstance3D)

    var trunks_a := a.get_node_or_null("Trunks") as MultiMeshInstance3D
    var trunks_b := b.get_node_or_null("Trunks") as MultiMeshInstance3D
    var crowns_a := a.get_node_or_null("Canopies") as MultiMeshInstance3D
    assert(trunks_a != null and trunks_b != null and crowns_a != null)
    var a_count := trunks_a.multimesh.instance_count
    assert(a_count >= 19 and a_count <= 20)
    assert(trunks_b.multimesh.instance_count >= 19 and trunks_b.multimesh.instance_count <= 20)
    assert(crowns_a.multimesh.instance_count == a_count)
    assert(crowns_a.multimesh.mesh is SphereMesh)
    assert((crowns_a.multimesh.mesh as SphereMesh).radial_segments == 6)

    # Procedural seed follows cell X/Z; the two baked scenes differ.
    var first_a := trunks_a.multimesh.get_instance_transform(0).origin
    var first_b := trunks_b.multimesh.get_instance_transform(0).origin
    assert(first_a.distance_to(first_b) > 0.0001)
    assert(a.get_node("Trunks").get_script() == null)
    assert(a.position == Vector3.ZERO)

    a.free()
    b.free()
    print("Baked HLOD proxy regression checks passed")
    quit(0)
