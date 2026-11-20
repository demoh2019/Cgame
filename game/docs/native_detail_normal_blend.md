# Fix: true PBR detail normals on stone without changing source color

In the previous Cgame Godot fork, `BaseMaterial3D` generated the final
`NORMAL_MAP` assignment **only when both `detail_normal` and
`detail_albedo` were set**. Our High/Ultra dungeon masonry had intentionally
supplied `detail_normal` alone to preserve the artists' color texture.
That meant those perfectly valid micro-normal textures were sampled (in
some builds) but their result never reached lighting.

## Renderer C++ fix
In `scene/resources/material.cpp`, the generated material shader now
correctly handles a **detail-normal-only** material. It decodes the base
and detail maps into signed tangent space, combines them using normalized
Whiteout blending, then repacks to Godot's expected 0..1 NORMAL_MAP.
This preserves imported albedo, ORM, roughness and authored normal
vectors, while adding detail from the shared 128² normal map.

When `detail_albedo` exists, its alpha still modulates overlay strength;
a separate `detail_mask` still controls both overlays. If the source
doesn't have a base normal, the new generated shader uses the correct
flat default (0.5,0.5,1.0) and specifies NORMAL_MAP_DEPTH=1.0. There are
no undefined reads of NORMAL_MAP in the no-base-normal variant.

Changing `detail_blend_mode` to its existing value no longer needlessly
queues another generated shader variant. Actual blend-mode changes still
invalidate and recompile the appropriate material.

## Game detail improvements
`graphics_stone_microdetail.gd` retains native detail-normal-only
materials for covered stone walls, columns, stairs, pillars and rubble.
The shared source height function has acquired small intersecting
fractures and chips, aligned with the existing Ultra POM heightmap.
The images are generated lazily once and cached globally, **not per
draw or per frame**. No additional GPU texture reads, draw calls,
normal-atlas allocations or world geometry are required.

Quality/backend behavior stays unchanged: Forward+ High uses one
normal detail map, Ultra uses a stronger map plus 4–8 step POM,
Performance/Balanced/Mobile/Compatibility disable both. Models with
author-authored detail, transparency or missing tangents stay excluded.

This repair is inspired by normal-layer compositing in Unreal Engine
and Unity HDRP, but fixes the real native shader generator rather
than adding another post process.

Regression: res://tests/test_native_detail_normal_blend.gd
Registered in the game and graphics CI suites.
Run: godot --headless --path game --script res://tests/run_graphics.gd

The fork requires a native build to activate its C++ fix. Actual
lighting screenshots and GPU frame-time checks are still necessary.
