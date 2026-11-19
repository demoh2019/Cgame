# Jolt: bounded contact-reporting scratch

Jolt reports contacts on physics worker threads and stores temporary manifolds
and area events until the end of a physics step. This fork keeps those buffers
for reuse, but a huge one-time contact burst could previously retain its peak
capacity indefinitely (especially in long-running editor sessions and when
streaming between dense and sparse scenes).

The contact listener now uses a high-water policy on **temporary** data:

- `manifolds` (per worker): keep at least 2,048 entries of capacity, release
  larger capacity only when it exceeds four times the current frame's usage.
- `deepest_manifolds` (physics thread's temporary hash): keep at least 4,096
  slots and use the same four-times-current-usage rule.
- `area_enters`, `area_exits`, and `area_soft_body_overlaps` (per worker):
  keep at least 2,048 event slots and trim capacity only after a large drop.

This retains the allocation for **sustained** dense-contact simulations while
releasing large buffers after the workload shrinks. Event count forecasting
also uses signed arithmetic: duplicate area exits no longer wrap the reserve
size to a giant unsigned value and trigger an unnecessary allocation. No contact/event may be
discarded before it is dispatched, and the **persistent** area-overlap sets
must remain intact to produce correct enter/exit events.

The policy follows the bounded-scratch approach of high-throughput physics
backends: avoid per-frame allocation when active while not permanently paying
for extreme peak load. This changes only scratch allocation lifetime, not
physics solver behavior or collision filtering.

## Execute

Use the project backend **Jolt Physics** (default in Cgame) and run:

```sh
python3 -m unittest tests/stress/test_jolt_contact_scratch.py -v

./bin/godot.linuxbsd.editor.dev.x86_64 --headless --path tests/stress \
  --script res://physics_jolt_contact_scratch_regression.gd
```

The runtime case creates **4,096 overlapping 3D rigid bodies** with contact
reporting enabled, advances four dense physics frames, deletes all but 64,
and advances four quieter frames. It checks for collision pairs and finite
transform values. The result marker includes dense/quiet engine-reported
memory and physics timing. Memory samples are observational, **not** a
proof that OS RSS or the allocator decreases: compare process RSS on the same
host and configuration, and use the native CI build.

The GitHub workflow runs the same script after native Jolt compilation.
Performance and correctness remain unverified until that CI job completes.
