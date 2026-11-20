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
