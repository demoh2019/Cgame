# World-stable GPU-instanced undergrowth and MultiMesh CPU optimization

Inspired by Unreal Engine's *PerInstanceRandom* vegetation and Unity's
GPU Instancing per-instance material properties, Albion After now adds
subtle pigment variation to repeated world decoration (ferns, bushes,
plants, flowers and tall grass), while maintaining **one MultiMesh draw
call per spatially culled batch**, all existing imported textures and
material normal/ORM maps.

Each flower and fern is tinted once at chunk construction using a
deterministic hash of its **global x/z position**. The hue remains
identical when chunks unload/reload and is unchanged by splitting a dense
batch into 32 m culling cells. Shading reuses Foliage's already present
`instance_tinted`/COLOR shader path. No new shader passes or extra PBR
textures or entities. Rocks, mushrooms, petals and additional props
preserve exact authored colors and have **no extra four-float buffer**.

The game's SceneryBatches now packs 3x4 basis+translation and optional
RGBA into a single PackedFloat32Array and calls Godot's native
`MultiMesh.buffer` upload ONCE per culling batch. Previously it sent
one RenderingServer transform write per model; colored models otherwise
would add a second write per instance. The layout was verified against
the Cgame engine's `MeshStorage::_multimesh_instance_set_transform`.

The C++ Godot fork also avoids redundant
`MultiMesh::set_visible_instance_count` RenderingServer dispatch when
the requested prefix is unchanged, preserving valid -1/all, 0/none,
and positive count transitions. This benefits grass and streamed
geometry independently of the new undergrowth coloration.

Safety and performance: the palette only varies material color, not
alpha/collision/positions. Existing draw-distance fade, batching, bounds,
shadow budgets, LOD and weather stay unchanged. The optional RGB color
channel costs only 16 bytes per colored instance at creation and adds
no draw call; test on target GPUs before claiming FPS wins.

Regression suite: res://tests/test_scenery_pigment_instancing.gd.
Run: godot --headless --path game --script res://tests/run_graphics.gd.
C++ fork changes require engine rebuild. Both test execution and visual
GPU screenshot comparison are pending in this environment.
