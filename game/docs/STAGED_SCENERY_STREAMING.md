# Camera-priority staged cosmetic scenery streaming

## Why

The native WorldStreamer already bounds whole-chunk generation, and ChunkView already grows procedural grass over multiple frames. However, the complete _build_decor() loop previously constructed every decorative plant, fallen branch, pebble and extra prop synchronously during the chunk generator callback. A heavily decorated new forest cell could therefore exceed the soft native main-thread limit by a large amount, leading to frame-time spikes or delayed appearance of playable world objects.

Unreal Engine World Partition separates spatial chunk residency from optional HLOD/scenery detail and uses priority-based streaming sources; Unity time-slices runtime content integration. This implementation adapts the same **separate playable residency versus visual completion** concept to Albion After, rather than imitating those engines' exact streamers.

## Game integration

1. The normal ChunkView.build() path still immediately creates native ChunkedTerrain3D, terrain materials, road/contact masks, resource trees and rocks, crates, walls, workbenches, windmills, signposts, NPCs and reflection anchors. None of their server-authoritative IDs or availability depend on cosmetic detail.
2. _build_decor() now creates only the inexpensive deterministic anchor lists and a list of cosmetic **categories**: nature-pack plants/bushes/pebbles, followed by extra model decorations. The original placement algorithms for each category were moved unchanged to _build_nature_decor_entry() and _build_extra_decor_entry().
3. Each loaded ChunkView contributes a WeakRef to the one static shared queue. On the first ChunkView process of a render frame, _service_decor() sorts live candidates by distance to the current camera plus bounded view-facing preference. It then processes one atomic category at a time, cycling between chunks so a nearby forest does not permanently block all other cells.
4. _decor_rng preserves each chunk's seeded RandomNumberGenerator state between categories. Interleaving the work between chunks therefore never changes the distribution, world positions or scale of decorations compared with the original synchronous build for the same world seed.
5. The queue prunes unloaded and completed chunks, and the existing GPU MultiMesh batching, visibility AABBs, PBR material reuse, shadow budgets, and leaf-motion shaders remain unchanged.

No new threads, GDScript awaits, GPU passes, textures or physics objects were added. The main-thread tasks are **atomic**, so a single category can exceed the budget; at least one task is allowed per frame to prevent starvation.

## CPU budget

| Graphics tier | Additional shared decorative CPU time slice |
| --- | ---: |
| Performance | 850 µs per frame |
| Balanced | 1,100 µs per frame |
| High | 1,700 µs per frame |
| Ultra | 2,400 µs per frame |

This budget is **additional to** the native WorldStreamer chunk integration time limit and the separate existing procedural grass budget. It caps the aggregate **cosmetic work across all ChunkView nodes**, rather than accidentally multiplying the time slice by the number of streamed chunks. It is a soft target, not a hard GPU/CPU frame deadline; measure the combined peak main-thread load and retune for hardware.

## Native Godot engine: visual completion tracking

WorldStreamer now optionally asks newly adopted chunks whether they implement has_pending_visual_detail(). If that method returns true, it adds the cell to pending_visual_details, without affecting loaded count, load radius, object visibility or server authority. Gameplay can always interact with the chunk from chunk_loaded.

When ChunkView finishes its last decorative category, it calls parent WorldStreamer.mark_visual_details_ready(Vector3i(cell.x, 0, cell.y)). The engine removes the pending marker and emits chunk_visual_details_ready(cell). If the chunk is unloaded or externally freed before completion, its pending marker is automatically erased. Other engine scenes need not implement this method and remain unchanged.

A new read-only get_pending_visual_details_count() reports how many **already resident** chunks still have unfinished optional cosmetics. The online benchmark log now records loaded / queued / threaded / visual counts separately, allowing testers to diagnose visual pop-in without confusing it with unavailable game world.

## Validation

After building the custom Godot engine, run native [WorldStreaming] tests in tests/scene/test_open_world.cpp and the game's:

    godot --headless --path game --script res://tests/run_graphics.gd
    godot --headless --path game --script res://tests/run_all.gd

Game tests cover camera priority, bounded first-task progress, four profile budgets, cosmetic readiness, native pending telemetry, repeated completion and cleanup on unload. No runtime graphics/CPU/GPU timing has been measured in this environment.

For a fair performance evaluation, teleport and ride between heavily decorated forests and urban ruins, compare before/after p50/p95/p99 **CPU frame times**, pending cosmetic count and total time to fully populate near-camera chunks. Verify distant objects do not all spawn in a single burst, never show missing interactive objects and preserve the deterministic artistic distribution across repeated reloads. The system is expected to reduce *individual-frame* creation spikes but may extend the time before every tiny prop is visible.
