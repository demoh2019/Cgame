# Screen-space cinematic pollen and fireflies

The game's atmospheric particles used to draw 1 m-wide camera-facing
additive quads. At close camera ranges those quads could span dozens of pixels,
producing oversized pale discs and unnecessary translucent pixel overdraw.

## Renderer technique

Inspired by the screen-space coverage considerations documented for thin
geometry in Unreal Engine's temporal upscaling pipeline. This is a small
analytic feature-size control, **not** Unreal TSR or temporal reconstruction.

The existing 3x3 world-tile `AmbientMotes` MultiMesh and 4 Hz updates remain
unchanged: no per-mote CPU updates, no new textures, no extra draw calls,
no new framebuffer passes.

* Engine: `scene/3d/camera_3d.cpp` exposes
  `get_world_size_for_pixel_diameter_at_position(world_point, pixel_diameter)`.
  This is the inverse of the existing native pixels-per-meter camera method.
  Projection, viewport aspect and orthographic camera size are handled by
  the same projection data used by the renderer. Invalid input is zero.
* Game: `scripts/client/mote_screen_space.gd` chooses an output-pixel
  diameter for Balanced/High/Ultra: 3 / 3.5 / 4 px respectively. The final
  shader adjusts fireflies and pollen independently, making slightly larger
  warm fireflies and smaller daytime pollen.
* When internal FSR2 resolution is below output resolution, choose at least
  1.75 internal pixels to reduce flickering in the sparse glow quads.
* Game `AmbientMotes.update_view()` calibrates world diameter at the avatar
  at most four times per second. The vertex shader uses each instance's
  camera-space depth to correct world size per particle, and treats orthogonal
  projection as depth-invariant. World diameters are bounded from 1.2 cm to
  40 cm so unexpected camera transitions cannot make huge additive discs.
* Stock Godot lacks this new native helper, so GDScript computes the same
  perspective/orthographic size from viewport resolution, FOV and camera
  depth as a fallback. This path remains playable without rebuilding the fork.
* Original deterministic world tile placement, alpha falloff, firefly pulse,
  storm/day/night activation, wind animation and GPU batching are retained.

## Validation

`tests/scene/test_camera_3d.cpp` checks native camera pixel-to-world sizing
at multiple depths and with keep-width and keep-height aspect conventions.
`game/tests/test_mote_screen_space.gd` checks GDScript fallback, bounds,
FSR2 scaling and the live shader integration.

Run Godot tests on a compiled fork and the game contract suites:

```sh
godot --headless --path game --script res://tests/run_all.gd
```

Visually compare a forest at noon (pollen) and swamp at dusk (fireflies),
1080p/4K, zoom 0.55–1.8, with and without FSR2. Profile GPU draw time and
overdraw before claiming measured FPS gains: this should reduce additive
quad pixel coverage, but no benchmark results are currently recorded.
