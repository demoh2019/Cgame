# Graphics quality (Godot 4)

The online client uses a configurable graphics profile. Press **Ctrl+F11** on the title screen or in-game to cycle **Performance → Balanced → High → Ultra**. The option persists in `user://albion_after_graphics.cfg`.

- **Performance**: FXAA, no dynamic sun shadow or tilt-shift blur.
- **Balanced** (default): FXAA, near sun shadows and 5-tap edge blur.
- **High**: 2× MSAA, farther shadows, 9-tap blur and glow where the renderer supports it.
- **Ultra**: 4× MSAA, longest shadows, enhanced bloom and SSAO on Forward+.

The project remains on the Compatibility renderer. SSAO and glow can be unavailable there; these flags take effect with a compatible Forward+ build. Game/network simulation and deterministic world generation are unchanged.

Grass tiles are already drawn as MultiMeshes. Their build-time CPU budget is reduced from 10 ms to 2.5 ms per frame across chunks to reduce hitching while streaming. A single tile may still exceed the budget because tile construction is synchronous.

Benchmark representative scenes at native 720p and 1080p on the target devices; compare frame-time percentiles, GPU time, and draw calls rather than inferring real FPS gains from shader sample counts.

## Rendering-aware improvements

Forward+ now uses FSR 2.2 at 0.59/0.77 scale for Performance/Balanced. Mobile uses FSR 1 spatial scaling; the default Compatibility renderer remains at native resolution, without unsupported temporal upscaling. High and Ultra use native resolution and their configured MSAA. Ultra optionally enables screen-space indirect lighting on Forward+ only.

The quality presets also tune the existing procedural grass LOD pipeline: streaming radius, shared per-frame build budget, and shader fade range. Switching quality updates the visibility range of already generated grass tiles without regenerating meshes. Compatible renderers and distant foliage must be visually verified on actual GPU hardware.
