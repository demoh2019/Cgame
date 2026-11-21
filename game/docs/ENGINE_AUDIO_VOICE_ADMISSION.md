# Native spatial audio voice admission

Cgame provides `AudioVoiceAdmissionPlanner : RefCounted`, inspired by
Unreal Engine Sound Concurrency's **Stop Lowest Priority** and **Stop
Quietest** rules. It is a deterministic admission planner, not an audio
mixer or full virtualized streaming playback system.

`select_victim(voices: Array, name: String, new_db: float,
new_priority: int, max_voices: int = 24,
same_sound_max: int = 5) -> int` returns -2 (ROOM), -1
(DROP_NEW) or the victim index. Per-sound limits are considered before
the global pool. Selection favors lower priorities first, then quieter
voices with oldest-age ties inside a 0.5 dB deadband. A lower-priority
request never evicts a higher-priority existing voice. For equal-priority
voices, a new effect must not be over 3 dB quieter.

The engine validates ranges, record shapes, names, audibility, age
and priorities before any result that could evict a sound.

## Live Albion After

The real `Audio.play_at()` now makes this decision **before** allocating
`AudioStreamPlayer3D`. Rejected requests never create scene nodes,
avoiding allocation churn during packed zombie fights. Existing
`SoundConcurrencyManager`, position/reverb, terrain obstruction and
audio buses continue working unchanged.

Audio priority by name: zombie kill = 3; weapon fire, repeater and
enemy harm = 2; object breaks and coins = 1; others = 0. This is
presentation-only: server hits, network messages, combat and inventory
are never gated by the planner.

`AudioVoices.prioritized_victim()` provides the matching stock Godot
fallback. The old `AudioVoices.victim()` API remains unchanged,
including old behavior when all priorities are zero.

## Regression coverage

- C++ doctest covers priority protection, same sound cap, audible
  thresholds, oldest ties, malformed input and default 24 voices.
- Game regression runs randomized stock/native parity scenarios and
  checks the actual `Audio.play_at` allocation order.
- Dedicated native build and Albion After game tests are run by
  `.github/workflows/native-audio-voice-admission.yml`.

This feature reduces **unnecessary sound-player allocations** but does
not claim a measured FPS gain without a native benchmark.

Reference: https://dev.epicgames.com/documentation/en-us/unreal-engine/sound-concurrency-reference-guide
