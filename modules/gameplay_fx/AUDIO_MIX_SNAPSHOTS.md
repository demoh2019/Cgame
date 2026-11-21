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
