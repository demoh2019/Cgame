# Jolt: skip redundant broadphase optimization for pending-only deletes

When a Godot rigid or soft body enters a Jolt space, it is initially queued
in one of the pending sleeping/awake lists. Jolt's
`BodyInterface::CreateBody` and `CreateSoftBody` allocate a body, but it is
**not inserted into broadphase** until `AddBodiesPrepare/Finalize` runs
(on the next step or forced pending flush).

Previously `JoltSpace3D::remove_object()` would call
`PhysicsSystem::OptimizeBroadPhase()` whenever the **whole physics server**
was inactive and the space was down to its default area, even when a body
was created and destroyed before it was ever inserted. An editor tool
repeatedly creating and cancelling a single provisional body in an inactive
space could therefore trigger a full broadphase rebuild on each deletion.

The implementation now records whether the removed `BodyID` belonged to
either pending list:

- **Pending body:** erase it from the list and destroy it immediately.
  Skip `RemoveBody` and `OptimizeBroadPhase`; it never entered the
  broadphase in the first place.
- **Already-inserted body:** call `RemoveBody`, destroy it immediately, and
  preserve the old final-body cleanup path: `OptimizeBroadPhase` if the
  server is inactive and at most the default area remains.

This does not defer destruction, affect contact solver behavior, change
`PhysicsSystem::Update`, or alter awake/sleeping queue indices. It
avoids potentially redundant tree rebuilds in editor scene churn and
cancelled streaming/spawn operations.

Upstream Jolt's documentation warns that `OptimizeBroadPhase` is
not intended to run every frame; it is mainly a heavy one-time
rebuild for previously suboptimal insertion patterns. Cgame already
uses batched `AddBodiesPrepare/Finalize`.

## Reproduce

```sh
python3 -m unittest tests/stress/test_jolt_pending_broadphase_rebuild.py -v

./bin/godot.linuxbsd.editor.dev.x86_64 --headless --path tests/stress \
  --script res://physics_jolt_pending_broadphase_regression.gd
```

The native script explicitly runs with the **Jolt Physics** backend in CI.
It temporarily disables the physics server, creates and destroys 2048
individual provisional rigid bodies plus 4 waves of 256 bodies, then
re-enables simulation and verifies that 48 real inserted bodies can step
and be removed while paused. It prints elapsed time, memory samples
and a final pass/fail marker.

For performance claims compare `single_churn_ms` before and after on the
same machine with the same compiler flags, Jolt backend, and load.
The source-level checks do not establish native compilation or measured
speedups; those require completed CI and benchmark results.
