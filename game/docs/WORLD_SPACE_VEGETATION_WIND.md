# World-aligned vegetation wind and grass lighting

Existing regional weather winds are expressed in **world X/Z**. Imported
trees, bushes and each procedural grass tuft can be independently rotated
or nonuniformly scaled. Previous wind shaders applied the weather X/Z motion
directly to LOCAL vertices: two identically exposed trees with different
instance yaws could lean in different world directions.

## What changed
- Both existing Godot shaders now share
  `res://assets/shaders/vegetation_wind_space.gdshaderinc`. It converts a
  world-horizontal displacement to local vertex coordinates by projecting
  onto each instance's actual model X/Z basis axes. This handles normal
  yaw rotations and nonuniform size while avoiding a full per-vertex matrix
  inverse. The prevailing wind stays aligned across repeated instances.
- Both shaders avoid wind-phase trigonometry entirely when the weather
  reports still air, in addition to the existing distance-based wind LOD.
- A **quality-scalable grass-normal tilt** follows the vertex bend. High
  and Ultra receive gently changing sunlit tip highlights; Performance
  keeps the original static up-facing normal. This is vertex-to-fragment
  interpolation in the original shader, not another light, screen pass,
  shadow map, geometry clone or texture.
- All 4 quality profiles broadcast the normal strength via a single
  global uniform at preset changes. The simulation, gameplay hitboxes,
  weather state and network remain untouched.

The approach follows Unreal's vertex World Position Offset / grass wind
and Unity's vertex-stage SpeedTree normal interpolation, adapted to
Godot's local-space VERTEX convention. It is not Nanite or a custom
deferred renderer. Non-orthogonal/sheared model bases are outside the
intended model asset pipeline.

## Verification
`game/tests/test_vegetation_wind.gd` now exercises projection under
multiple yaws / scale pairs, source contract, windless cost gates and
quality presets. It is already in `run_all.gd`.

`godot --headless --path game --script res://tests/run_all.gd`

Theoretical work saved: the weather-calmed branch skips vertex sine/cosine
and per-vertex wind projection. Actual GPU timing and visual review of
sunlit grass, rotated trees and gust animations require a Godot runtime.
