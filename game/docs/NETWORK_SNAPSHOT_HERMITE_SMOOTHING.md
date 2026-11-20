# Monotonic network snapshot Hermite smoothing — Albion After and Godot fork

## Problem and references

Albion After's networked world receives server actor snapshots at approximately
10 Hz. The client already buffers snapshots for 120 ms, avoids extrapolating
past the newest server state, and resets buffers on teleports. However, the
previous linear blend jumps in visual velocity at every 100 ms boundary.

Unreal Engine's Character Movement Component smooths simulated proxies
independently from authoritative movement. Unity Netcode NetworkTransform
buffers and interpolates snapshots. Gaffer on Games documents cubic Hermite
interpolation as a way to reduce visible discontinuities at low snapshot
rates. This update applies that mathematical idea to our existing system;
it does **not** replace network authority, prediction or the jitter buffer.

- Unreal Engine: https://dev.epicgames.com/documentation/en-us/unreal-engine/understanding-networked-movement-in-the-character-movement-component-for-unreal-engine
- Unity Netcode: https://mp-docs.dl.it.unity3d.com/netcode/current/components/networktransform/
- Snapshot interpolation: https://gafferongames.com/post/snapshot_interpolation/

## Engine

The fork adds the optional native
`Node3D.interpolate_network_snapshot(from, to, from_velocity, to_velocity,
snapshot_delta, fraction) -> Vector3`.

The method computes a cubic Hermite position between two snapshots with
their endpoint velocity tangents. Each axis is treated as a **monotonic
segment**: its Hermite slope is clamped to [0, 3] times the corresponding
coordinate displacement, and the result is bounded by both endpoints.
This prevents extrapolation past a wall, stairs or rapidly reversing
actor even if a neighboring snapshot estimates a bad velocity.

- Exact endpoints at fractions 0 and 1
- Two snapshots with their ordinary secant velocity produce exactly
  the original linear interpolated position
- Corrupt timestamps, invalid velocities and network gaps above 0.5 s
  fall back to linear blending, not an unbounded spline
- Gaps longer than 8 m bypass curved interpolation; existing game
  teleport handling resets history and snaps immediately
- The helper reads no physics or tree state; it does not alter its Node3D
  host transform and cannot claim server-side authority
- No allocations, pathfinding, geometry rebuilds, extra game network
  packets or per-entity scenes are introduced

## Game integration

`EntityView._sample()` uses the new
`NetworkSnapshotSmoothing.sample_position()` for **other players and
zombies**, preserving the existing buffered timestamps, shortest-path
yaw rotation and no-future-extrapolation logic.

The helper estimates endpoint derivatives from snapshots before and
after the active pair (when available). If the history contains just
two positions, it uses identical segment velocity tangents and returns
the original straight line. Velocity estimates never cross a detected
teleport discontinuity. The client supplies each existing Node3D as
the native helper receiver — no additional scene node is created.

**Stock Godot compatibility:** if the native method does not exist,
the same monotone cubic coefficients and safeguards run in the game's
GDScript helper. This allows testing the scene on standard builds,
while the compiled fork evaluates the hot geometry calculation in C++.

The local player's authoritative camera/control path, server physics,
collisions, damage, NPC AI and bandwidth remain unchanged.
The result is strictly *visual motion smoothing*.

## Quality and runtime verification

Game: `godot --headless --path game --script res://tests/run_all.gd`.
`test_network_snapshot_smoothing.gd` compares two-snapshot linear
parity, corner bounds, turnaround velocities, corrupted inputs, delayed
packets, the native vs GDScript implementations and integration with
EntityView. Test on a built Godot fork and on stock Godot.

Engine: `[SceneTree][Node3D] Network snapshots use bounded Hermite interpolation`
covers native endpoint preservation, rounded corners, invalid values,
large corrections and unchanged transform state.

Visual QA: use 10 snapshots/sec with simulated packet jitter and loss.
Record other players weaving around props, runners changing direction,
zombies chasing the player around doors, stairs, respawn and teleport,
then measure visible position jitter at 60/120 Hz display rates.
Inspect a correct NPC path after 1–3 missing packets. Native vs fallback
trajectories should match to about 0.0002 world units in deterministic tests.

The engine binary was not available during authoring. Written tests and
source inspections are **not** a substitute for running the Godot
compiler, actual network simulation and visual capture.
