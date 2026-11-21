# cgame_audio (experimental)

Native audio DSP for the Cgame engine fork. Optional built-in module; it adds the following classes at the scene initialization level.

| Class | Base | Purpose |
| --- | --- | --- |
| `AudioEffectConvolutionReverb` | `AudioEffect` | Real-time uniformly partitioned FFT convolution reverb with lock-free impulse-response swap |
| `CgameEarlyReflections` | `RefCounted` | Image-source early reflections for shoebox rooms and IR synthesis |
| `AudioStreamProcedural` | `AudioStream` | Plays a node-based audio graph evaluated block by block in the audio thread |
| `AudioStreamPlaybackProcedural` | `AudioStreamPlaybackResampled` | Playback instance (not instantiable from script) |

The class reference lives in `doc_classes/`. A GDScript facade that prefers these classes and falls back to the game's GDScript implementations is in `game_facade/cgame_audio_facade.gd`.

## Convolution reverb

```gdscript
var ir: PackedFloat32Array = CgameEarlyReflections.to_ir(
    CgameEarlyReflections.image_sources_box(Vector3(8, 3, 5), Vector3(2, 1.5, 2), Vector3(6, 1.5, 3), 3, 0.3),
    48000, 1.0)
var fx := AudioEffectConvolutionReverb.new()
fx.impulse = ir
fx.impulse_sample_rate = 48000.0
fx.wet = 0.4
AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), fx)
```

- Algorithm: uniformly partitioned overlap-save convolution (Gardner 1995; Wefers 2015). Own radix-2 FFT in double precision.
- `block_size` (default 256 frames) is also the latency of the wet signal; the dry path is not delayed.
- Setting `impulse`, `impulse_right`, `impulse_stream` or `block_size` while the effect is running builds a new kernel and a pre-allocated engine per live instance on the calling thread, then publishes it with an atomic pointer exchange. The audio thread never locks, allocates or frees; retired engines go back to the main thread through an SPSC ring.
- A mono IR is applied to both channels, `impulse_right` enables a true-stereo IR. `impulse_stream` accepts 8/16-bit PCM `AudioStreamWAV`.
- The IR switch resets the convolution state (no crossfade), so the old tail is cut when the IR changes.

## Early reflections

`image_sources_box` follows Allen and Berkley (1979). `to_ir` writes reflections as linearly interpolated impulses and adds a three-band diffuse tail (`impulse_response`). Results are deterministic. Not ported yet: `ray_reflections` (needs the BVH from the game project); `echogram_to_reflections` is available to convert an echogram computed elsewhere.

## Procedural audio streams

`AudioStreamProcedural.graph` uses the same dictionary format as the game's `audio_graph.gd` (see the class reference for node types). Oscillators use polyBLEP, filters are RBJ biquads, pink noise is Voss-McCartney. Delay time is capped at 10 s. Random sources use the engine's PCG generator seeded per node from `seed` and node id, so output is deterministic but not sample-identical to the GDScript implementation.

## Tests

`tests/test_cgame_audio.h` (doctest, `[CgameAudio]` prefix): partitioned vs direct convolution within 1e-4 for several block sizes and stereo IRs, tail detection, effect-level latency and live IR swap, WAV decoding, image-source counts and delays, IR normalization/determinism, graph validation, oscillator frequency, chunk-independent determinism and playback. Run with `bin/godot... --test --test-case="*CgameAudio*"` after a build.
