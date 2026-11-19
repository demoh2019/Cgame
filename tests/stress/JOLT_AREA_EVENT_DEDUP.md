# Jolt Area3D: idempotent buffered events across worker threads

Jolt invokes contact callbacks from multiple physics worker threads. Cgame
collects rigid-body and sensor overlaps in per-thread buffers, then delivers
them to Godot `Area3D` after the physics step, preserving safe script
callback timing. Box2D 3.1 uses an analogous buffered begin/end sensor event
design; the critical requirement is that a shape pair transition be
reported once even when several worker callbacks observe the same pair.

## Issue

Before this change, `JoltContactListener3D::_flush_area_body_events()`
unconditionally dispatched every buffered exit and enter. Two workers could
enqueue the same transition, causing duplicate callbacks for a single
persistent `SubShapeIDPair`.

There was also a second issue inside `JoltArea3D::_add_shape_pair()`:
it enqueued a pending enter even when that exact pair was **already
present** in `Overlap::shape_pairs`. This inflated the secondary
shape-index refcount and could prevent a matching exit from being reported.

Both issues are correctness and overhead problems: callback duplication
may cause gameplay event handlers to execute several times, and stale
refcounts retain incorrect overlap state.

## Changes

- In the per-space event merge, dispatch an **exit only if**
  `area_overlaps.erase(pair)` successfully removed a tracked pair.
- Dispatch an **enter only if** that pair is not already present in
  `area_overlaps`; then insert it once.
- Preserve the original **all exits before all enters** ordering. When a
  Jolt subshape index is recycled for a new actual shape, its pair can
  legitimately emit one exit and one enter in the same step. The transition
  is not lost.
- `JoltArea3D::_add_shape_pair` now early-returns for an already mapped
  subshape pair rather than appending another `pending_added` entry.
  It still maps distinct Jolt subshapes to the same Godot shape indices
  and retains refcount aggregation for these genuinely distinct pairs.
- All buffering and deduplication happen **after** the Jolt simulation
  step under the existing listener synchronization. No extra atomics,
  spinlocks or allocations are introduced in the contact callback path.

## Tests

```sh
python3 -m unittest tests/stress/test_jolt_area_event_dedup.py -v

./bin/godot.linuxbsd.editor.dev.x86_64 --headless --path tests/stress \
  --script res://physics_jolt_area_event_dedup_regression.gd
```

The Python model exercises 10,000 seeded random enter/exit buffer batches,
duplicate enter and exit reports, forced exit+enter subshape replacements,
per-subshape refcount balance, and source contracts.

The native Jolt fixture attaches **eight overlapping subshapes** to one
Area3D, runs a single rigid body through that volume in **four waves** and
requires exactly one begin/end per subshape per wave. It checks 96 frames
in total, records wall time and performs full RID cleanup.

CI syntax-checks the fixture, selects Jolt explicitly by replacing the
existing project setting instead of appending a duplicate `[physics]`
section, runs the scene and archives its output.

The feature reduces redundant sensor event traffic and prevents incorrect
gameplay callbacks. Any simulation FPS, peak RSS or CPU improvement must be
measured with native before/after tests on identical scenes.

## Background

- [Box2D sensor and contact event buffering](https://box2d.org/documentation/group__events.html)
- [Box2D simulation step event collection](https://box2d.org/documentation/md_simulation.html)
- [Jolt ContactListener](https://jrouwe.github.io/JoltPhysicsDocs/5.7.0/class_contact_listener.html)
