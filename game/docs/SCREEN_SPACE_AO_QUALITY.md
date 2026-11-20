# Contact shadow fidelity — native screen-space AO filtering

Albion After now changes the *native* Godot SSAO quality with the actual
game graphics level. Performance and Balanced (and Mobile/Compatibility)
do not enable the AO pass. Forward+ High uses MEDIUM and Forward+ Ultra
uses HIGH AO quality; both retain the **half-resolution** buffer,
2 blur passes, and standard 50–300m fade range. An idempotent native
RenderingServer profile avoids redundant quality updates.

On High, contact shadows ground forest roots, ruins, stairs, soldiers
and walls. On Ultra, higher-quality SSAO gathering retains more detailed
occlusion while the existing SDFGI adds bounced sunlight. High may also
have screen-space indirect diffuse bounce when budgeted. This change
does not add a duplicate full-screen post shader, ray tracing,
additional blur pass or textures.

The Cgame engine's SSAO and SSIL bilateral blur dispatch now ignores
out-of-bounds workgroup threads on odd-sized frames. Wide SSIL
blur also clamps its four edge-metadata imageLoad neighbors; outside
image reads were undefined on Metal/Vulkan and could leak incorrect
brightness across the boundary. The existing depth/normal edge
weights and ray counts are preserved.

Inspirations: Unity HDRP ambient occlusion denoise/sample count and
Godot's native scalable SSAO/SSIL; no proprietary algorithm is copied.
The change uses exact existing native Godot APIs.

Validation: `res://tests/test_graphics_indirect_lighting.gd`, and
`python3 -m unittest tests/servers/rendering/test_ao_blur_bounds.py -v`.
Both are connected to the graphics workflow. Shader compilation and
GPU comparisons on Apple M1 Metal and Vulkan remain necessary.
