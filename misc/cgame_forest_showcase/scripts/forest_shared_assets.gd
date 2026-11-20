extends RefCounted
## Shared immutable prototype meshes and materials for every streamed forest tile.
##
## WorldPartition3D still manages per-cell MultiMesh buffers and collision
## shapes. These long-lived lightweight templates avoid constructing the same
## CylinderMesh/SphereMesh/QuadMesh/ShaderMaterial hundreds of times.
## All factories run on the main thread; this does not access rendering or
## physics servers from a worker thread.

static var _trunk: CylinderMesh
static var _canopy: SphereMesh
static var _distant_canopy: SphereMesh
static var _grass: QuadMesh
static var _rock: SphereMesh
static var _ground_material: StandardMaterial3D


static func tree_trunk() -> CylinderMesh:
    if _trunk == null:
        _trunk = CylinderMesh.new()
        _trunk.top_radius = 0.25
        _trunk.bottom_radius = 0.40
        _trunk.height = 3.8
        _trunk.radial_segments = 7

        var bark := StandardMaterial3D.new()
        bark.albedo_color = Color(0.22, 0.12, 0.078)
        bark.roughness = 0.96
        _trunk.material = bark
    return _trunk


static func tree_canopy() -> SphereMesh:
    if _canopy == null:
        _canopy = SphereMesh.new()
        _canopy.radius = 1.0
        _canopy.height = 2.0
        _canopy.radial_segments = 11
        _canopy.rings = 6

        var wind := ShaderMaterial.new()
        wind.shader = preload("res://shaders/foliage_wind.gdshader")
        _canopy.material = wind
    return _canopy


static func distant_tree_canopy() -> SphereMesh:
    # Simplified low-poly mesh for distant forest HLOD. Kept independent of
    # full wind-animated canopies so only nearby vegetation pays shader cost.
    if _distant_canopy == null:
        _distant_canopy = SphereMesh.new()
        _distant_canopy.radius = 1.0
        _distant_canopy.height = 2.0
        _distant_canopy.radial_segments = 5
        _distant_canopy.rings = 2

        var leaves := StandardMaterial3D.new()
        leaves.albedo_color = Color(0.27, 0.42, 0.23)
        leaves.roughness = 0.95
        _distant_canopy.material = leaves
    return _distant_canopy


static func grass_blade() -> QuadMesh:
    if _grass == null:
        _grass = QuadMesh.new()
        _grass.size = Vector2(0.34, 0.75)

        var grass_material := ShaderMaterial.new()
        grass_material.shader = preload("res://shaders/grass_wind.gdshader")
        _grass.material = grass_material
    return _grass


static func rock_mesh() -> SphereMesh:
    if _rock == null:
        _rock = SphereMesh.new()
        _rock.radius = 1.0
        _rock.height = 2.0
        _rock.radial_segments = 8
        _rock.rings = 4

        var stone := StandardMaterial3D.new()
        stone.albedo_color = Color(0.28, 0.31, 0.29)
        stone.roughness = 0.92
        _rock.material = stone
    return _rock


static func ground_material() -> StandardMaterial3D:
    if _ground_material == null:
        _ground_material = StandardMaterial3D.new()
        _ground_material.vertex_color_use_as_albedo = true
        _ground_material.roughness = 0.97
    return _ground_material
