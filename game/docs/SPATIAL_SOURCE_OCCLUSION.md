# Terrain, walls and per-source audio obstruction in Albion After

## Reference architecture

Unreal Engine Sound Attenuation separates distance, air absorption and
occlusion: a direct-path obstruction lowers individual source volume and
darkens high frequencies without lowering an entire audio mix.
Unity's Audio Low Pass Filter provides an analogous spectral response.
Albion After already had a terrain-height occlusion check and atmospheric
audio, while our Godot fork now exposes `AudioStreamPlayer3D.obstruction_amount`.

References:
- https://dev.epicgames.com/documentation/unreal-engine/sound-attenuation-in-unreal-engine
- https://docs.unity.com/en-us/engine/7000.0/manual/audio/reference/filters/class-audio-low-pass-filter
- https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer3d.html

## Gameplay integration

The game reuses its existing obstacle-occlusion physics scheduler:
at most three physics raycasts per tick, with a 0.25 s recheck of each
long-running sound. Raycasts ignore Area3D triggers, while the existing
heightfield check also detects intervening hills and rocky ridges. The
terrain test is now refreshed inside this same bounded ray budget as the
listener moves, preventing a stale 'blocked forever' sound when the player
walks around a mountain.

Each source's occlusion smoothly approaches the new target with a bounded
rate, preventing abrupt level jumps at doorway thresholds.

**On the custom Godot engine** the client sets
`AudioStreamPlayer3D.obstruction_amount`. The engine applies a -8 dB
direct-path multiplier for full obstruction, a logarithmic spectral
cutoff toward 1.4 kHz, and reduces high-shelf energy even for nearby
sources. The native mixer uses a **separate -15 dB high-frequency shelf**
at full obstruction, not the -8 dB full-band factor a second time.
The initial playback buffer receives both the *same* spectral cutoff
and the shelf factor as later physics/audio updates: no brief unfiltered
transient when a terrain-blocked shot starts playing.

**On stock Godot** the client applies the matching attenuation and
cutoff directly to that one `AudioStreamPlayer3D`. The original source
cutoff is always the *unobstructed* air-absorption baseline so native
or fallback occlusion is applied once, not twice.

The shared -8 dB policy also reduces a blocked source's audibility
score in the voice limiter, allowing clearer nearby combat sounds to
win priority. The existing distance voice budget and sound concurrency
manager remain responsible for avoiding source storms.

No per-source effect bus, extra audio stream, audio thread physics query,
sound buffer allocation, or additional raycast is introduced. Only the
small existing obstruction state and rate-limited scene queries are used.
The feature works with music ducking, reverb and user-adjustable mix
volumes without muting the whole SFX bus.

## Testing

Game: `godot --headless --path game --script res://tests/run_all.gd`
(see `test_audio_geometry_occlusion.gd`). The tests cover obstruction
curves, wall/terrain scheduler bounds, live player property/fallback
selection, shared gain and preservation of unoccluded cutoff.

Native: the standalone test
`tests/scene/test_audio_occlusion_policy.cpp` builds with an ordinary
C++17 compiler and tests the curve independently of Godot. Source
integration checks confirm the new startup cutoff and high-frequency
attenuation are applied inside the native mixer.

In a hardware session, shoot from both sides of a barricade, walk behind
and around a ridge during long audio loops, cross a doorway, and compare
clear vs. blocked enemy attacks. Confirm that the first 10–20 ms of a
blocked shot does not suddenly start loud/bright, and that environmental
reverb and UI/music do not change. Stress-test 20 simultaneous sources:
wall checks must remain capped at three per physics tick. Profile p50/p95
main-thread and audio mix times before/after.

The Godot binary is not available in the authoring environment, so audio
playback and engine runtime still require a local build and listening test.
