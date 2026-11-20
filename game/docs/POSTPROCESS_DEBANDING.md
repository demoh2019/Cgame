# GPU display-gradient debanding

The existing fullscreen filmic color-grade shader now optionally uses
**interleaved-gradient noise** (Jorge Jimenez, Next Generation
Post-Processing in Call of Duty: Advanced Warfare) after split toning,
contrast and vignette. A screen-pixel-anchored, stable hash perturbs
the finished scene by at most half of one 8-bit output step. This
decorrelates visible quantization stripes in clear skies, distant fog,
smooth dusk gradients and moonlit dark regions without blurring
valuable texture detail. A derivative-based flatness mask tapers the
effect across high-contrast silhouettes.

Cost: **zero new passes, zero texture samples, zero images/VRAM,
zero draw calls**. It reuses the current post-grade ColorRect shader.
Performance and Balanced disable the ALU branch. High uses 0.8 and
Ultra 1.0 display-step strength. The runtime quality controller
updates the existing material, including when adaptive quality changes.

There is no new engine module, network protocol, save field or
authoritative gameplay dependency. Automated regression assertions:
`game/tests/test_postprocess_deband.gd` via `run_all.gd`.

Visual confirmation and frame profiling still require a rendered
Godot session: the static tests do not measure actual GPU timings.
