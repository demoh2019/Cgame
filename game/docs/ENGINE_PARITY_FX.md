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

## Camera and gameplay post-processing feel

`scripts/client/camera_post_fx.gd` (node `CameraPostFx`, wired in `online_main.gd`)
plus the overlay shader `assets/shaders/camera_post_fx.gdshader` (CanvasLayer -9,
hidden entirely when no effect is active). Pure helpers are unit-tested in
`tests/test_camera_post_parity.gd`.

| Feature | Unity | Unreal | Notes |
| --- | --- | --- | --- |
| Hit-stop on heavy hits / kills | Time.timeScale dip | Global Time Dilation | 0.06-0.09 s real time at 8-12% speed; own hits only |
| Damage red vignette | URP Volume Vignette (script-driven) | Post Process Vignette | scaled by damage, decays |
| Low-health desaturation | Color Adjustments | Post Process Saturation | below 40 HP, bluish grey |
| Heartbeat vignette | animated Vignette | animated Post Process | double-thump, faster at lower HP |
| Chromatic aberration pulse on hit | Chromatic Aberration | Scene Fringe | Medium+ quality |
| Radial motion blur at speed | Motion Blur / custom | Motion Blur | sprint or bike; taps 0/3/5/8 by tier |
| FOV kick | Cinemachine Lens | Camera FOV curve | sprint +3.5, bike +6 |
| Speed zoom pull-out | Cinemachine Framing Transposer | Spring Arm length | bike +12%, sprint +5% |
| Camera look-ahead | Cinemachine Lookahead Time | Camera Lag / lookahead | capped 2.6 m, smoothed |
| Death letterbox | Cinemachine letterbox / Timeline | Letterbox Cinematic | bars slide in while dead |
| Photo mode | Cinemachine free-look | Photo mode / Debug camera | Ctrl+Alt+P: orbit (left drag), wheel zoom, HUD hidden, Esc exits |

Already present and not duplicated: trauma camera shake, tilt-shift depth of
field and vignette in `post_grade.gdshader`, mouse-wheel zoom with limits.

## Audio parity

All logic is in pure helpers under `scripts/client/audio_*.gd`, wired through
`audio.gd` (`update_environment`, `play_at`, `on_event`, `handle_key`) and a few
lines in `online_main.gd`. Tests: `tests/test_audio_parity.gd`.

| Feature | Unity | Unreal | Cgame |
| --- | --- | --- | --- |
| Surface footsteps | Physic-material footsteps | Physical Surface + footstep notifies | `audio_surfaces.gd`: stone / water / sand / mud / leaves / grass from biome, height vs water level and dungeon; retunes pitch and loudness by surface and speed. |
| Terrain occlusion | Low Pass + occlusion plugins | Attenuation occlusion | `audio_spatial.terrain_blocked`: height-field line test listener to source; occluded one-shots get a 1.4 kHz cutoff. |
| Air absorption | Rolloff + low-pass curve | Attenuation air absorption | `attenuation_filter_cutoff_hz` per `AudioStreamPlayer3D`, falls with distance and rain. |
| Listener low-pass | Mixer snapshots | Submix effects | `AudioEffectLowPassFilter` on the SFX bus, glides (log domain) underground or in a storm. |
| Voice limiting | AudioSource priority, max voices | Sound Concurrency | `audio_voices.gd`: 24 voices, 5 per sound; quietest/oldest culled, weaker newcomer dropped. |
| Pitch/volume variation | Random pitch scripts | Sound Cue Modulator | +-8 % pitch, +-1.5 dB per one-shot. |
| Sidechain ducking | Mixer Duck Volume | Sound Mix / submix sidechain | `audio_ducking.gd`: death, outpost, skill-up, kills dip Music (Ambience 40 %); fast attack, slow release. |
| Bus layout + sliders | AudioMixer groups | Sound Classes | Master / Music / SFX / UI / Ambience (`audio_mix.gd`), persisted in `user://albion_after_audio.cfg`; Ctrl+Home picks the bus, Ctrl+PgUp/PgDn changes it. |
| Weather loops | Looping sources | Ambient Sound / MetaSounds noise | `audio_ambient.gd`: generated rain hiss and wind rumble loops scaled by storm and wind, quieter under cover. |
| Biome ambience beds | Mixer snapshots | Ambient Sound actors | Ambience loop pitch/level glides per biome, quieter at night and underground. |

Not done: doppler on projectiles (one-shots are static on the client), HRTF or
convolution reverb.
