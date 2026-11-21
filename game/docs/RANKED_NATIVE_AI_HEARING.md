# Ranked AI hearing for Albion After

Cgame's optional native `AIHearingSensor2D` now supports
`report_noise_ranked(listener, source, loudness, occlusion=1.0)`.
This is a new **opt-in** API: ordinary `report_noise` still stores the latest
accepted event, preserving existing scripts.

## Why

Unreal Engine's AI Perception system exposes stimulus strength and maximum
age, allowing AI to reason about competing observations:
https://dev.epicgames.com/documentation/en-us/unreal-engine/ai-perception-in-unreal-engine

Cgame uses a deliberately simpler, deterministic normalized signal strength:

```text
strength = max(0, 1 - distance / (hearing_radius * loudness * occlusion))
```

A weaker audible event returns true but cannot overwrite a stronger
unexpired location. Equal strength is resolved by smaller source X, then Y;
the same winner can refresh its memory without changing order. The
memory expiry timer is unchanged and reset after expiration.

## Actual game integration

`game/scripts/shared/native_infected_senses.gd` detects the optional method
once and uses it for `record_confirmed_sound`. This adapter receives **only
already accepted** signals from the server-owned infected perception path:
safe-zone immunity, wind-adjusted radius, geometry-cover attenuation,
alive/dead checks, and existing aggro decisions remain authoritative.
The sensor never originates a target ID, RPC, hit, or sighting.

A noisy player encountered last in a dictionary no longer automatically
overrides the clearer accepted source when the infected later investigates
its recent sound memory. In stock Godot and older Cgame, the bridge
falls back to the prior `report_noise` API.

Debug snapshots now expose `ranked_hearing` and `sound_strength` for
server-side diagnostics, not routine client replication.

## Tests and limitations

- Native C++ tests: strength comparisons, ties independent of event order,
  expiry and no-refresh for weaker events, invalid coordinate rejection,
  and legacy compatibility.
- `game/tests/test_native_infected_senses.gd`: native/fallback behavior,
  server-authoritative acquisition, deterministic order and memory expiry.
- `game/tests/run_all.gd` already includes the game suite.

This is not acoustic ray tracing, a music/audio engine, or an AI target
selection replacement. It does not reduce processing cost of the existing
server-side sound broadphase.

Native compilation and headless test execution are required before merge:

```sh
scons platform=linuxbsd target=editor dev_build=yes tests=yes module_behavior_tree_enabled=yes
bin/godot.linuxbsd.editor.dev.x86_64 --headless --test --test-case="*[AIHearingSensor2D]*"
bin/godot.linuxbsd.editor.dev.x86_64 --headless --path game --script res://tests/run_all.gd
```
