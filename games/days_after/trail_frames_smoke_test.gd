extends SceneTree
## Run: godot --headless --path games/days_after --script res://trail_frames_smoke_test.gd
## The native sampler and stock-Godot implementation must agree in
## both point positions AND orthonormal, tangent-aligned transforms.

const TRAIL_SCRIPT = preload("res://trail_markers.gd")
const FOLIAGE_SCRIPT = preload("res://foliage_scatter.gd")


func _initialize() -> void:
    call_deferred("_smoke")


func _frames_agree(a: Array, b: Array) -> bool:
    if a.size() != b.size():
        return false
    for i in range(a.size()):
        var first: Transform3D = a[i]
        var second: Transform3D = b[i]
        if (first.origin.distance_to(second.origin) > 0.001
                or first.basis.x.distance_to(second.basis.x) > 0.002
                or first.basis.y.distance_to(second.basis.y) > 0.002
                or first.basis.z.distance_to(second.basis.z) > 0.002):
            return false
    return true


func _smoke() -> void:
    var failures: int = 0
    var foliage = FOLIAGE_SCRIPT.new()
    var trail = TRAIL_SCRIPT.new()
    trail.configure(foliage.get_trail_points(),
        foliage.get_exclusion_box_mins(), foliage.get_exclusion_box_maxs())
    root.add_child(trail)
    await process_frame

    var raw_positions: PackedVector3Array = trail.get_raw_samples()
    var frames: Array = trail.get_raw_frames()
    var fallback: Array = trail._sample_frames_fallback()
    if frames.size() != raw_positions.size() or frames.size() < 30 or frames.size() > 192:
        push_error("PCG TRAIL FRAME: invalid frame count or unaligned sample arrays")
        failures += 1
    if not _frames_agree(frames, fallback) or not trail.verify_native_fallback_parity():
        push_error("PCG TRAIL FRAME: native orientation differs from stock-Godot fallback")
        failures += 1

    var has_curved_tangent: bool = false
    for i in range(frames.size()):
        var frame: Transform3D = frames[i]
        if frame.origin.distance_to(raw_positions[i]) > 0.001:
            push_error("PCG TRAIL FRAME: native transform origin does not match sampled position")
            failures += 1
            break
        if (not frame.basis.x.is_finite() or not frame.basis.y.is_finite()
                or not frame.basis.z.is_finite()
                or absf(frame.basis.determinant() - 1.0) > 0.002
                or absf(frame.basis.z.length() - 1.0) > 0.002):
            push_error("PCG TRAIL FRAME: basis is not finite and orthonormal")
            failures += 1
            break
        var previous: int = maxi(0, i - 1)
        var next: int = mini(frames.size() - 1, i + 1)
        var secant: Vector3 = raw_positions[next] - raw_positions[previous]
        if secant.length_squared() > 1.0e-8:
            if frame.basis.z.dot(secant.normalized()) < 0.995:
                push_error("PCG TRAIL FRAME: frame does not face the path tangent")
                failures += 1
                break
        if absf(frame.basis.z.x) > 0.1 and absf(frame.basis.z.z) > 0.1:
            has_curved_tangent = true
    if not has_curved_tangent:
        push_error("PCG TRAIL FRAME: curved section lacks aligned tangent frames")
        failures += 1

    var visible: PackedVector3Array = trail.get_selected_positions()
    if not trail.verify_anchor_bounds_parity():
        push_error("PCG TRAIL FRAME: native cluster anchor AABB differs from GDScript")
        failures += 1
    var point_bounds: AABB = trail.get_anchor_bounds()
    if visible.size() > 0:
        var source_union := AABB(visible[0], Vector3.ZERO)
        for stone in visible:
            source_union = source_union.expand(stone)
            if (stone.x < point_bounds.position.x - 0.0001
                    or stone.y < point_bounds.position.y - 0.0001
                    or stone.z < point_bounds.position.z - 0.0001
                    or stone.x > point_bounds.end.x + 0.0001
                    or stone.y > point_bounds.end.y + 0.0001
                    or stone.z > point_bounds.end.z + 0.0001):
                push_error("PCG TRAIL FRAME: native anchor bounds lost a source stone")
                failures += 1
                break
        if point_bounds.position.distance_to(source_union.position) > 0.0001 or (
                point_bounds.size.distance_to(source_union.size) > 0.0001):
            push_error("PCG TRAIL FRAME: source AABB was not tightly bounded")
            failures += 1
        if trail.custom_aabb.position.distance_to(point_bounds.grow(0.75).position) > 0.0001 or (
                trail.custom_aabb.size.distance_to(point_bounds.grow(0.75).size) > 0.0001):
            push_error("PCG TRAIL FRAME: draw AABB is not padded around native anchors")
            failures += 1

    if trail.multimesh == null or trail.multimesh.instance_count != visible.size():
        push_error("PCG TRAIL FRAME: one MultiMesh instance was not created per visible marker")
        failures += 1
    else:
        for i in range(visible.size()):
            var instance: Transform3D = trail.multimesh.get_instance_transform(i)
            if instance.origin.distance_to(visible[i] + Vector3.UP * 0.045) > 0.001:
                push_error("PCG TRAIL FRAME: native sampled origins were not rendered")
                failures += 1
                break
            var matched: bool = false
            for frame_variant in frames:
                var frame: Transform3D = frame_variant
                if frame.origin.distance_to(visible[i]) < 0.001:
                    if instance.basis.z.distance_to(frame.basis.z) > 0.002:
                        push_error("PCG TRAIL FRAME: instanced stone discarded its tangent orientation")
                        failures += 1
                    matched = true
                    break
            if not matched:
                push_error("PCG TRAIL FRAME: visible stone has no source frame")
                failures += 1
                break

    var degenerate = TRAIL_SCRIPT.new()
    var no_boxes := PackedVector3Array()
    degenerate.configure(PackedVector3Array([
        Vector3(0, 0, 0), Vector3(0, 6, 0)
    ]), no_boxes, no_boxes)
    var upright: Array = degenerate._sample_frames()
    if not _frames_agree(upright, degenerate._sample_frames_fallback()) or upright.size() < 3:
        push_error("PCG TRAIL FRAME: vertical segment parity failed")
        failures += 1
    else:
        for variant_frame in upright:
            var frame: Transform3D = variant_frame
            if frame.basis.z.distance_to(Vector3.UP) > 0.002 or absf(frame.basis.determinant() - 1.0) > 0.002:
                push_error("PCG TRAIL FRAME: vertical segment basis flipped")
                failures += 1
                break
    degenerate.configure(PackedVector3Array([
        Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(0, 0, 0)
    ]), no_boxes, no_boxes)
    if not _frames_agree(degenerate._sample_frames(), degenerate._sample_frames_fallback()):
        push_error("PCG TRAIL FRAME: U-turn basis was not deterministic")
        failures += 1

    var snapshot: Array = trail.get_raw_frames()
    trail.regenerate()
    if not _frames_agree(snapshot, trail.get_raw_frames()):
        push_error("PCG TRAIL FRAME: regeneration changed the route transforms")
        failures += 1
    degenerate.free()
    foliage.free()
    trail.queue_free()
    await process_frame
    print("PCG TRAIL FRAMES: %d failures" % failures)
    quit(0 if failures == 0 else 1)
