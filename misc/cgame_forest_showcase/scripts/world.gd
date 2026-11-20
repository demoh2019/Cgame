# Reusable 3D vertical slice for Cgame.
# Uses only stock Godot runtime APIs plus the native AdaptiveResolution3D node in world.tscn.
extends Node3D

const WORLD_EXTENT: float = 64.0
const GRID_SEGMENTS: int = 112
const CHUNK_EDGE: float = 32.0
const CRYSTAL_TOTAL: int = 8

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var camera: Camera3D
var world_environment: Environment
var hud: Label
var hint: Label
var grass_chunks: Array[MultiMeshInstance3D] = []
var crystals: Array[Node3D] = []

var elapsed: float = 0.0
var hud_elapsed: float = 0.0
var collected: int = 0
var high_quality: bool = true
var mouse_sensitivity: float = 0.0018


func _ready() -> void:
    rng.seed = 913481
    _create_environment()
    _create_sun()
    _create_terrain()
    _create_forest()
    _create_grass()
    _create_rocks()
    _create_crystals()
    _create_camera()
    _create_hud()
    _apply_quality(true)
    _refresh_hud()


func height_at(x: float, z: float) -> float:
    # Spatially continuous analytic height: normals and instance positions agree.
    return 1.7 * sin(x * 0.058) * cos(z * 0.063) \
        + 0.85 * sin((x + z) * 0.135) \
        + 0.25 * sin(x * 0.47) * cos(z * 0.39)


func _normal_at(x: float, z: float) -> Vector3:
    var e: float = 0.3
    var dx: float = (height_at(x + e, z) - height_at(x - e, z)) / (2.0 * e)
    var dz: float = (height_at(x, z + e) - height_at(x, z - e)) / (2.0 * e)
    return Vector3(-dx, 1.0, -dz).normalized()


func _create_environment() -> void:
    var sky_material := ShaderMaterial.new()
    sky_material.shader = preload("res://shaders/atmosphere.gdshader")

    var sky := Sky.new()
    sky.sky_material = sky_material

    world_environment = Environment.new()
    world_environment.background_mode = Environment.BG_SKY
    world_environment.sky = sky
    world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    world_environment.tonemap_mode = Environment.TONE_MAPPER_AGX
    world_environment.tonemap_agx_white = 6.0
    world_environment.glow_enabled = true
    world_environment.glow_intensity = 0.35
    world_environment.fog_enabled = true
    world_environment.fog_density = 0.009
    world_environment.volumetric_fog_density = 0.015

    var node := WorldEnvironment.new()
    node.name = "SkyAndAtmosphere"
    node.environment = world_environment
    add_child(node)

    # This sample is intended for the Forward+ rendering backend.
    get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
    get_viewport().scaling_3d_scale = 1.0


func _create_sun() -> void:
    var sun := DirectionalLight3D.new()
    sun.name = "GoldenHourSun"
    sun.rotation_degrees = Vector3(-38.0, -43.0, 0.0)
    sun.light_color = Color(1.0, 0.78, 0.58)
    sun.light_energy = 1.35
    sun.shadow_enabled = true
    add_child(sun)


func _create_terrain() -> void:
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var colors := PackedColorArray()
    var uvs := PackedVector2Array()
    var indices := PackedInt32Array()

    var stride: int = GRID_SEGMENTS + 1
    var step: float = WORLD_EXTENT * 2.0 / float(GRID_SEGMENTS)
    for z in range(stride):
        for x in range(stride):
            var px: float = -WORLD_EXTENT + float(x) * step
            var pz: float = -WORLD_EXTENT + float(z) * step
            var y: float = height_at(px, pz)
            var normal: Vector3 = _normal_at(px, pz)
            vertices.push_back(Vector3(px, y, pz))
            normals.push_back(normal)
            uvs.push_back(Vector2(float(x), float(z)) * 0.08)
            var slope: float = clampf(1.0 - normal.y, 0.0, 1.0)
            var variation: float = 0.5 + 0.5 * sin(px * 0.12 + pz * 0.09)
            var soil := Color(0.21, 0.20, 0.13)
            var moss := Color(0.16, 0.27, 0.13)
            colors.push_back(moss.lerp(soil, clampf(slope * 2.8 + variation * 0.12, 0.0, 1.0)))

    for z in range(GRID_SEGMENTS):
        for x in range(GRID_SEGMENTS):
            var i: int = z * stride + x
            # Counterclockwise winding from above (+Y); normal agrees with height derivative.
            indices.push_back(i)
            indices.push_back(i + stride)
            indices.push_back(i + 1)
            indices.push_back(i + 1)
            indices.push_back(i + stride)
            indices.push_back(i + stride + 1)

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_COLOR] = colors
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices

    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var material := StandardMaterial3D.new()
    material.vertex_color_use_as_albedo = true
    material.roughness = 0.97
    mesh.surface_set_material(0, material)

    var terrain := MeshInstance3D.new()
    terrain.name = "Terrain_Heightfield"
    terrain.mesh = mesh
    terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(terrain)


func _create_forest() -> void:
    var trunk := CylinderMesh.new()
    trunk.top_radius = 0.25
    trunk.bottom_radius = 0.40
    trunk.height = 3.8
    trunk.radial_segments = 7
    var bark := StandardMaterial3D.new()
    bark.albedo_color = Color(0.22, 0.12, 0.078)
    bark.roughness = 0.96
    trunk.material = bark

    var canopy := SphereMesh.new()
    canopy.radius = 1.0
    canopy.height = 2.0
    canopy.radial_segments = 11
    canopy.rings = 6
    var foliage_material := ShaderMaterial.new()
    foliage_material.shader = preload("res://shaders/foliage_wind.gdshader")
    canopy.material = foliage_material

    # Per-chunk MultiMesh resources enable frustum culling of entire distant clusters.
    # A single monolithic forest MultiMesh would be culled only as one oversized object.
    for cz in range(-2, 2):
        for cx in range(-2, 2):
            var trunks: Array[Transform3D] = []
            var crowns: Array[Transform3D] = []
            var custom: Array[Color] = []
            for j in range(54):
                var px: float = float(cx) * CHUNK_EDGE + rng.randf_range(1.0, CHUNK_EDGE - 1.0)
                var pz: float = float(cz) * CHUNK_EDGE + rng.randf_range(1.0, CHUNK_EDGE - 1.0)
                if Vector2(px, pz - 9.0).length() < 8.0:
                    continue
                var scale: float = rng.randf_range(0.70, 1.5)
                var base: float = height_at(px, pz)
                var yaw: float = rng.randf_range(-PI, PI)
                var orientation := Basis(Vector3.UP, yaw)
                trunks.append(Transform3D(orientation.scaled(Vector3(scale * 0.75, scale, scale * 0.75)),
                    Vector3(px, base + scale * 1.90, pz)))
                crowns.append(Transform3D(orientation.scaled(Vector3(scale * 2.0, scale * 1.75, scale * 2.0)),
                    Vector3(px, base + scale * 4.15, pz)))
                custom.append(Color(rng.randf(), rng.randf(), rng.randf(), 1.0))
            _spawn_instances("Trunks_%s_%s" % [cx, cz], trunk, trunks, custom, true)
            _spawn_instances("Canopies_%s_%s" % [cx, cz], canopy, crowns, custom, true)


func _create_grass() -> void:
    var blade := QuadMesh.new()
    blade.size = Vector2(0.34, 0.75)
    var grass_material := ShaderMaterial.new()
    grass_material.shader = preload("res://shaders/grass_wind.gdshader")
    blade.material = grass_material

    for cz in range(-2, 2):
        for cx in range(-2, 2):
            var transforms: Array[Transform3D] = []
            var colors: Array[Color] = []
            for j in range(225):
                var px: float = float(cx) * CHUNK_EDGE + rng.randf_range(0.0, CHUNK_EDGE)
                var pz: float = float(cz) * CHUNK_EDGE + rng.randf_range(0.0, CHUNK_EDGE)
                var s: float = rng.randf_range(0.6, 1.6)
                var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
                transforms.append(Transform3D(basis.scaled(Vector3(s, s, s)),
                    Vector3(px, height_at(px, pz) + s * 0.36, pz)))
                colors.append(Color(rng.randf(), rng.randf(), 0.0, 1.0))
            var instance := _spawn_instances("Grass_%s_%s" % [cx, cz], blade, transforms, colors, false)
            grass_chunks.append(instance)


func _create_rocks() -> void:
    var rock := SphereMesh.new()
    rock.radius = 1.0
    rock.height = 2.0
    rock.radial_segments = 8
    rock.rings = 4
    var stone := StandardMaterial3D.new()
    stone.albedo_color = Color(0.28, 0.31, 0.29)
    stone.roughness = 0.92
    rock.material = stone

    for cz in range(-2, 2):
        for cx in range(-2, 2):
            var transforms: Array[Transform3D] = []
            var colors: Array[Color] = []
            for j in range(9):
                var px: float = float(cx) * CHUNK_EDGE + rng.randf_range(0.0, CHUNK_EDGE)
                var pz: float = float(cz) * CHUNK_EDGE + rng.randf_range(0.0, CHUNK_EDGE)
                var s: float = rng.randf_range(0.45, 1.6)
                var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
                transforms.append(Transform3D(basis.scaled(Vector3(s * 1.4, s * 0.45, s)),
                    Vector3(px, height_at(px, pz) + s * 0.15, pz)))
                colors.append(Color(1.0, 1.0, 1.0, 1.0))
            _spawn_instances("Stones_%s_%s" % [cx, cz], rock, transforms, colors, true)


func _spawn_instances(label: String, mesh: Mesh,
        transforms: Array[Transform3D], custom: Array[Color],
        cast_shadows: bool) -> MultiMeshInstance3D:
    var multi := MultiMesh.new()
    multi.transform_format = MultiMesh.TRANSFORM_3D
    multi.use_custom_data = true  # Must be set before instance_count.
    multi.mesh = mesh
    multi.instance_count = transforms.size()
    for i in range(transforms.size()):
        multi.set_instance_transform(i, transforms[i])
        multi.set_instance_custom_data(i, custom[i])

    var node := MultiMeshInstance3D.new()
    node.name = label
    node.multimesh = multi
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    # Fine grass has a shorter visibility range and a soft camera-distance fade.
    # Tree and rock clusters remain visible much farther away.
    if label.begins_with("Grass_"):
        node.visibility_range_end = 64.0
        node.visibility_range_end_margin = 11.0
        node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
    else:
        node.visibility_range_end = 145.0
    add_child(node)
    return node


func _create_crystals() -> void:
    var gem := SphereMesh.new()
    gem.radius = 0.55
    gem.height = 1.1
    gem.radial_segments = 8
    gem.rings = 4
    var gem_material := StandardMaterial3D.new()
    gem_material.albedo_color = Color(0.18, 0.55, 0.95)
    gem_material.metallic = 0.12
    gem_material.roughness = 0.18
    gem_material.emission_enabled = true
    gem_material.emission = Color(0.16, 0.48, 1.0)
    gem_material.emission_energy_multiplier = 3.8
    gem.material = gem_material

    var positions: Array[Vector2] = [
        Vector2(9, -2), Vector2(24, -18), Vector2(-17, -21),
        Vector2(-32, 14), Vector2(11, 33), Vector2(-8, 45),
        Vector2(43, 22), Vector2(35, -41)
    ]
    for i in range(positions.size()):
        var p: Vector2 = positions[i]
        var holder := Node3D.new()
        holder.name = "Crystal_%02d" % i
        holder.position = Vector3(p.x, height_at(p.x, p.y) + 1.2, p.y)
        var jewel := MeshInstance3D.new()
        jewel.mesh = gem
        jewel.scale = Vector3(0.75, 1.5, 0.75)
        holder.add_child(jewel)
        add_child(holder)
        crystals.append(holder)


func _create_camera() -> void:
    camera = Camera3D.new()
    camera.name = "Explorer"
    camera.fov = 72.0
    camera.far = 210.0
    camera.current = true
    camera.position = Vector3(0.0, height_at(0.0, 9.0) + 2.1, 9.0)
    camera.rotation_degrees.x = -9.0
    add_child(camera)


func _create_hud() -> void:
    var canvas := CanvasLayer.new()
    canvas.name = "GameHUD"
    add_child(canvas)
    hud = Label.new()
    hud.position = Vector2(22, 20)
    hud.add_theme_font_size_override("font_size", 19)
    hud.add_theme_color_override("font_color", Color(0.92, 0.96, 0.90))
    hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.82))
    hud.add_theme_constant_override("shadow_offset_x", 2)
    hud.add_theme_constant_override("shadow_offset_y", 2)
    canvas.add_child(hud)
    hint = Label.new()
    hint.position = Vector2(22, 145)
    hint.add_theme_font_size_override("font_size", 15)
    hint.add_theme_color_override("font_color", Color(0.76, 0.85, 0.77))
    hint.text = "WASD / стрелки: движение  •  мышь: обзор (щелчок)  •  E: сбор\nF1: кинематографично  •  F2: производительность  •  Esc: курсор"
    canvas.add_child(hint)


func _apply_quality(high: bool) -> void:
    high_quality = high
    world_environment.ssao_enabled = high
    world_environment.ssil_enabled = high
    world_environment.volumetric_fog_enabled = high
    for chunk in grass_chunks:
        chunk.multimesh.visible_instance_count = -1 if high else int(chunk.multimesh.instance_count * 0.50)
    var controller := get_node_or_null("AdaptiveResolution3D")
    if controller:
        controller.set("min_scale", 0.70 if high else 0.62)
        controller.set("target_fps", 60)
    _refresh_hud()


func _refresh_hud() -> void:
    if hud == null:
        return
    var quality: String = "CINEMATIC" if high_quality else "PERFORMANCE"
    var scale: float = get_viewport().scaling_3d_scale
    var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
    var gpu_text: String = "%.2f ms" % gpu_ms if gpu_ms > 0.0 else "N/A"
    hud.text = "AURORA FOREST  |  Cgame / Godot 4.8\n" \
        + "Реликвии: %d / %d    Профиль: %s\n" % [collected, CRYSTAL_TOTAL, quality] \
        + "3D scale: %.2f    FPS: %d    GPU: %s" % [scale, Engine.get_frames_per_second(), gpu_text]
    if collected >= CRYSTAL_TOTAL:
        hint.text = "Все реликвии найдены! Лес снова сияет. Нажми F1/F2, чтобы сравнить рендеринг."


func _process(delta: float) -> void:
    elapsed += delta
    hud_elapsed += delta
    if hud_elapsed >= 0.25:
        hud_elapsed = 0.0
        _refresh_hud()

    for i in range(crystals.size()):
        var crystal: Node3D = crystals[i]
        crystal.rotation.y += delta * 0.7
        crystal.position.y = height_at(crystal.position.x, crystal.position.z) \
            + 1.2 + sin(elapsed * 1.7 + float(i)) * 0.23

    if camera == null:
        return
    var direction := Vector3.ZERO
    if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
        direction -= camera.global_basis.z
    if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
        direction += camera.global_basis.z
    if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
        direction += camera.global_basis.x
    if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
        direction -= camera.global_basis.x
    direction.y = 0.0
    if direction.length_squared() > 0.0001:
        var speed: float = 8.5 if Input.is_physical_key_pressed(KEY_SHIFT) else 5.2
        camera.position += direction.normalized() * speed * delta
    camera.position.x = clampf(camera.position.x, -WORLD_EXTENT + 2.0, WORLD_EXTENT - 2.0)
    camera.position.z = clampf(camera.position.z, -WORLD_EXTENT + 2.0, WORLD_EXTENT - 2.0)
    camera.position.y = lerpf(camera.position.y,
        height_at(camera.position.x, camera.position.z) + 2.1, minf(1.0, 8.0 * delta))


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        get_viewport().set_input_as_handled()
    elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        camera.rotation.y -= event.relative.x * mouse_sensitivity
        camera.rotation.x = clampf(camera.rotation.x - event.relative.y * mouse_sensitivity, -1.42, 1.42)
        get_viewport().set_input_as_handled()
    elif event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_ESCAPE:
                Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
            KEY_F1:
                _apply_quality(true)
            KEY_F2:
                _apply_quality(false)
            KEY_E:
                _collect_nearest()


func _collect_nearest() -> void:
    if camera == null:
        return
    var nearest: Node3D = null
    var distance: float = 3.2
    for candidate in crystals:
        var dist: float = Vector2(camera.position.x - candidate.position.x,
            camera.position.z - candidate.position.z).length()
        if dist < distance:
            distance = dist
            nearest = candidate
    if nearest:
        crystals.erase(nearest)
        nearest.queue_free()
        collected += 1
        _refresh_hud()
