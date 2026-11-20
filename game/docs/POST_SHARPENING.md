# Focus-zone post sharpening

The game's existing full-screen post effect provides split tone grading, vignette, and a shallow diorama tilt-shift. Native-resolution High/Ultra previously had no additional controllable focus detail enhancement.

**New:** a small, edge-limited spatial sharpening kernel operates inside the sharp middle band of the diorama. It uses the existing screen texture and *the same post-process draw call*, fetching four immediate neighbors only when the sharpen strength and focus mask are nonzero. It does not sharpen the blurred corners, gameplay HUD, or title/connect UI.

| Profile | Focus sharpen |
| --- | ---: |
| Performance | 0.00 (disabled, zero added samples) |
| Balanced | 0.00 (disabled; FSR2 retains its own image reconstruction on Forward+) |
| High | 0.14 |
| Ultra | 0.22 |

The 4-neighbor detail estimate is bounded by local pixel minimum/maximum and reduced at high-contrast edges. This is conceptually related to **contrast-adaptive sharpening** but is *not* AMD FidelityFX CAS.

When adaptive Forward+ FSR2 is active, post sharpen is disabled to avoid fighting the temporal reconstruction filter. Compatibility rendering and manually selected native High/Ultra use the focus enhancement.

This is a **GPU visual effect**, not a gameplay system. Nothing about terrain generation, network simulation, UI layout or physics changes.

## Validation

Run `godot --headless --path game --script res://tests/run_all.gd` for source-level regression checks. Visually compare fine foliage, distant roofs, terrain and thin props on manual High/Ultra at equal camera positions, at native 720p and 1080p. Look for halo artifacts, shimmer while moving, and any sharp seam between the focus strip and the blurred periphery. Profile median and p95 GPU frame time; no numerical FPS gain is claimed without hardware measurements.

References: Godot resolution scaling and post-processing documentation; AMD FidelityFX CAS principles; Unreal TSR / screen-percentage scalability.
