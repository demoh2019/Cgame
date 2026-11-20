# Native AgX filmic highlight preservation in Cgame + Albion After

The Cgame engine fork already implements native AgX tonemapping (its
`Environment.TONE_MAPPER_AGX` and white/contrast properties), but the game
previously used ACES for every GPU and graphics preset.

## Gameplay rendering

- Forward+ **High** uses AgX, a 12.5 scene-white point and 1.20 contrast.
- Forward+ **Ultra** uses AgX with white at 16.29 and contrast at 1.26,
  letting bright sun, clouds and wet-surface highlights roll off naturally.
- Performance, Balanced, Mobile and GL Compatibility preserve ACES with
  the game's original white-point value of 6.0.
- Existing `CinematicColorGrade` continues adjusting exposure, storm
  saturation and glow using the same Environment resource in both clients.
- Preset/renderer switching happens through the existing GraphicsQuality
  controller. No new LUT, full-screen shader, texture or lighting pass.

## Engine-side optimization and safety

`scene/resources/environment.cpp` no longer sends identical tonemap mode,
exposure, white and AgX contrast parameters to the RenderingServer every time
the game updates its weather/day-night cinematic grade. Non-finite and negative
exposures, invalid white points and invalid AgX contrast are ignored, avoiding
invalid HDR inputs; changing AgX white while ACES is active updates the cached
property without uploading irrelevant tone-map state.

Engine-side regression lives in `tests/scene/test_sky.cpp` under the
`[SceneTree][Environment]` test name. Game integration is covered by
`game/tests/test_cinematic_color_grade.gd`. These are source-level changes,
not a claim of a compiled renderer or benchmarked performance.

Run the **custom Cgame engine** and the Godot game tests:
`godot --headless --path game --script res://tests/run_all.gd`.
Review reference frames at sunrise, midday, storm, night, glancing-angle water
and wet stone before tuning exposure or saturation further.
