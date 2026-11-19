# GodotPhysics 2D/3D: bounded reclamation of idle island scratch memory

## Problem

Cgame's GodotPhysics2D and GodotPhysics3D reconstruct the **live** constraint
and rigid-body islands every physics step, reusing the outer
`LocalVector<LocalVector<...>>` storage across frames. Reuse is important for
throughput: a steady simulation must not malloc/free hundreds of tiny
island lists every tick.

However, previously no path reduced these vectors after a one-off burst of
thousands or millions of small islands. Even after the world was unloaded
or bodies had fallen asleep, every retained inner LocalVector could keep
its heap allocation. The outer LocalVector also kept peak capacity.

Jolt's architecture constructs its island data per physics step, avoiding
long-lived island ownership. This patch adopts *bounded idle reclamation*
without giving up Cgame's reuse of hot scratch buffers.

## New reclamation policy

At the end of each `GodotStep2D::step()` and `GodotStep3D::step()`, **after**
constraint solving, sleeping decisions, soft-body updates, and worker
barriers:

1. Keep the first 128 island slots, and retain a 2x cushion above the
   number of live islands when reclaiming.
2. Never start reclaiming if at most 512 slots are retained, or if the
   current live count is at least one-quarter of the retained count.
3. Wait **16 consecutive quiet physics steps**. A busy step resets the
   countdown, preventing repeated free/realloc when activity oscillates.
4. Remove at most **1024 surplus island slots per physics step**, running
   their normal `LocalVector` destructors. This frees their *inner* buffers
   progressively instead of causing one massive synchronous unload.
5. Reduce the *outer* LocalVector capacity only once it is significantly
   oversized (more than twice the current size), or when reaching the
   retention target. This avoids a `realloc` on every step.

Body and constraint island counters are independent, because scenes can
have very different live body and constraint island counts.

Example: after 4096 cached islands drop to 8 live islands, the count
stays at 4096 for 15 quiet steps, then becomes 3072, 2048, 1024, 128 over
the following four steps. Previously the nested buffers would remain
allocated until the physics-step object itself was destroyed.

This is **not** a change to physics simulation results, pair matching,
sleep states, solver iterations, or the color cache. It changes how much
idle scratch memory stays allocated. Memory retained by *active* unusually
large island vectors is outside this change's scope.

## Validation

```sh
# Verify integration into 2D/3D and source policies.
python3 -m unittest discover -s tests/stress -p test_physics_island_storage.py -v

# Requires tests=yes Cgame editor:
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Island scratch memory is reclaimed incrementally after quiet frames"

./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Island scratch reclamation cancels when activity returns"
```

C++ tests exercise all retention thresholds with real nested LocalVectors,
verify the freed elements run their destructors, ensure the first surviving
islands remain valid and the original buffers can grow again. They also
test alternating bursts and small scenes with no reclaim.

For performance evidence, compare the old and new commits on the same
machine using a load/unload/reload cycle of a scene with many **separate**
contact/joint islands. Measure process RSS (not just Godot allocation
counters), the number of active islands, peak frame duration and p95/p99
physics-step cost during the reclaim period. In stable dense worlds the
helper should stay on its O(1) no-op path; a RAM reduction is expected
only in the burst-then-quiet workload, and has not yet been measured.

Reference: Jolt Physics architecture
https://github.com/jrouwe/JoltPhysics/blob/master/Docs/Architecture.md
