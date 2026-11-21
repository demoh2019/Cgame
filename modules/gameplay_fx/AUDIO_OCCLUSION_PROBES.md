# Bounded spatial-audio obstruction probes

Inspired by Unreal's sound attenuation and occlusion systems, this feature
makes audio obstruction ray admission fair under crowded spatial sound mixes.
Previously Albion After checked at most three rays per physics frame but
selected the earliest inserted sources before the later sounds.

## Engine API

AudioOcclusionProbePlanner.select_due(next_due_seconds, priorities,
audibilities, ids, now_seconds, budget) returns due voice **indices**.
It never touches scene nodes, physics, AudioServer, clocks, or network state.

- Maximum 128 voices, 16 probes; rejects invalid arrays atomically.
- Priority 0..3 provides up to 450 ms effective age advantage.
- Increasing overdue time eventually outranks even high-priority newcomers.
- Stable IDs make exact ties independent of voice insertion/removal order.
- O(N * budget) selection without full sorting or mutable engine state.

## Albion After

The live client uses this planner for a maximum of three scheduled
geometry/terrain sound-occlusion raycasts per physics tick. Low-priority
ambient sounds cannot monopolize checks while combat is active; lower
priority sounds cannot starve indefinitely either. The chosen source
still uses the same terrain obstruction, world physics ray, obstruction
attack/release curve, 0.25 second recheck, and per-voice mixer settings.
Unselected sources still smooth their audio every physics frame.

The GDScript fallback has equivalent validation and ranking on stock
Godot, and old binaries without the engine class use that fallback.

AI hearing, collision, physics state, gameplay authority, save files,
and server-side networking are unchanged.

## Validation

The dedicated audio-occlusion-probe-budget workflow runs source contracts,
compiles the custom native editor with tests, runs C++ doctests and a
headless real-game import, the focused audio suite, and full game suite.

This is a bounded admission algorithm; no measured speedup claim is made
without profiling actual game content on the target platforms.

Unreal reference: Sound Attenuation / Occlusion documentation.
