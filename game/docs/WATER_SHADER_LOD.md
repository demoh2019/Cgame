# Water shading LOD: keep near-camera detail, skip deep-water noise

The existing ocean already supports physically inspired Fresnel, shoreline
depth tinting, wave slopes and foam on both Compatibility and Forward+ paths.
This change **preserves all near-camera water detail** while making the
expensive high-frequency noise distance-aware.

- High/Ultra compute distance only when fine ripples are enabled.
- A smooth distance fade attenuates fine wave slopes and fine foam noise;
  the low-frequency wave trains, Fresnel, base colors and depth are unchanged.
- Far water skips fine noise fetches entirely, with no additional textures.
- Deep-water pixels do not evaluate foam noise at all. Foam still appears
  near beaches, rocks and shallow underwater surfaces.
- `graphics_profiles.gd` sets quality-specific start/end distances:
  Performance 20–45 m, Balanced 40–85 m, High 65–125 m, Ultra 105–195 m.
  The first two presets do not use the high-frequency noise branch because
  their ripple strength is at most 0.30.
- The graphics-quality switch updates two uniform floats on the existing
  shader material. No changes to network, physics or renderer internals.

This follows the same *screen-size-dependent detail* principle used in
large-world engines; it does not implement Unreal's Single Layer Water.

Run `godot --headless --path game --script res://tests/run_all.gd`.
Additional tests validate the preset ranges and water shader asset/branches.
GPU timings and screenshots still need evaluation on real hardware.
