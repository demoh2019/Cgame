# Jolt pending-body index: compact allocation and reuse

Cgame batches Jolt body insertion with `AddBodiesPrepare` / `AddBodiesFinalize`.
Before first insertion, a body may be removed, destroyed, or transferred
between sleeping and awake pending queues. Repeated linear searches through
thousands of pending IDs would become quadratic. The fork already creates
a hash lookup index lazily at 128 pending bodies.

This change replaces the node-based `HashMap<uint32_t, uint32_t>` in each
queue with a compact open-addressed `AHashMap<uint32_t, uint32_t>`. Its
contiguous storage improves locality and reduces per-entry allocations.
Since AHashMap grows near 75% load, the code reserves enough *slots* for
an incoming index before building it to avoid a second reallocation.

After flush or full deletion the index is **cleared** and reused when its
capacity is at most 4096 slots. A larger transient index is **reset** to
release memory. Small pending batches still use the original linear scan
and do not materialize a hash map.

The swap-and-erase algorithm preserves Jolt's full index-and-sequence-number
key (not just the body slot index), so it will not confuse an old BodyID
with a recycled slot. Both awake and sleeping queues use the same helper.
The lifetime of physical bodies, collision resolution and the Jolt batch
insertion calls remain unchanged. This does **not** defer destruction or
perform an unsafe delayed `RemoveBodies` operation.

## Reproduce

```sh
python3 -m unittest tests/stress/test_jolt_pending_index_cache.py \
  tests/stress/test_jolt_pending_buffer_reuse.py -v

./bin/godot.linuxbsd.editor.dev.x86_64 --headless --path tests/stress \
  --script res://physics_jolt_pending_index_churn.gd
```

The native scenario creates and removes 512 rigid bodies in each of
24 waves, before any physics tick (12,288 total removals), toggles
sleeping/awake flags, and deletes bodies in a coprime permutation.
Finally it adds 64 new bodies, runs a physics step and requires that
active bodies be reported. CI explicitly selects the Jolt backend.

Record time spent in pending-body create/destroy and peak process RSS
before/after the change on the same host/compiler. Source-level tests
and allocator design do not establish a measured speedup; native CI
compilation and regression tests must pass independently.
