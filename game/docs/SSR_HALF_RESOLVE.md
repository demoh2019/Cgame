# Pixel-correct half-resolution SSR reconstruction (engine + Albion After)

## Visible result

Godot Forward+ already traces glossy reflections on a half-resolution
Hi-Z buffer to keep reflections affordable in forests, roads and wet
PBR environments. However, the original four-tap bilateral upsampler
used mirrored corner weights and a non-pixel-centered texel origin.
This shifted fine reflection edges and made bright streaks/halos and
screen-edge instability more noticeable under camera motion.

The engine's SSR resolve compute shader now projects full-resolution
pixel centers into **actual allocated half-texture dimensions**,
including odd window sizes and dynamic render scales. Four correctly
oriented bilinear weights are combined with the existing depth,
normal and roughness weights, retaining crisp glossy boundaries.
Texture fetches replicate the nearest valid texel at screen borders.
The HDR inverse-tonemap has a finite denominator to avoid Inf/NaN
energy spikes from intensely lit wet materials.

No extra ray steps, textures, buffers, shader passes or temporal
history are added: this uses the exact same four bilaterally weighted
samples as before. The game tightens depth-hit tolerance from 0.25 to
0.24 for High and 0.22 to 0.20 for Ultra, now that resolve is correctly
pixel-centered; existing High/Ultra ray steps (28/48), native roughness
filters and per-backend gating remain. Performance/Balanced never
enable SSR, and Compatibility/Mobile keep SSR disabled.

Influence: Unity's half-resolution SSR with configurable upscaling and
surface roughness treatment, and Unreal's layered SSR/reflection-probe
fallback. This is a native Godot GPU reconstruction fix, not a claim
that it implements proprietary HDRP/Lumen/TSR denoisers.

## Verification

Python unit/source tests: 
`python3 -m unittest tests/servers/rendering/test_ssr_half_resolve.py -v`
validate even/odd viewport geometry, four corner weights and
in-bounds samples. The existing Godot
`res://tests/test_graphics_reflections.gd` tests real in-game profile
switching. Both are integrated in
`.github/workflows/albion-after-graphics.yml` with a sparse
checkout of the affected engine shader.

Source-contract tests are not equivalent to compiling GLSL for Metal
or to a visual frame capture. Validate GPU P95 and image stability in
the same moving-camera scene on M1 Metal and Vulkan before claiming
measured runtime gains.
