extends SceneTree
## Focused PCG per-instance geometry LOD policy, native/fallback parity.
## Run: godot --headless --path games/days_after --script res://pcg_instance_lod_smoke_test.gd

const LODPlan = preload("res://pcg_instance_lod.gd")


func _check(condition: bool, message: String, failures: Array[String]) -> void:
    if not condition:
        failures.append(message)


func _initialize() -> void:
    var failures: Array[String] = []
    var positions := PackedVector3Array([
        Vector3(0, 0, 0), Vector3(24, 0, 0), Vector3(24.01, 0, 0),
        Vector3(27, 0, 0), Vector3(27.01, 0, 0), Vector3(-24, 0, 0)])
    var initial_expected := PackedInt32Array([0, 0, 1, 1, 1, 0])
    var first: PackedInt32Array = LODPlan.plan_instance_lods(positions, Vector3(),
        PackedInt32Array(), 24.0, 3.0, false)
    _check(first == initial_expected, "initial near/far tier boundaries", failures)
    _check(LODPlan.plan_instance_lods(positions, Vector3(),
        PackedInt32Array(), 24.0, 3.0) == first,
        "native/fallback initial tiers mismatch", failures)
    var near_previous := PackedInt32Array([0, 0, 0, 0, 0, 0])
    var far_previous := PackedInt32Array([1, 1, 1, 1, 1, 1])
    _check(LODPlan.plan_instance_lods(positions, Vector3(),
        near_previous, 24.0, 3.0, false) ==
        PackedInt32Array([0, 0, 0, 0, 1, 0]),
        "near history flickered within far boundary", failures)
    _check(LODPlan.plan_instance_lods(positions, Vector3(),
        far_previous, 24.0, 3.0, false) ==
        PackedInt32Array([0, 1, 1, 1, 1, 1]),
        "far history flickered within near boundary", failures)
    _check(LODPlan.plan_instance_lods(positions, Vector3(),
        near_previous, 24.0, 3.0) ==
        LODPlan.plan_instance_lods(positions, Vector3(),
            near_previous, 24.0, 3.0, false),
        "native/fallback near-history mismatch", failures)
    _check(LODPlan.plan_instance_lods(positions, Vector3(),
        far_previous, 24.0, 3.0) ==
        LODPlan.plan_instance_lods(positions, Vector3(),
            far_previous, 24.0, 3.0, false),
        "native/fallback far-history mismatch", failures)

    var variants := PackedInt32Array([0, 1, 0, 1, 2, 1])
    var tiers := PackedInt32Array([0, 1, 1, 0, 0, 1])
    var native_groups: Array = LODPlan.partition_variant_lods(variants, tiers, 3)
    var fallback_groups: Array = LODPlan.partition_variant_lods(variants, tiers, 3, false)
    _check(native_groups.size() == 6 and native_groups == fallback_groups,
        "native/fallback variant-tier buckets mismatch", failures)
    if native_groups.size() == 6:
        var expected := [
            PackedInt32Array([0]), PackedInt32Array([2]),
            PackedInt32Array([3]), PackedInt32Array([1, 5]),
            PackedInt32Array([4]), PackedInt32Array()]
        var visits := PackedInt32Array()
        visits.resize(variants.size())
        for group_index in 6:
            var indices: PackedInt32Array = native_groups[group_index]
            _check(indices == expected[group_index],
                "variant-tier bucket order at %d" % group_index, failures)
            for source_index in indices:
                if source_index < 0 or source_index >= variants.size():
                    failures.append("out-of-bounds source index in LOD group")
                else:
                    visits[source_index] += 1
                    _check(variants[source_index] == floori(float(group_index) / 2.0) and
                        tiers[source_index] == group_index % 2,
                        "wrong variant or tier for source", failures)
        for count in visits:
            if count != 1:
                failures.append("LOD groups dropped or duplicated original point")
                break

    _check(LODPlan.partition_variant_lods(PackedInt32Array(),
        PackedInt32Array(), 3).size() == 6,
        "empty source must yield six empty valid LOD groups", failures)
    _check(LODPlan.partition_variant_lods(
        PackedInt32Array([0, 1]), PackedInt32Array([0]), 2).is_empty(),
        "mismatched tier counts not rejected", failures)
    _check(LODPlan.partition_variant_lods(
        PackedInt32Array([0, 2]), PackedInt32Array([0, 1]), 2).is_empty(),
        "invalid trailing variant not rejected", failures)
    _check(LODPlan.partition_variant_lods(
        PackedInt32Array([0, 1]), PackedInt32Array([0, 2]), 2).is_empty(),
        "invalid LOD tier not rejected", failures)
    _check(LODPlan.plan_instance_lods(positions, Vector3(),
        PackedInt32Array([1]), 24.0, 3.0).is_empty(),
        "wrong historical tier count not rejected", failures)
    _check(LODPlan.plan_instance_lods(
        PackedVector3Array([Vector3(0, 0, 0), Vector3(NAN, 0, 0)]),
        Vector3(), PackedInt32Array(), 24.0, 3.0).is_empty(),
        "invalid tail position not rejected", failures)
    _check(LODPlan.plan_instance_lods(positions, Vector3(),
        PackedInt32Array(), 24.0, 24.0).is_empty(),
        "invalid hysteresis not rejected", failures)
    var too_many := PackedVector3Array()
    too_many.resize(16385)
    _check(LODPlan.plan_instance_lods(too_many, Vector3(), PackedInt32Array()).is_empty(),
        "native point cap not enforced", failures)

    for failure in failures:
        printerr("FAIL " + failure)
    print("PCG INSTANCE LOD TOTAL: %d failures" % failures.size())
    quit(1 if not failures.is_empty() else 0)
