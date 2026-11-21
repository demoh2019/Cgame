# Weighted non-repeating audio variation

## Engine

Unreal Engine's **Sound Cue Random Node** offers *Randomize Without
Replacement*: every sound branch plays before the next cycle can repeat.
Our existing `WeightedChoiceTable` sampled with replacement only.

New native `sample_excluding(unit, excluded_indices)` computes a weighted
choice among non-excluded entries in O(options + exclusions) time (maximum
4096 options). It rejects invalid indices and finite/out-of-range draws,
never selects zero weights, allows duplicate exclusions and returns -1
when the remaining distribution is empty. The Resource is not mutated and
does not consume RNG state. Old `sample_unit` remains unchanged.

## Albion After

`audio_variants.gd` owns one history per sound bank and automatically
starts a fresh cycle when all positive-weight clips have been used.
`audio.gd` now plays each of three flesh and four bone samples once before
repeating either set. Native engines use the new sampler; official Godot
and older Cgame binaries use a GDScript parity fallback. One cosmetic
random draw is used per clip. Pitch, volume, positioning, reverb and
voice lifetime are unchanged.

This is only client-side audio presentation, not combat authority,
loot, persistent data, or networking. No unmeasured FPS gains are claimed.

## Verification

C++ native doctests cover boundaries, duplicate exclusions, zero
weights, exhaustion, invalid draws and resource immutability.
`test_audio_parity.gd` checks native/fallback equivalence across weighted
cycles, uniqueness, reset behavior and invalid input. CI compiles the
engine, tests native behavior and imports/runs the game audio and full suites.

Reference: https://dev.epicgames.com/documentation/en-us/unreal-engine/sound-cue-reference-for-unreal-engine
