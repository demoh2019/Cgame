# Geometry sound occlusion envelope — Cgame / Albion After

## Player-facing improvement

When a source passes behind a dungeon wall, mountain ridge or barricade,
its high frequencies and volume become muffled quickly. When the player
moves through a doorway and regains line of sight, the sound returns more
gently, avoiding abrupt changes.

This follows the *principle* of Unreal Engine's sound attenuation
occlusion interpolation and Wwise-style obstruction smoothing. Cgame
implements its own native per-source exponential envelope; no middleware
or new plugin is required.

## Existing geometry pipeline stays bounded

`Audio._physics_process` continues to trace at most three wall rays
per physics tick, and a given voice is rechecked every 0.25 seconds.
Existing heightfield checks also share this fixed budget. Raycasts never
run inside the real-time audio mixer. Game state, server combat,
physics collisions and network packets are unchanged.

When a new sound first starts behind terrain, `play_spatial` sets
obstruction before the first audio buffer, rather than starting open.

## Implemented

- Cgame `AudioStreamPlayer3D.advance_obstruction_amount(target, delta,
  attack_seconds=0.08, release_seconds=0.22)`:
  exponential, time-step independent approach for the native filter and
  gain path; source-local, clamped, finite-input validated, with an exact
  end state instead of an endless tiny signal update.
- Albion After `AudioSpatial.smooth_obstruction()` mirrors the same
  formula on stock Godot. The game selects the native method at runtime
  using `has_method` and `call`, so scripts still parse on regular
  Godot 4. High frequencies and volume are adjusted **once** by the
  native mixer; the stock fallback uses standard player properties.
- Source audibility and voice stealing priority track the smoothed
  value, consistent with earlier occlusion-aware concurrency logic.
- `tests/scene/test_audio_occlusion_smoothing.cpp` covers full attack/
  release, different timestep partitions, invalid samples, clamping
  and convergence. `game/tests/test_audio_occlusion_envelope.gd` checks
  the matching stock fallback and Cgame implementation, time-step
  independence, invalid inputs and the live audio pipeline.

The response is

```text
smoothed = current + (target - current) * (1 - exp(-delta / seconds))
seconds = attack_seconds if target > current else release_seconds
```

The units are response **time constants**, not times to reach
100% of target. After one time constant the value moves approximately
63% of the remaining distance, independent of the physics update rate.

## Verification

```sh
godot --headless --path game --script res://tests/run_audio.gd
godot --headless --path game --script res://tests/run_all.gd
# On a native Cgame editor built with tests=yes:
godot --headless --test --test-case="*Obstruction attack and release are time consistent*"
```

Native CI runs the C++ test and the short game audio suite. The portable
Godot fallback is included in the general game headless regression suite.

No claimed FPS improvement: this is primarily audible transition quality
and deterministic cross-platform behavior with no added raycast budget.

## Reference

- Unreal Engine sound attenuation / occlusion controls:
  https://dev.epicgames.com/documentation/en-us/unreal-engine/sound-attenuation-in-unreal-engine
- Unreal audio engine overview (inexpensive occlusion trace):
  https://dev.epicgames.com/documentation/en-us/unreal-engine/audio-engine-overview-in-unreal-engine
