# Regional wind shapes water wave normals and whitecaps

The ocean/surface water now responds optically to the *same smoothed
regional weather wind* already uploaded by the shared Atmosphere for
vegetation (global `aa_vegetation_wind`: XY direction, Z intensity).

High and Ultra add a single world-anchored travelling wave with
analytic slope; the shader adds that slope to the original two
crossing wave trains before computing water PBR normals, guarded
screen refraction and existing storm whitecap foam. Thus wind
direction, reflections, foam and surface wave appearance stay
coherent without a simulation texture, CPU mesh deformation, a
foam/spray emitter, or a second render pass. Gameplay water
collision/boiling/travel remain untouched.

**GPU budget:** Performance/Balanced use strength 0 and skip the
new branch. High 0.27 and Ultra 0.45 calculate one cosine only when
a nonzero weather wind exists and the surface is near the camera
inside the existing fine-detail fade. No additional samplers or
runtime per-frame material updates. The weather vector is already
published at most 10 Hz. This is a small approximation rather
than an FFT ocean solver.

Inspired by Unreal's Single Layer Water and Unity HDRP's water
simulation/foam systems, adapted to the Godot 4 single-material
world for a much lower GPU and memory budget.

Test: `res://tests/test_wind_driven_water.gd` in the full
`run_all.gd` suite. Profile GPU P95 and compare still/calm/storm
views on Metal, Forward+ Vulkan and Compatibility.
