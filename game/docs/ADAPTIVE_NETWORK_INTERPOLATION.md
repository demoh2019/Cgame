# Adaptive network snapshot buffering — Albion After and Cgame

Inspired by Unreal simulated-proxy movement smoothing and Unity Netcode's
buffered snapshot interpolation, adapted for the existing Cgame Godot fork.
These are original, interoperable implementations, not copied engine code.

## Previous behavior

Albion After's visual entities used a fixed 120ms interpolation delay at a
nominal 10Hz server snapshot rate. Uneven packet arrival could exhaust the
interpolation history, momentarily freezing a remote survivor or infected.
The previous clock's per-frame error correction could also move the render
timeline backwards when newer buffering targets were behind the clock.

## New behavior

- One `NetworkJitterBuffer` instance runs per `EntityView`, not per actor.
- `EntityView.update_from` runs every render frame, but the policy observes
  only **new server timestamps** and local **monotonic arrival times**.
- Nominal presentation delay remains 120ms. Late arrivals and lost
  snapshots raise it, up to 350ms; clean intervals reduce it gradually.
- A native `Node3D.advance_network_render_time` implements a bounded
  non-negative playback rate and never advances beyond the last actual
  server timestamp. A matching GDScript fallback supports stock Godot.
- Out-of-order snapshots are ignored for rendering. Large backwards time
  changes on reconnect flush visual history to avoid interpolating between
  two server epochs. Existing teleport handling remains intact.
- Visual-only scheduling: game positions, damage, AI, collision and PvP
  validation remain fully server-authoritative.

## Testing

```sh
godot --headless --path game --script res://tests/run_all.gd
godot --headless --path game --script res://tests/run_graphics.gd
# Cgame native test binary: select
# [SceneTree][Node3D] Network render clock handles jitter without speculative movement
```

`game/tests/test_network_jitter_buffer.gd` covers fixed cadence, jitter,
packet gaps, duplicate updates, invalid floats, reconnection, monotone
playback and native/GDScript parity. The game tests deliberately do not
require a real multiplayer server or a GPU.

## Performance and fairness

The estimator is O(1) per *new snapshot* with no per-entity buffers or GPU
work. The frame clock is O(1) once per rendered frame. This adds latency
only when network jitter makes a stable reconstruction harder. Gameplay,
hit detection and rewards never use the delayed presentation clock.

Latency and perceived smoothness must be evaluated with actual packet
loss/jitter simulation and hardware captures. The tests verify deterministic
behavior, **not** measured improvements in multiplayer FPS or latency.
