# Cinematic time-of-day color grading

The game already tonemaps its HDR 3D view through Godot's ACES tone mapper. Its existing full-screen canvas postpass handles a subtle diorama tilt-shift, bounded focus sharpening, split-tone grading and vignette **under the HUD**.

The previous postpass hardcoded cool shadows and golden highlights. Now those two exact color vectors are parameters updated at a **5 Hz maximum** cadence from the authoritative day/night clock and smoothed local storm intensity. No extra postprocess pass, texture sampling or noise is introduced:

- **Day:** the original neutral/cinematic baseline.
- **Dawn and dusk:** richer, warm highlights near the horizon without shifting all shadows orange.
- **Night:** deep blue-tinted shadows and cooler highlight balance while preserving gameplay readability.
- **Storms:** lower warmth and cool, muted highlights, fading smoothly with the existing storm controller.
- **Underground:** an independent cool-shadow/warm-torch palette; surface day and weather are not used for cave grading.

The grade runs after the engine's ACES tonemapping, complementing rather than replacing it. The gameplay HUD and menus are on a higher canvas layer and do not inherit the grading.

No new textures, shader branches, screen taps, or game/server simulation changes. The two uniform values change every 0.2 seconds rather than every frame; the color transitions remain smooth because game time and weather vary slowly.

## Visual and performance acceptance

Compare equal-camera screenshots at midday, sunrise, sunset, deep night, storm and an underground torch-lit scene. Check that health-bar/team UI colors remain unchanged, trees are visible in moonlight and warm dusk is not oversaturated. Measure median and p95 GPU time on both Compatibility and Forward+; source-level reductions do not constitute a measured frame-rate improvement.

Headless regression: `godot --headless --path game --script res://tests/run_all.gd`. The added `test_cinematic_color_grade.gd` checks palette determinism and smooth behavior under weather transitions.
