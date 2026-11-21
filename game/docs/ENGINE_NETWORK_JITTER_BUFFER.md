# Adaptive network jitter buffer — Cgame engine and Albion After

Cgame now offers the reusable engine `AdaptiveNetworkJitterBuffer : RefCounted`,
inspired by Unreal simulated-proxy network smoothing. It measures server
snapshot arrival jitter, gently increases its visual interpolation delay
under packet loss or irregular arrival, then reduces that delay slowly
on stable connections. This policy **does not predict positions**, schedule
network RPCs, authorize movement or replace the existing bounded Hermite
interpolation and teleport handling.

## Native API

- `observe(server_time, local_arrival_time) -> float`: one call per
  authoritative server timestamp; ignores repeated render frames, stale
  packets and invalid timestamps.
- `delay` and `get_delay()`: dynamically adjusted display latency.
  Default 0.12 s, capped at 0.35 s for the canonical 10 Hz game snapshots.
- `configure(base_delay, max_delay, expected_snapshot_step) -> bool`:
  reusable policy profiles for different game snapshot rates; finite,
  bounded settings, no unbounded player-visible latency.
- `reset()`: clears stale network epoch state.
- `get_stats()`: delay, peak jitter, accepted/ignored packet counts,
  epoch resets, lost/reconnect gaps, configured cadence and native flag.

`game/scripts/client/entity_view.gd` selects the native class automatically
on Cgame; ordinary Godot continues using the feature-compatible
`network_jitter_buffer.gd` fallback. Existing `_process` render-clock,
bounded Hermite smoothing and zero-extrapolation behavior remain identical.
`EntityView.network_jitter_stats()` surfaces local diagnostics for game
UI/profiling without any network protocol changes.

## Safety and coverage

Native tests in `tests/scene/test_adaptive_network_jitter_buffer.cpp`
cover stable and irregular packets, duplicate/out-of-order data, epochs,
invalid timestamps, configuration and telemetry. Extended
`game/tests/test_network_jitter_buffer.gd` compares both implementations
over 1,200 irregular arrivals and tests actual EntityView selection.
Dedicated CI compiles the Cgame editor and runs both the native and entire
Albion After suites. No CPU/FPS or latency improvement is claimed before
runtime measurements and green builds.

Unreal design reference:
https://dev.epicgames.com/documentation/unreal-engine/detailed-actor-replication-flow-in-unreal-engine

The actual `EntityView` initializes its buffer with
`Defs.SNAPSHOT_RATE` rather than hard-coding a 10Hz sampling interval,
so if the game's server tick profile changes, the visual jitter detector
still measures missing packets against the correct cadence.
