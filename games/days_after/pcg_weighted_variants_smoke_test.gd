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

    var authored := PackedInt32Array([2, 0, 1, 2, 0, 2, 1, 2])
    var native_groups: Array = Weighted.partition_indices(authored, 4)
    var fallback_groups: Array = Weighted.partition_indices(authored, 4, false)
    _check(native_groups == fallback_groups and native_groups.size() == 4,
        "native/fallback PCG mesh batches disagree", failures)
    if native_groups.size() == 4:
        _check(native_groups[0] == PackedInt32Array([1, 4]) and
            native_groups[1] == PackedInt32Array([2, 6]) and
            native_groups[2] == PackedInt32Array([0, 3, 5, 7]) and
            (native_groups[3] as PackedInt32Array).is_empty(),
            "PCG mesh buckets are not stable and ordered", failures)

    var chosen_groups: Array = Weighted.partition_indices(output, 3)
    var chosen_script_groups: Array = Weighted.partition_indices(output, 3, false)
    _check(chosen_groups.size() == 3 and chosen_groups == chosen_script_groups,
        "large 4096 point PCG mesh partition parity failed", failures)
    if chosen_groups.size() == 3:
        var visit_counts := PackedInt32Array()
        visit_counts.resize(output.size())
        for variant in 3:
            var indices: PackedInt32Array = chosen_groups[variant]
            for source_index in indices:
                _check(source_index >= 0 and source_index < output.size(),
                    "PCG mesh bucket index is out of bounds", failures)
                if source_index >= 0 and source_index < output.size():
                    visit_counts[source_index] += 1
                    _check(output[source_index] == variant,
                        "PCG mesh bucketing changed selected variant", failures)
        for visits in visit_counts:
            if visits != 1:
                failures.append("PCG mesh partition duplicated or dropped source points")
                break
    _check(Weighted.partition_indices(PackedInt32Array(), 3).size() == 3,
        "valid empty input must create all empty mesh buckets", failures)
    _check(Weighted.partition_indices(PackedInt32Array([0, 2]), 3).size() == 3,
        "missing middle variant is valid", failures)
    _check(Weighted.partition_indices(PackedInt32Array([0, 3]), 3).is_empty(),
        "invalid tail variant must atomically reject mesh batches", failures)
    _check(Weighted.partition_indices(PackedInt32Array([0, -1]), 3).is_empty(),
        "negative mesh variant must reject all input", failures)
    _check(Weighted.partition_indices(PackedInt32Array([0, 1]), 0).is_empty(),
        "zero mesh variant count must reject", failures)
    _check(Weighted.partition_indices(PackedInt32Array([0, 1]), 33).is_empty(),
        "too many mesh variants must reject", failures)
    var oversized := PackedInt32Array()
    oversized.resize(16385)
    _check(Weighted.partition_indices(oversized, 3).is_empty(),
        "mesh partition must enforce the native 16K limit", failures)

    for failure in failures:
        printerr("FAIL " + failure)
    print("PCG WEIGHTED VARIANTS TOTAL: %d failures" % failures.size())
    quit(1 if not failures.is_empty() else 0)
