extends SceneTree
# Offline procedural proxy scene baker. Designed to work with stock Godot:
# no native WorldPartition3D APIs are needed at bake time.
#
# godot --headless --path modules/world_partition/demo \
#   --script res://tools/bake_hlod_proxies.gd -- --radius=6 --stride=8
#
# Saves deterministic, serialized per-cell PackedScene proxies. Runtime loads
# them directly instead of generating each proxy's tree MultiMesh in _ready.

const SOURCE_SCENE := "res://scenes/cell_detail.tscn"
const OUTPUT_DIRECTORY := "res://generated"
const CELL_SIZE := 128.0
const DEFAULT_RADIUS := 6
const DEFAULT_STRIDE := 8
const MAX_RADIUS := 16
const MAX_STRIDE := 64
const Manifest = preload("res://tools/hlod_bake_manifest.gd")

func _initialize() -> void:
    call_deferred("_build_all")

func _parse_number_argument(name: String, fallback: int, minimum: int, maximum: int) -> int:
    for argument in OS.get_cmdline_user_args():
        var prefix := "--%s=" % name
        if argument.begins_with(prefix):
            var raw := argument.substr(prefix.length())
            if raw.is_valid_int():
                var value := raw.to_int()
                if value >= minimum and value <= maximum:
                    return value
            push_error("Invalid --%s: expected integer in %d..%d" % [name, minimum, maximum])
            return -1
    return fallback

func _build_all() -> void:
    var radius := _parse_number_argument("radius", DEFAULT_RADIUS, 0, MAX_RADIUS)
    var stride := _parse_number_argument("stride", DEFAULT_STRIDE, 1, MAX_STRIDE)
    if radius < 0 or stride < 0:
        quit(2)
        return

    var source_scene := load(SOURCE_SCENE) as PackedScene
    if source_scene == null:
        push_error("Cannot load detailed source scene: " + SOURCE_SCENE)
        quit(2)
        return

    var destination := ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
    if DirAccess.make_dir_recursive_absolute(destination) != OK:
        push_error("Cannot create proxy asset folder: " + destination)
        quit(2)
        return

    var fingerprint: String = Manifest.source_fingerprint(stride)
    if fingerprint.is_empty():
        push_error("Cannot hash HLOD inputs; check source and baker files.")
        quit(2)
        return

    var old_manifest: Dictionary = Manifest.read_valid_manifest(stride)
    var old_cells: Dictionary = old_manifest.get("cells", {})
    var new_cells: Dictionary = {}
    var baked := 0
    var skipped := 0
    var kept_instances := 0
    for x in range(-radius, radius + 1):
        for z in range(-radius, radius + 1):
            var cell := Vector2i(x, z)
            var cell_key: String = Manifest.cell_key(cell)
            var proxy_path: String = Manifest.proxy_path(cell)

            # Skip only when the content signature and exact saved bytes match.
            if old_cells.has(cell_key) and Manifest.is_cached_proxy_valid(cell, old_manifest):
                new_cells[cell_key] = old_cells[cell_key]
                skipped += 1
                continue

            var count := _bake_cell(source_scene, cell, stride)
            if count < 0:
                push_error("Proxy build failed for cell (%d, %d)" % [x, z])
                quit(2)
                return
            var digest := FileAccess.get_sha256(proxy_path)
            if digest.is_empty():
                push_error("Cannot hash baked proxy: " + proxy_path)
                quit(2)
                return
            new_cells[cell_key] = digest
            kept_instances += count
            baked += 1

    # Commit the manifest last: partial builds cannot advertise new or stale
    # cells as valid. Out-of-range generated files remain on disk but are not
    # referenced, so runtime safely falls back to procedural scenes.
    var manifest := {
        "schema": Manifest.SCHEMA_VERSION,
        "stride": stride,
        "fingerprint": fingerprint,
        "cells": new_cells,
    }
    var manifest_file := FileAccess.open(Manifest.MANIFEST_PATH, FileAccess.WRITE)
    if manifest_file == null:
        push_error("Cannot write HLOD manifest: " + Manifest.MANIFEST_PATH)
        quit(2)
        return
    manifest_file.store_string(JSON.stringify(manifest, "\t", true) + "\n")
    manifest_file.flush()
    manifest_file.close()

    print("HLOD proxy baking completed: Baked %d, skipped %d, newly kept instances %d, stride %d" % [baked, skipped, kept_instances, stride])
    quit(0)

func _bake_cell(source_scene: PackedScene, cell: Vector2i, stride: int) -> int:
    var source := source_scene.instantiate() as Node3D
    if source == null:
        return -1

    # Match the native streamer's final X/Z transform BEFORE _ready(). The
    # source cell script seeds its forest from that final position.
    source.position = Vector3(float(cell.x) * CELL_SIZE, 0.0, float(cell.y) * CELL_SIZE)
    get_root().add_child(source)

    var result := Node3D.new()
    result.name = "BakedForestProxy"
    var total := 0
    for child in source.get_children():
        if child is MultiMeshInstance3D:
            var original := child as MultiMeshInstance3D
            var proxy := MultiMeshInstance3D.new()
            proxy.name = original.name
            proxy.transform = original.transform
            var baked_mm := _subsample_multimesh(original.multimesh, original.name, cell, stride)
            if baked_mm == null:
                source.get_parent().remove_child(source)
                source.free()
                result.free()
                return -1
            total = maxi(total, baked_mm.instance_count)
            proxy.multimesh = baked_mm
            result.add_child(proxy)
            proxy.owner = result
        elif child is MeshInstance3D:
            var original_mesh := child as MeshInstance3D
            var copied := MeshInstance3D.new()
            copied.name = original_mesh.name
            copied.mesh = original_mesh.mesh
            copied.transform = original_mesh.transform
            copied.material_override = original_mesh.material_override
            result.add_child(copied)
            copied.owner = result

    source.get_parent().remove_child(source)
    source.free()

    var packed := PackedScene.new()
    if packed.pack(result) != OK:
        result.free()
        return -1

    var output_path: String = Manifest.proxy_path(cell)
    var save_result := ResourceSaver.save(packed, output_path)
    result.free()
    if save_result != OK:
        return -1
    return total

func _subsample_multimesh(source: MultiMesh, part_name: String, cell: Vector2i, stride: int) -> MultiMesh:
    if source == null or source.mesh == null:
        return null
    var output := MultiMesh.new()
    output.transform_format = source.transform_format
    output.use_colors = source.use_colors
    output.use_custom_data = source.use_custom_data
    output.mesh = _proxy_mesh(source.mesh, part_name)

    var count := source.visible_instance_count
    if count < 0:
        count = source.instance_count

    # Per-cell deterministic offset avoids identical thinning of adjacent cells.
    var offset := posmod(cell.x * 73856093 + cell.y * 19349663, stride)
    var kept := 0
    for index in range(offset, count, stride):
        kept += 1

    output.instance_count = kept
    var target := 0
    for index in range(offset, count, stride):
        if source.transform_format == MultiMesh.TRANSFORM_3D:
            output.set_instance_transform(target, source.get_instance_transform(index))
        else:
            output.set_instance_transform_2d(target, source.get_instance_transform_2d(index))
        if source.use_colors:
            output.set_instance_color(target, source.get_instance_color(index))
        if source.use_custom_data:
            output.set_instance_custom_data(target, source.get_instance_custom_data(index))
        target += 1
    return output

func _proxy_mesh(mesh: Mesh, part_name: String) -> Mesh:
    if part_name == "Canopies" and mesh is SphereMesh:
        var detailed := mesh as SphereMesh
        var simplified := SphereMesh.new()
        simplified.radius = detailed.radius
        simplified.height = detailed.height
        simplified.radial_segments = 6
        simplified.rings = 3
        simplified.material = detailed.material
        return simplified
    return mesh
