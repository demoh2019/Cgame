extends SceneTree
## Run: godot --headless --path games/days_after --script res://pcg_density_smoke_test.gd
## Pure helper tests run with native Cgame and stock Godot.

const Density = preload("res://pcg_density_policy.gd")


func _initialize() -> void:
    var errors: Array[String] = []
    _test_policy(errors)
    for message in errors:
        printerr("FAIL " + message)
    print("PCG DENSITY TOTAL: %d failures" % errors.size())
    quit(1 if not errors.is_empty() else 0)


func _check(ok: bool, message: String, errors: Array[String]) -> void:
    if not ok:
        errors.append(message)


func _selected_ids(indices: PackedInt32Array,
        ids: PackedInt64Array) -> Array[int]:
    var result: Array[int] = []
    for index in indices:
        result.append(int(ids[index]))
    result.sort()
    return result


func _test_policy(errors: Array[String]) -> void:
    var src := PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
    var remapped: PackedFloat32Array = Density.remap_densities(src,
        0.0, 1.0, 0.2, 0.8, true, false)
    _check(remapped.size() == 5, "remap lost input points", errors)
    if remapped.size() == 5:
        for i in 5:
            _check(absf(remapped[i] - (0.2 + 0.15 * float(i))) < 0.00001,
                "remap interpolated wrong at %d" % i, errors)
    _check(Density.remap_densities(src, 0.0, 1.0, 1.0, 0.0, true, false)[0] == 1.0,
        "reversed output range must be supported", errors)
    _check(Density.remap_densities(src, 0.25, 0.75, 0.4, 0.6, true, false)[0] >
        Density.remap_densities(src, 0.25, 0.75, 0.4, 0.6, false, false)[0],
        "clamp_input must change out-of-range values", errors)
    _check(Density.remap_densities(PackedFloat32Array([0.8, NAN]),
        0.0, 1.0, 0.2, 0.8, true, false).is_empty(),
        "invalid tail must atomically reject remap", errors)
    _check(Density.remap_densities(src, 0.7, 0.7, 0.2, 0.8, true, false).is_empty(),
        "zero-width input range is invalid", errors)
    _check(Density.remap_densities(src, 0.0, 1.0, -0.1, 1.0, true, false).is_empty(),
        "out-of-bounds output range invalid", errors)

    var densities := PackedFloat32Array()
    var ids := PackedInt64Array()
    for i in 128:
        densities.append(float((i * 37) % 101) / 100.0)
        ids.append(i * 13 + 7)
    var native_remap: PackedFloat32Array = Density.remap_densities(
        densities, 0.0, 1.0, 0.35, 0.92)
    var script_remap: PackedFloat32Array = Density.remap_densities(
        densities, 0.0, 1.0, 0.35, 0.92, true, false)
    _check(native_remap.size() == 128 and script_remap.size() == 128,
        "native and GDScript remap size mismatch", errors)
    if native_remap.size() == 128 and script_remap.size() == 128:
        for i in 128:
            _check(absf(native_remap[i] - script_remap[i]) < 0.000001,
                "native/fallback remap mismatch at %d" % i, errors)

    var native_selected: PackedInt32Array = Density.select_indices(
        script_remap, ids, 27419, 4096)
    var script_selected: PackedInt32Array = Density.select_indices(
        script_remap, ids, 27419, 4096, false)
    _check(native_selected == script_selected,
        "native/fallback seeded density selection diverged", errors)
    _check(script_selected == Density.select_indices(script_remap, ids,
        27419, 4096, false), "density selection is nondeterministic", errors)

    var reverse_densities := PackedFloat32Array()
    var reverse_ids := PackedInt64Array()
    for i in range(127, -1, -1):
        reverse_densities.append(script_remap[i])
        reverse_ids.append(ids[i])
    var reversed_indices: PackedInt32Array = Density.select_indices(
        reverse_densities, reverse_ids, 27419, 4096, false)
    _check(_selected_ids(script_selected, ids) ==
        _selected_ids(reversed_indices, reverse_ids),
        "reordering candidate points rerolled their stable density decisions", errors)

    _check(Density.select_indices(PackedFloat32Array([0.0, 1.0, 1.0]),
        PackedInt64Array([1, 2, 3]), 0, 2, false) == PackedInt32Array([1, 2]),
        "probability 0/1 and cap semantics broken", errors)
    _check(Density.select_indices(PackedFloat32Array([1.0, NAN]),
        PackedInt64Array([1, 2]), 0, 4096, false).is_empty(),
        "invalid trailing density must not produce partial output", errors)
    _check(Density.select_indices(PackedFloat32Array([1.0, 0.8]),
        PackedInt64Array([1, -5]), 0, 4096, false).is_empty(),
        "invalid stable point IDs must fail closed", errors)
    _check(Density.select_indices(PackedFloat32Array([1.0]),
        PackedInt64Array([1]), 0, 0, false).is_empty(),
        "zero selection budget must fail closed", errors)
    _check(Density.select_indices(PackedFloat32Array([1.0]),
        PackedInt64Array([1]), 0, 4097, false).is_empty(),
        "excessive selection budget must fail closed", errors)
