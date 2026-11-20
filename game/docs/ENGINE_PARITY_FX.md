# Engine parity: impact decals and reverb zones

Comparison of Cgame against Unity (URP/HDRP) and Unreal Engine 5 for what the
game uses at runtime. Already covered natively: GPU particles (≈ Niagara/VFX
Graph), adaptive music (≈ MetaSounds/Wwise states), camera trauma shake (≈
Cinemachine Impulse / UE CameraShake), streaming world partition, AgX filmic
tonemap, dynamic resolution, contact shadows, eye adaptation.

Gaps closed here (no engine change needed):

| Feature | Unity | Unreal | Cgame now |
| --- | --- | --- | --- |
| Projected decals | URP Decal Projector | Deferred Decals | `scripts/client/impact_decals.gd` — pooled `Decal` ring buffer; ichor on infected hits/deaths, blood on player hits. Budget 0/24/48/96 by quality tier, 40 s lifetime with 6 s fade, follows the quality menu. |
| Reverb zones | Audio Reverb Zone | Audio Volumes | `scripts/client/reverb_zones.gd` — `SFX` bus with `AudioEffectReverb`; underground / forest-swamp / open presets blended per frame in `audio.update_reverb`. All 3D world sounds route through it. |

Remaining gaps worth considering later: physics ragdolls on death
(PhysicalBone3D), foot IK on slopes, motion blur, and per-material footstep
sounds.

Tests: `tests/test_engine_parity_fx.gd`.

## Ragdolls (Unity ragdoll joints / Unreal Physics Asset)

`scripts/client/ragdoll.gd` builds `PhysicalBone3D` bodies at runtime from the
mannequin bones a model has (pelvis, spine, head, arms, legs; cone joints,
hinged elbows/knees). A killed infected falls as a ragdoll with a push away
from its facing, onto a 9×9 m heightmap collider of the terrain under it (own
collision layer, so nothing else is touched). Budget 0/3/6/12 corpses by
quality; each settles 5 s then sinks into the ground and is freed. Rigs without
mannequin bones and Low quality keep the old instant despawn.
Tests: `tests/test_ragdoll.gd`.

## Combat and interaction VFX (Unity VFX Graph/Shuriken, Unreal Niagara)

`scripts/client/combat_vfx.gd` (one node, wired from `online_main.gd` via
`handle_event` and `update_player`). Everything is pooled/capped per
`GraphicsQuality.level()` (0 = off, then 1..3 grow); math lives in static
helpers covered by `tests/test_vfx_parity.gd`.

| Feature | Unity | Unreal | Cgame |
| --- | --- | --- | --- |
| Ranged tracers | Trail/Line renderer | Niagara beam/ribbon | stretched additive box from shooter along `dir`, 0.12 s fade |
| Shell casings | Particle System + collision | Niagara mesh particles w/ collision | brass cylinders, ballistic + one bounce, 2.5 s |
| Muzzle / blast light | Light + animation | Niagara light renderer | pooled `OmniLight3D`, quadratic falloff (1/2/3 by tier) |
| Melee swing trail | Trail Renderer | Ribbon emitter | fading arc ribbon in front of the attacker |
| Material-aware impacts | Per-surface VFX tables | Physical Material to Niagara | metal sparks, wood chips, stone, sand, mud, water, dirt (`material_for`, `impact_profile`) |
| Directional blood/ichor | Velocity-from-hit particles | Niagara event payload direction | spray away from the attacker, slightly upward |
| Water splash + ripples | Shuriken wading splash | Niagara water interaction | rings and droplets at `WATER_LEVEL` while moving in water |
| Landing dust | Animation event puff | Anim notify + Niagara | puff scaled by measured fall speed (>3 m/s) |
| Explosion shockwave | Shockwave + point light | Niagara shock ring + light | ring, dust, light on flash grenades and broken barricades |
| Pickup sparkle | Sparkle VFX | Niagara sparkle | rising billboard sparkles on crates, colour by item |

Not done: campfire heat shimmer/smoke flipbook and death dissolve shader (no
campfire/loot-bag node hooks yet), and impacts at real ray-hit points (the
server sends no hit position for ranged shots).
