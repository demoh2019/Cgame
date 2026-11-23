# P1 Virtual Geometry — GPU-resident meshlet pages (increment)

This stage extends the **existing** experimental `game/scripts/client/meshlet_renderer.gd` task/mesh shader path. It is a real GPU buffer residency and upload-budget implementation, **not** a claim of feature parity with Unreal Nanite.

## Fixed-slot GPU geometry pool

The existing mesh shader supports **32 meshlets per task workgroup**, with up to 64 vertices and 124 triangles per meshlet. A *logical page* now holds 32 consecutive meshlets. A *physical GPU slot* contains all four payload streams for one resident page:

| Stream | Bytes per page | Contents |
|---|---:|---|
| Vertex positions | 32768 | 32 × 64 × vec4; deduplicated only within each meshlet |
| Meshlet vertex IDs | 8192 | 32 × 64 × uint, remapped to absolute physical slot offsets |
| Packed triangles | 15872 | 32 × 124 × uint (local triangle indices) |
| Meshlet descriptors | 1536 | 32 × 48 bytes (offsets, counts, sphere, normal cone) |
| **Total** | **58368** | **57 KiB per resident page** |

By default the experimental renderer allocates at most **64 slots (~3.56 MiB)** for these payload buffers, regardless of the number of source meshlets, and uploads at most **4 new pages per render frame**. These are configurables `max_resident_pages` and `max_page_uploads_per_frame` on `MeshletRenderer`; the game debug probe defaults to 16 slots and 2 uploads. Source geometry and logical page bounds remain **in CPU memory**, because disk-backed page serialization has not been added.

`MeshletPageStreaming.build_bounds()` creates a conservative sphere for each source page. `wanted_pages()` prioritizes pages whose bounds intersect the camera frustum, then nearest pages by distance, with deterministic id ordering for ties. Extra pages are prefetched if slots remain; nothing is permanently removed by a hard distance threshold. `plan()` reuses resident slots, fills free slots first and evicts only unwanted pages. No individual meshlet visibility is computed or read back on CPU. Task shader frustum/cone culling is still GPU-side.

The render-thread `_stream_gpu_pages()` uploads exactly the chosen page's four fixed-size streams through `RenderingDevice.buffer_update()`, updates the physical descriptor offsets and records the normal task shader draw **without GPU-to-CPU readbacks**. The mesh shader sees only the resident slot array. Its task stage skips zeroed descriptors for slots not yet loaded. Camera teleports cause bounded progressive page replacement; temporary incomplete geometry is possible until the page budget catches up.

This is **not indirect dispatch**: the CPU issues a fixed mesh-task group count equal to the allocated slot count, and the GPU task stage performs per-meshlet compaction before rasterization. There is still CPU per-page candidate sorting. The mesh shader itself and compositor pipeline need validation on real Vulkan `VK_EXT_mesh_shader` hardware.

## Real Albion After integration, disabled by default

The canonical `game/scripts/client/online_main.gd` can opt into a single debug draw **of the actual production rock mesh**, from `Meshes.get_mesh("rock")`, using `VirtualGeometryProbe`. It is not a second game, a replacement model catalog, or a production asset conversion.

```sh
CGAME_MESHLET_PAGE_PROBE=1 bin/godot.linuxbsd.editor.x86_64 --path game
```

The experiment requires a debug build and a rendering device that reports mesh shader support. With Metal or an older GPU the probe is not installed; normal game rocks, collisions, gathering, tier tints, networking and original materials are **unchanged**. On a suitable GPU one additional debug-colored meshlet rock appears near the camera's initial world focus. This deliberately tests the page allocator against an actual game mesh while avoiding regression to production PBR materials.

The script exposes `renderer.get_page_stats()`: `total_pages`, `resident_pages`, `slot_count`, `bytes_per_slot`, `gpu_capacity_bytes`, `last_page_uploads`, and a snapshot of resident logical page ids. These are capacity/counter observations, **not** claimed frame-time or VRAM benchmark results.

## Verification

- `game/tests/test_meshlet_page_streaming.gd` exercises conservative page bounds, camera priority and relocation, stable slots, evictions, byte-exact storage packing, the incomplete final page, zeroed unused slots, fallback rendering, and canonical-game probe integration.
- `game/tests/test_meshlet_renderer.gd` is now also registered in `game/tests/run_all.gd`, so the existing meshlet descriptor, shader section, CPU culling and fallback tests are not silently omitted.
- `tests/scene/test_gpu_meshlet_pages_contract.py` checks source contracts for matching descriptor/layout constants, render-thread budget wiring and the real game opt-in.
- The `gpu-meshlet-residency.yml` CI workflow imports the main project and runs focused headless suites after building the custom engine.

Local command when a matching built engine is available:

```sh
bin/godot.macos.editor.arm64 --headless --path game --script res://tests/run_one.gd -- test_meshlet_renderer test_meshlet_page_streaming
```

**Important:** A headless run cannot validate task/mesh SPIR-V compilation, framebuffer compatibility, synchronization or hardware throughput. This requires a Vulkan driver supporting `VK_EXT_mesh_shader`, an actual rendered scene capture, and GPU profiling.

## Remaining Nanite gaps

1. Bind the GPU page pool to visible, material-faithful production geometry, preserving UVs, tangents, normals, colors, skinning and surface material batching; today's meshlet shader is intentionally debug-shaded.
2. Add compressed on-disk pages and asynchronous CPU→GPU staging with a hard upload time/bandwidth budget. Current pages are generated from CPU-resident source meshes and updated synchronously on the rendering thread.
3. Implement GPU-driven coarse hierarchical LOD selection/visibility, Hi-Z occlusion, and indirect or mesh-task draw generation from GPU counters. Today's per-page priority is CPU-side and task shader per-meshlet culling is GPU-side.
4. Add a geometry fallback while high-resolution pages are loading, reliable temporal residency, large-world movement and teleport soak tests, and renderer/GPU vendor compatibility tests.

Other P1 tracks (dynamic GI/Lumen, terrain material layers, virtual texture/shadow feedback) remain separate work.
