# Camera-like exposure adaptation for High and Ultra

Godot 4 `CameraAttributesPractical` controls **native scene luminance
adaptation** on the existing WorldEnvironment, which is shared between
the online and solo client. Bright clear skies, underground torchlit
bunkers and moonlit scenes can transition without immediate exposure
jumps. This **does not replace** the hand-designed ACES, time-of-day
color grade and environmental fog. It preserves the game's artistic
night palette with deliberately narrow ISO limits.

Renderer cost policy:
- Performance and Balanced: automatic exposure always disabled.
- High Forward+: ISO 90..150, adaptation speed 0.65.
- Ultra Forward+: ISO 80..200, speed 0.85.
- Compatibility and Mobile: disabled at every graphics level.
- The practical CameraAttributes resource is created once, reused for
  all profile changes and does not enable depth-of-field blur.

Automatic exposure is a **native GPU luminance effect** and does carry
a render workload, unlike simple changes to environment uniforms.
High/Ultra opt into that cost, with conservative adaptation range.
Godot's automatic exposure is only supported by Forward+; no
unsupported shaders, extra software loops, or custom histogram
buffers are introduced. Artists can retune min/max sensitivity after
capture review; P95 GPU timing and day/night screenshots should be
measured before release.

Related technologies: camera exposure adaptation in Unreal Engine and
Unity HDRP's exposure and tonemapping; native implementation uses
Godot 4 WorldEnvironment and CameraAttributes, not their code.

Validation: `game/tests/test_graphics_eye_adaptation.gd`, registered
in the headless runner `game/tests/run_all.gd`.
