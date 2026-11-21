# AudioMixSnapshotController — Cgame engine + Albion After

Inspired by Unreal Engine **Audio Modulation Control Bus Mixes** and Audio Volumes:
https://dev.epicgames.com/documentation/en-us/unreal-engine/audio-modulation-quick-start-guide
https://dev.epicgames.com/documentation/en-us/unreal-engine/audio-volumes-in-unreal-engine

## Native engine API

- `activate_mix(source, bus_offsets_db, fade_seconds=1.0)`: independent named profile with up to 8 named dB stages.
- `deactivate_mix(source, fade_seconds=1.0)`: reversible, non-popping fade-out.
- `tick(delta)`: frame-rate-independent linear fade weights.
- `get_bus_offset_db(bus)`: sum of contributions, clamped [-60, 0] dB, O(16×8) worst-case with no allocations. User volume and event ducking are **not** modified.
- `get_mix_count`, `has_mix`, `get_mix_weight`, `clear`.

Bounds: at most 16 concurrent profiles, 8 bus entries each, finite [-30,0] dB stages, fade time [0,15] seconds. Invalid changes are rejected before updating a profile. The API is data-only and does not call AudioServer or the audio render thread. The caller applies the mix to each AudioServer bus, combined with its own slider, filters and temporary audio ducking.

## Albion After

The real multiplayer sound node `game/scripts/client/audio.gd` runs this controller when Cgame supports it, otherwise uses `game/scripts/client/audio_mix_snapshots.gd` with the same semantics.

- `Zone.Underground` gently reduces music/ambience/SFX to convey interior acoustic separation.
- `Zone.Forest` slightly softens ambience/SFX.
- `Weather.Storm` layers over the zone at the same time, with a hysteresis band to prevent rapid reactivation near a storm threshold.
- `AudioDuckMix` event envelope remains independent; audio offsets are applied **after** persisted user sliders, so silence remains silence.
- AudioServer updates only when audible gain changes by at least 0.01dB. Server physics, AI, gameplay outcomes, game saves and network authority are untouched.

Native C++ doctests: `tests/test_audio_mix_snapshot_controller.h` included by the module register file. GDScript tests: `game/tests/test_audio_mix_snapshots.gd`.

## Timed Control Bus Mixes and automatic release

Unreal Engine Control Bus Mixes include attack/release stage times, a
duration option and re-triggering. Cgame now exposes
`AudioMixSnapshotController.activate_timed_mix(source, offsets, attack=0.2,
hold=3.0, release=1.0)`. A timed mix holds from its activation time (the
attack is included in the duration) and then automatically fades out; it
does not require a matching deactivation event.

- A repeated activation by name **refreshes the whole timer** but retains the
  existing mix's current weight. This avoids audible dips on rapid events.
- The engine applies attack/release time **piecewise** when a frame crosses the
  hold expiry, so a 1.0-second frame with 0.3 seconds left holds for 0.3
  and releases for 0.7, not for the full second.
- A manual `activate_mix` or `deactivate_mix` of the same source cancels the
  timer; unrelated profiles retain independent attack/release schedules.
- Both attack and release are finite [0, 15] seconds. Hold is finite
  [0, 120] seconds. Invalid inputs are rejected **before changing any mix**.
  Profile stage and capacity limits remain unchanged: at most 16 profiles,
  eight buses per profile and [-30, 0] dB per stage.
- `get_mix_remaining_seconds(source)` returns an active hold countdown
  or -1 for absent, untimed and already releasing mixes. The controller
  is still data-only; the game remains responsible for combining the
  resulting bus levels with user sliders, audio ducking and AudioServer.

**Albion After** applies `Combat.Focus` for 9 seconds after the most recent
combat cue, dimming **Ambience by -3 dB and Music by -1 dB** with a 0.15-second
attack and 1.5-second automatic release. Rapid blows extend the hold without
restarting the attack. The `SFX` bus, physics, damage, loot and authoritative
server state do not change. Existing storm and acoustic-zone snapshots
continue independently. Older Cgame builds, or stock Godot, use the matching
`audio_mix_snapshots.gd` time model; on old engines with the untimed native
controller, native zone mixes and scripted timed combat mix are **summed
together**, then bounded as before.

Implementation tests: `tests/test_audio_mix_snapshot_controller.h`,
`game/tests/test_audio_timed_mix.gd` and
`tests/scene/test_timed_audio_mix_contract.py`. GitHub workflow:
`.github/workflows/native-timed-audio-mixes.yml`.

Reference: https://dev.epicgames.com/documentation/en-us/unreal-engine/audio-modulation-reference-guide-in-unreal-engine

