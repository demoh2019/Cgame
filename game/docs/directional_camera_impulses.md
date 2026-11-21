# Directional world-space camera impacts in Cgame + Albion After

## Feature

Unreal Engine's **PlayWorldCameraShake** can orient a shake towards the
epicenter of a world event. Cgame's pre-existing `Camera3D.add_spatial_trauma`
implemented radial attenuation and a procedural trauma shake, but not
source-oriented motion.

Cgame now adds:

```gdscript
camera.add_directional_spatial_trauma(
    impact_position, player_position, 0.2, 1.0, 8.0)
var local_impulse: Vector3 = camera.get_shake_direction_impulse()
```

- The **direction** points towards the impact, expressed in the camera's local
  axes at event time. Different sides of a fight produce distinct visual cues.
- The **magnitude** uses the existing smooth spatial falloff: full influence
  inside the inner radius, zero at or beyond the outer radius. The event
  amount is clamped before accumulation, and the direction has unit maximum.
- The visual directional kick decays with `shake_decay`. Combined procedural
  and directional translation is capped by `shake_max_offset` on each axis.
  The camera's real Node3D transform and game/player positions do not move.
- Invalid coordinates/radii, nonfinite or non-positive amounts have no effect.
  Coincident impact/listener positions still shake, but invent no direction.
- `set_trauma(0)` clears random and directional shake immediately. No GPU
  work, physics query, per-impulse allocation, or additional scene node is
  required.

## Actual Albion After integration

`game/scripts/client/combat_camera_feedback.gd` uses the new method on real
client events from `online_main.gd`:

- `hit_zombie`: directional strike;
- `knockback`: directional blast;
- `barricade_broken`: directional destruction;
- `zombie_died` and `flash_thrown`: keep nondirectional trauma.

The existing player's **Reduce screen shake** accessibility setting scales
the amount *before* entering C++. With its scale zero, directional and
nondirectional feedback are both disabled. Older Cgame builds automatically
use `add_spatial_trauma`; stock Godot's independent fallback behavior is
unchanged. These cues are **cosmetic only**, never server-authoritative.

## Verification

- Native: `tests/scene/test_camera_shake.cpp` — validates direction,
  opposite-direction cancellation, stack saturation, spatial falloff, invalid
  event protection, render-only movement, and decay to rest.
- Game: `game/tests/test_combat_camera_feedback.gd` — checks real cue
  selection, camera direction and accessibility behavior.
- Source contract: `python3 -m unittest tests/scene/test_directional_camera_impulse_contract.py -v`.
- CI: `.github/workflows/native-camera-directional-impulses.yml` builds Cgame
  and runs native tests plus headless Albion game tests.

This is a targeted, standalone engine feature inspired by Unreal's world shake:
https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/Camera/APlayerCameraManager/PlayWorldCameraShake

The effect's in-game artistic quality must be evaluated interactively.
No performance increase is claimed; this adds bounded cosmetic motion.
