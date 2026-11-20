# Rain on the lens: fused high-end weather post-effect

Inspired by Unreal post-process materials and Unity HDRP full-screen rain
effects, Albion After now offers **subtle simulated lens droplets** in the
existing screen-grade shader. This is an optional cinematic embellishment,
not a change to the actual world rain particles or character physics.

- Only Forward+ High and Ultra allocate fragment work. Performance,
  Balanced, Mobile, Compatibility, clear weather, drizzles, shelters and
  dungeons take a zero-strength branch.
- A tiny drifting procedural droplet field uses built-in TIME and screen
  pixel size. No external textures, GPU normal atlas, compute task, or
  per-droplet node/particle is allocated.
- The shader reads one additional screen pixel **only inside a small
  visible droplet**. It bends background by about 2-3 display pixels and
  adds a faint white rim; no new fullscreen draw call or screen copy.
- The center of the game screen, where the player stands and fights,
  is explicitly protected by the existing focus-center uniform. UI stays
  sharp because the post layer renders behind the HUD.
- Quality limits: High <= 0.32, Ultra <= 0.60; normal storms fade in
  continuously above the 0.38 threshold and fade out under shelter.
- The client already batches cinematic color-grade updates at 5 Hz.
  We update weather and the normalized regional wind on the same cadence,
  not on every rendered frame; no new network packets or save fields.

A separate post grade would cause another Godot canvas_item screen-texture
copy. This implementation reuses the existing pass and sampler by design;
the offline preview, which has no corresponding post layer, is unchanged.

Tests: game/tests/test_graphics_lens_rain.gd
Run: godot --headless --path game --script res://tests/run_graphics.gd

Measure actual GPU cost and evaluate accessibility in storm scenes on the
target rendering backends; assertions do not establish visual quality.
