extends MultiMeshInstance3D
## One low-poly canopy batch per distant HLOD terrain tile.
##
## This is a visual-only replacement for streamed forest crowns. It copies
## the exact tree-placement RNG sequence used by streamed_forest_cell.gd, so
## detailed and distant trees align during WorldPartition3D handoff.
## No trunks, grass, collision shapes, physics or wind shaders are generated.
##
## Keep the same seed, tree count, clearing check, RNG calls and crown
## transform when changing the near-forest placement algorithm.

const TerrainHeight = preload("res://scripts/terrain_height.gd")
const SharedAssets = preload("res://scripts/forest_shared_assets.gd")
const CELL_SIZE: float = 32.0
const TREE_COUNT: int = 54


func configure(cell: Vector2i, cached_batch: MultiMesh = null) -> void:
    name = "DistantForestCanopies"
    cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

    # A cached MultiMesh contains immutable world-independent local tree
    # transforms. Its renderer resource can outlive any individual HLOD node.
    if cached_batch != null:
        multimesh = cached_batch
        return

    var rng := RandomNumberGenerator.new()
    rng.seed = 913481 + cell.x * 73856093 + cell.y * 19349663

    var transforms: Array[Transform3D] = []
    var colors: Array[Color] = []
    for i in range(TREE_COUNT):
        var px: float = rng.randf_range(1.0, CELL_SIZE - 1.0)
        var pz: float = rng.randf_range(1.0, CELL_SIZE - 1.0)
        var wx: float = float(cell.x) * CELL_SIZE + px
        var wz: float = float(cell.y) * CELL_SIZE + pz
        if Vector2(wx, wz - 9.0).length() < 8.0:
            continue

        var scale: float = rng.randf_range(0.70, 1.5)
        var ground: float = TerrainHeight.height_at(wx, wz)
        var orientation := Basis(Vector3.UP, rng.randf_range(-PI, PI))
        transforms.push_back(Transform3D(
            orientation.scaled(Vector3(scale * 2.0, scale * 1.75, scale * 2.0)),
            Vector3(px, ground + scale * 4.15, pz)))

        # Consume precisely three random color samples as the near canopy does.
        # Slightly vary PBR per-instance color while retaining the material.
        var r: float = rng.randf()
        var g: float = rng.randf()
        var b: float = rng.randf()
        colors.push_back(Color(0.82 + 0.18 * r,
            0.83 + 0.17 * g, 0.80 + 0.20 * b, 1.0))

    var batch := MultiMesh.new()
    batch.transform_format = MultiMesh.TRANSFORM_3D
    batch.use_colors = true
    batch.mesh = SharedAssets.distant_tree_canopy()
    batch.instance_count = transforms.size()
    for i in range(transforms.size()):
        batch.set_instance_transform(i, transforms[i])
        batch.set_instance_color(i, colors[i])
    multimesh = batch
