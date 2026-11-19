# Jolt soft-body Area3D sensor overlap generation map

Jolt emits soft-body/sensor contacts from multiple worker threads. Cgame
buffers their subshape pairs and publishes enter/exit notifications only
after the physics step. Previously the persistent soft-body overlap set
counted every callback as a persisting pair. Duplicate callbacks for the
same pair could inflate that count, leading to a negative exit estimate.
On any exit the implementation also built a second full `HashSet`,
reinserted every current contact and replaced the previous set. This
allocates and hashes all overlaps on frames with partial sensor exits.

## New implementation

A persistent compact `AHashMap<SubShapeIDPair,uint32_t>` stores the *last
completed generation* in which each unique pair was observed.

- During each flush, advance a 32-bit generation; on wrap, invalidate all
  stamps before continuing (no false matches after 2^32 steps).
- For every callback, look up the pair. Mark previous pairs only once per
  generation. Insert new pairs and dispatch a single enter event.
- If all previously stored pairs were seen, **skip the expiration scan**.
- Otherwise iterate existing entries and remove only pairs not seen in this
  generation, dispatching exit events exactly once. The compact hash map
  moves its last slot into a removed slot, so the loop correctly inspects
  the same index again after an erase.
- Reuse map allocation under a steady workload. When the live set becomes
  less than one-quarter of a large allocated table, rebuild the remaining
  small map once; when empty, release oversized storage. Do not touch the
  separate, persistent rigid-body area overlap set.
- Worker callbacks remain thread-local; all merge and mutation happens
  under the existing post-step `instances_mutex` lock.

This follows the high-throughput physics-engine pattern of minimizing
expensive global rebuilds during persistent contacts, while keeping begin/end
events correct when sensors receive multiple contact reports.

## Tests

```sh
python3 -m unittest tests/stress/test_jolt_softbody_overlap_epochs.py \
  tests/stress/test_jolt_contact_scratch.py -v

./bin/godot.linuxbsd.editor.dev.x86_64 --headless --path tests/stress \
  --script res://physics_jolt_softbody_area_overlap_regression.gd
```

The native fixture builds a small indexed tetrahedron mesh and creates a
Jolt soft body. An `Area3D` sensor moves in and out of its volume six
times, checking that each cycle yields exactly one body-enter and one
body-exit event. The CI job selects the Jolt backend explicitly.

Python model tests independently check duplicated contacts, stable
contacts, 2000 randomized steps, the 32-bit epoch rollover, and entry
expiry. Static contracts check the actual algorithm and allocation policy.

For performance comparisons use the same sensor/softbody workload with
sustained overlap, periodic exits, and a large-to-small churn case.
Compare process RSS, time spent in the sensor event flush and total
physics tick CPU time before/after. No measured CPU or RAM gain is
claimed until native benchmarks finish.
