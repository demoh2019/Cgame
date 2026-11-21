extends SceneTree
## Run: godot --headless --path games/days_after --script res://pcg_weighted_variants_smoke_test.gd
## Bounded native/GDScript stable-ID PCG weighted variant parity.

const Weighted = preload("res://pcg_weighted_variants.gd")


func _check(condition: bool, message: String, failures: Array[String]) -> void:
    if not condition:
        failures.append(message)


func _initialize() -> void:
    var failures: Array[String] = []
    var ids := PackedInt64Array()
    for index in range(4096):
        ids.append(index)
    var weights := PackedFloat32Array([6.0, 3.0, 1.0])
    var reference: PackedInt32Array = Weighted.choose_variants(ids, weights, 2711, false)
    var output: PackedInt32Array = Weighted.choose_variants(ids, weights, 2711)
    _check(output == reference and output.size() == 4096,
        "native/fallback weighted selection mismatch", failures)
    var counts := PackedInt32Array([0, 0, 0])
    for index in output:
        if index < 0 or index >= counts.size():
            failures.append("selector returned out-of-bounds variant index")
        else:
            counts[index] += 1
    _check(counts[0] > 2100 and counts[0] < 2850 and
        counts[1] > 850 and counts[1] < 1650 and
        counts[2] > 200 and counts[2] < 700,
        "selection did not approximate 60/30/10 weights", failures)
    _check(Weighted.choose_variants(ids, weights, 2711) == output,
        "seeded native selection is not deterministic", failures)

    var permuted_ids := PackedInt64Array()
    for index in range(4095, -1, -1):
        permuted_ids.append(ids[index])
    var permuted := Weighted.choose_variants(permuted_ids, weights, 2711)
    _check(permuted.size() == 4096, "reorder changed output count", failures)
    if permuted.size() == 4096:
        for index in 4096:
            if permuted[index] != output[4095 - index]:
                failures.append("variant assignment changed on reordering")
                break

    var all_green := Weighted.choose_variants(ids,
        PackedFloat32Array([7.0, 0.0, 0.0]), 1)
    _check(all_green.size() == 4096, "positive variant lost IDs", failures)
    for index in all_green:
        if index != 0:
            failures.append("zero-weight variant was selected")
            break
    var all_dry := Weighted.choose_variants(ids,
        PackedFloat32Array([0.0, 0.0, 1.0]), 1)
    for index in all_dry:
        if index != 2:
            failures.append("sole-positive weighted variant not selected")
            break

    _check(Weighted.choose_variants(PackedInt64Array([1, -1]), weights).is_empty(),
        "bad tail stable ID should reject entire request", failures)
    _check(Weighted.choose_variants(PackedInt64Array([1, 2147483648]), weights).is_empty(),
        "out-of-range stable ID should reject", failures)
    _check(Weighted.choose_variants(PackedInt64Array([1, 2]),
        PackedFloat32Array([1.0, NAN])).is_empty(),
        "nonfinite weights must fail closed", failures)
    _check(Weighted.choose_variants(PackedInt64Array([1, 2]),
        PackedFloat32Array([1.0, -1.0])).is_empty(),
        "negative weights must fail closed", failures)
    _check(Weighted.choose_variants(PackedInt64Array([1, 2]),
        PackedFloat32Array([0.0, 0.0])).is_empty(),
        "zero weight sum should reject", failures)
    _check(Weighted.choose_variants(PackedInt64Array([1, 2]), weights, -1).is_empty(),
        "negative random seed should reject", failures)
    _check(Weighted.choose_variants(PackedInt64Array(), weights).is_empty(),
        "valid empty input should yield empty output", failures)

    for failure in failures:
        printerr("FAIL " + failure)
    print("PCG WEIGHTED VARIANTS TOTAL: %d failures" % failures.size())
    quit(1 if not failures.is_empty() else 0)
