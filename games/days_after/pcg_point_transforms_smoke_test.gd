extends SceneTree
## Native/fallback PCG Transform Points parity, stable ID independence and limits.
## godot --headless --path games/days_after --script res://pcg_point_transforms_smoke_test.gd

const Points = preload("res://pcg_point_transforms.gd")


func _check(ok: bool, message: String, failures: Array[String]) -> void:
    if not ok:
        failures.append(message)


func _same_transforms(a: Array, b: Array, tolerance: float = 0.00005) -> bool:
    if a.size() != b.size():
        return false
    for i in a.size():
        var first: Transform3D = a[i]
        var second: Transform3D = b[i]
        if first.origin != second.origin or \
                first.basis.x.distance_to(second.basis.x) > tolerance or \
                first.basis.y.distance_to(second.basis.y) > tolerance or \
                first.basis.z.distance_to(second.basis.z) > tolerance:
            return false
    return true


func _initialize() -> void:
    var failures: Array[String] = []
    var ids := PackedInt64Array()
    var positions := PackedVector3Array()
    for i in 512:
        ids.append((i * 137) % 512)
        positions.append(Vector3(float(i % 23), 0.22, float(i / 23)))
    var native: Array = Points.generate_transforms(
        positions, ids, 42019, TAU, 0.82, 1.18, 0.88, 1.16)
    var fallback: Array = Points.generate_transforms(
        positions, ids, 42019, TAU, 0.82, 1.18, 0.88, 1.16, false)
    _check(native.size() == 512 and _same_transforms(native, fallback),
        "native/fallback point transform mismatch", failures)
    _check(_same_transforms(native, Points.generate_transforms(
        positions, ids, 42019, TAU, 0.82, 1.18, 0.88, 1.16)),
        "stable ID transform regeneration was not deterministic", failures)

    var yaw_variation := false
    var varied_heights := false
    for i in native.size():
        var transform: Transform3D = native[i]
        var scale: Vector3 = transform.basis.get_scale()
        _check(transform.origin == positions[i],
            "point transform moved an authored position", failures)
        _check(scale.x >= 0.82 - 0.00001 and scale.x <= 1.18 + 0.00001,
            "point horizontal scale out of bounds", failures)
        _check(scale.y >= 0.88 - 0.00001 and scale.y <= 1.16 + 0.00001,
            "point vertical scale out of bounds", failures)
        _check(absf(scale.x - scale.z) < 0.00002,
            "horizontal scale lost uniform X/Z scaling", failures)
        if absf(transform.basis.x.z) > 0.1:
            yaw_variation = true
        if absf(scale.y - 1.0) > 0.05:
            varied_heights = true
    _check(yaw_variation and varied_heights,
        "point transform variation did not change yaw and height", failures)

    var reordered_ids := PackedInt64Array()
    var reordered_pos := PackedVector3Array()
    for i in range(511, -1, -1):
        reordered_ids.append(ids[i])
        reordered_pos.append(positions[i] + Vector3(100, 0, 0))
    var reordered: Array = Points.generate_transforms(
        reordered_pos, reordered_ids, 42019, TAU, 0.82, 1.18, 0.88, 1.16)
    if reordered.size() != 512 or native.size() != 512:
        failures.append("reordered point transforms missing")
    else:
        for i in 512:
            var x: Transform3D = reordered[i]
            var y: Transform3D = native[511 - i]
            if not x.basis.is_equal_approx(y.basis) or x.origin != reordered_pos[i]:
                failures.append("stable ID point appearance changed with source ordering")
                break

    var forced: Array = Points.generate_transforms(
        positions, ids, 42019, 0.0, 1.0, 1.0, 1.0, 1.0)
    _check(forced.size() == 512, "fixed transformation options failed", failures)
    for transform in forced:
        if not (transform as Transform3D).basis.is_equal_approx(Basis()):
            failures.append("fixed rotation/scale options were not identity")
            break

    _check(Points.generate_transforms(
        PackedVector3Array(), PackedInt64Array()).is_empty(),
        "valid empty point array failed", failures)
    _check(Points.generate_transforms(
        PackedVector3Array([Vector3(), Vector3()]),
        PackedInt64Array([0])).is_empty(),
        "mismatched array lengths were not rejected", failures)
    _check(Points.generate_transforms(
        PackedVector3Array([Vector3(), Vector3()]),
        PackedInt64Array([1, -1])).is_empty(),
        "invalid late stable ID was not rejected atomically", failures)
    _check(Points.generate_transforms(
        PackedVector3Array([Vector3(), Vector3()]),
        PackedInt64Array([1, 2147483648])).is_empty(),
        "out-of-range stable ID was not rejected", failures)
    _check(Points.generate_transforms(
        PackedVector3Array([Vector3(), Vector3(NAN, 0, 0)]),
        PackedInt64Array([1, 2])).is_empty(),
        "nonfinite late point was not rejected", failures)
    _check(Points.generate_transforms(
        PackedVector3Array([Vector3()]), PackedInt64Array([1]),
        -1).is_empty(),
        "negative seed was accepted", failures)
    _check(Points.generate_transforms(
        PackedVector3Array([Vector3()]), PackedInt64Array([1]),
        0, NAN).is_empty(),
        "invalid yaw was accepted", failures)
    _check(Points.generate_transforms(
        PackedVector3Array([Vector3()]), PackedInt64Array([1]),
        0, TAU, 1.2, 0.8).is_empty(),
        "inverted scales were accepted", failures)
    var oversized := PackedVector3Array()
    var oversized_ids := PackedInt64Array()
    oversized.resize(16385)
    oversized_ids.resize(16385)
    _check(Points.generate_transforms(oversized, oversized_ids).is_empty(),
        "maximum point batch limit was not enforced", failures)

    for failure in failures:
        printerr("FAIL " + failure)
    print("PCG POINT TRANSFORMS TOTAL: %d failures" % failures.size())
    quit(1 if not failures.is_empty() else 0)
