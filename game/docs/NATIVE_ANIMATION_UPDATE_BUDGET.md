# Native animation update-rate budget — Albion After + Godot fork

## Inspiration

Unreal Engine uses animation Update Rate Optimizations and an Animation
Budget Allocator to reduce the skeletal evaluation workload in crowds
without pausing nearby heroes. Unity Animator Culling lets developers
stop evaluating non-visible or distant characters. Godot AnimationMixer
already supports MANUAL processing, so the fork can implement this
without inventing a second skeletal renderer or duplicating animation
tracks.

Documentation:
- Unreal Engine animation optimization:
  https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-optimization-in-unreal-engine
- Unity Animator culling:
  https://docs.unity.com/en-us/engine/6000.7/script-reference/unityengine/animatorcullingmode
- Godot AnimationMixer:
  https://docs.godotengine.org/en/stable/classes/class_animationmixer.html

## New native engine API

`AnimationMixer.advance_budgeted(delta, interval, max_catchup=0.5)`:
- Works only for mixers set to MANUAL animation processing. Returns a
  boolean indicating whether `advance()` evaluated a pose.
- Accumulates each skipped frame's delta in a C++ member instead of
  allocating or modifying a GDScript dictionary every frame.
- When enough elapsed time has accumulated, invokes the original
  *virtual* `advance(total_delta)` function, so AnimationPlayer's
  state machine, blend tracks, event ordering, and animation playback
  continue using their existing code.
- Bounds the catch-up duration so a large pause/loading stall never
  advances several seconds of melee clips in a single update.
- Immediately skips and clears pending time for inactive mixers or
  mixers using automatic physics/idle updates to avoid double ticks.
- Validates nonfinite and invalid inputs; respects the requested
  interval even if the catch-up cap was set too small.
- `reset_advance_budget()` clears old time when a character changes
  visual LOD without altering playback state or pose.
- `get_advance_budget_accumulated()` exposes read-only profiling
  information.

All methods are opt-in, without new serialized scene properties or
changes to the default AnimationMixer behavior. Runtime memory cost is
one double per mixer. This is not a full Animation Budget Allocator:
the game's existing distance/crowd policy still decides importance.

## In-game integration

The existing CharacterModel has a live crowd distance tier system
and switches far characters to MANUAL animation processing. It also
plays separate upper-body attack clips through `_layer`.

On the fork, `_tick_procedural` now invokes native
`advance_budgeted(delta, tier_interval, 0.5)` on the main animator
and optional upper-body player. Their elapsed time remains aligned.
When LOD changes, both native accumulation buffers are reset.

On stock Godot without the new method, the old GDScript tick path
remains with the same 0.5 s catch-up cap. This prevents new hard
dependencies on a custom engine binary. The game does **not**
activate two independently ticking controllers: existing crowd
logic remains the single owner of the character's animation rate.

| Animation tier | Approximate distance | Evaluation interval |
| --- | --- | --- |
| 0 / 1 | near | native full framerate |
| 2 | middle distance | about 30 Hz |
| 3 | far | about 15 Hz |
| 4 | distant edge | about 8 Hz |

Other LOD protections (procedural foot IK, look-at, root-motion ownership,
ragdolls and script gameplay) remain unchanged. Animation LOD is
visual-only; authoritative simulation still ticks as before.

## Testing

Engine C++:
`[SceneTree][AnimationPlayer] Native budgeted animation advances preserve elapsed time`
and
`[SceneTree][AnimationPlayer] Budgeted animation can be safely disabled`.

Game:
`godot --headless --path game --script res://tests/run_all.gd`
includes `test_anim_lod.gd`, covering native availability and the
stock fallback.

Verify visual parity with 20+ animated enemies, moving hero, attack
upper-body overlays and crowd quality switches. Profile main-thread
animation evaluation costs at 720p and 1080p with 20/50 characters,
checking p50 and p95 frame time, phase changes and gameplay events.
A native method does not guarantee better FPS until compiled and profiled.

A Godot binary and GPU runtime are not available in the authoring
environment; tests have been authored and source integration checked,
but the compiled fork still needs execution.
