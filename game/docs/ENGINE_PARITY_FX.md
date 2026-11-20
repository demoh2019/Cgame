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

## Character animation (Unity Animation Rigging + Mecanim / Unreal Control Rig + AnimBP)

Static helpers in `scripts/client/character_anim.gd`, runtime driver
`scripts/client/character_anim_modifier.gd` (a `SkeletonModifier3D` that runs after the AnimationPlayer and undoes
its own changes each pass), wiring in `character_model.gd` and one crowd call in `entity_view.gd`.

| Feature | Unity | Unreal | Cgame now |
| --- | --- | --- | --- |
| Foot IK on slopes | Animation Rigging Two Bone IK / Animator IK | Foot Placement / Two Bone IK | Analytic two-bone leg solve to `world.height_at`, planted-foot weight (swing legs untouched), foot tilt to ground normal |
| Pelvis height adjust | Hips offset in IK | Pelvis offset in Foot Placement | Hips follow the lower foot target, clamped 0.35 m, smoothed |
| Head look-at | Multi-Aim / LookAt IK | Look At node | Neck 40% + head 60%, yaw/pitch clamped, eases off when the target is behind; camera for the nearest characters |
| Lean into turns | Animation Rigging damped transform | Control Rig lean | Spine roll from measured yaw rate, forward pitch with speed |
| Breathing idle additive | Additive layer | Additive anim | Chest pitch sine, fades while moving |
| Additive hit reaction | Additive animation layer | Additive hit / Physical Animation | Spring-damper flinch on the spine; moving or acting characters are not interrupted, only heavy idle hits also play the clip |
| Upper/lower body layering | Avatar Mask layer | Layered Blend Per Bone | Second `AnimationPlayer` with upper-body-only clip copies, so a swing plays while the legs keep walking |
| Smooth locomotion rate | Blend Tree speed | BlendSpace1D play rate | Playback rate eased (3/s) within the same clip |
| Animation LOD (URO) | Animator Culling / LOD | Update Rate Optimization | 5 tiers by distance: IK/look off, then 30/15/8 Hz manual `advance`, modifiers off |
| Crowd anim budget | n/a | Animation Budget Allocator | Only the nearest 0/4/8/14 characters (quality tier) run IK and look-at |
| Ragdoll compatibility | Ragdoll takeover | Physics blend | `start_ragdoll` resets and disables the modifier and layer |

Tests: `tests/test_animation_parity.gd`. The live-skeleton and `CharacterModel` checks need a running scene tree and
are skipped under `run_all.gd`'s `_initialize`; run the suite after a `process_frame` to include them.
## UI, input, accessibility and localization

All settings live in `user://albion_after_graphics.cfg` (sections `interface`, `bindings`) next to the graphics
quality, are client-only, and are edited in the Esc / gamepad-Menu settings window. One node,
`scripts/client/ui_accessibility_layer.gd`, is added by `online_main.gd`; the logic is in static `ui_*.gd` helpers.

| Feature | Files | Unity / Unreal equivalent |
|---|---|---|
| Esc / Menu settings window (Gameplay, Controls, Accessibility tabs) | `ui_pause_menu.gd` | Unity settings UI / UE pause + options menu (CommonUI) |
| Key rebinding with conflict swap, reset, persistence (move, sprint, crouch, pause, FPS) | `ui_input_rebind.gd` | Input System `PerformInteractiveRebinding` / Enhanced Input player mappable keys |
| Gamepad: pad buttons drive the existing hotkeys (A interact, X attack, Y inventory ...), stick clicks sprint/crouch, Menu pauses | `ui_gamepad.gd` | Input System gamepad control scheme / UE gamepad bindings |
| On-screen prompts that switch by last-used device, Xbox or PlayStation glyphs | `ui_gamepad.gd`, layer | CommonUI input-type-aware action widgets / Input System control-scheme glyphs |
| UI scale slider 0.75-1.75 (window `content_scale_factor`) | `ui_access.gd`, `ui_settings.gd` | Canvas Scaler / UE DPI scale |
| Colour-blind filters: protanopia, deuteranopia, tritanopia (Machado matrices, full-screen shader) | `ui_colorblind.gd` | UE "Color Blind Mode"; Unity post-processing colour matrix |
| Closed captions with direction and distance, e.g. `[Gunshot, left, 24 m]`, three sizes | `ui_captions.gd` | UE closed captions / sound-class subtitles |
| Russian/English `Translation` built in code, English text as key so existing Labels/Buttons/tooltips translate automatically, language picker, OS-locale default | `ui_localization.gd` | Unity Localization package string tables / UE FText string tables |
| Toggle (instead of hold) sprint and crouch, mutually exclusive latches | `ui_settings.gd` (`resolve_hold`), `ui_access.gd` | UE Enhanced Input "hold vs toggle" triggers |
| Reduce screen shake (camera trauma scale) | `online_main.gd` `_shake` | UE camera-shake scale / Cinemachine impulse gain |
| Reduce flashes (no lightning flash, no hit flash or low-health pulse) | `online_main.gd`, `hud_skin.gd` | UE/Unity photosensitivity options |
| High-contrast interface (white outlined text, black ink on parchment) | `ui_access.gd` | OS/UE high-contrast mode |
| FPS / frame time / draw call overlay (default backslash) | layer | `stat fps` / Unity Rendering Debugger |

Limits: only the polled movement actions are rebindable; one-shot hotkeys stay keycode-matched (see F2). The gamepad
has no aim stick yet. In-world strings from `hud.say` stay English. Tests: `tests/test_ui_parity.gd`.

## Physics and world interactivity (cosmetic, client only)

Everything below lives on the client, is capped per `GraphicsQuality.level()` (0..3) and never touches
server/simulation state. Entry point: `scripts/client/physics_world_fx.gd` (fed by `online_main.gd` events).
Tests: `tests/test_physics_parity.gd`.

| Feature | Unity | Unreal | Cgame |
| --- | --- | --- | --- |
| Barricade destruction into debris | fractured prefab + Rigidbody chunks | Chaos Destruction geometry collection | `physics_debris.gd` — `barricade_broken` bursts wood chunk `RigidBody3D`s (budget 0/10/24/48), own layer, one heightmap collider following the player, sleep then shrink away, pooled |
| Spent casings | pooled Rigidbody particles | Niagara mesh particles with collision | `physics_debris.gd` — ranged `attack` ejects brass casings (0/0/10/24) |
| Blast impulse field | `AddExplosionForce` | Radial Force / Physics Field | `physics_debris.gd` `blast()` — sphere query, quadratic falloff, pushes chunks and ragdoll `PhysicalBone3D` (`Ragdoll.LAYER`); driven by barricade break, flash/ember throws, knockback, infected deaths (`physics_world_fx.blast_for`) |
| Buoyancy bobbing | Buoyancy scripts / Water system | Chaos buoyancy / Water plugin | chunks float (density 0.6) on a travelling swell, casings sink (`buoyancy_force`, `surface_height`) |
| Debris budget & sleeping | Rigidbody sleep, object pools | Chaos sleep + pooling | oldest body recycled over the tier cap; asleep >1.5 s or older than 9 s retires |
| Loot bag drop bounce | dropped Rigidbody + PhysicMaterial | physics actor spawn | `loot_drop_bounce.gd` — damped analytic bounce and landing squash on the bag mesh, wired in `entity_view._process` |
| Grass/bush bend around player | interactive-grass shader | MPC grass interaction | `plant_interaction.gd` + `assets/shaders/plant_interaction.gdshaderinc` — global `aa_plant_bend` (x,z,radius,strength) used by `grass_field.gd` and `foliage.gd`; speed-scaled, radius 0/1.1/1.5/1.9 m |
| Tree/bush shake on hit/harvest | wind zone + script | Foliage interaction | global `aa_plant_shake` with damped envelope; `gathered` shakes hardest |
| Cloth banners | Cloth component | Chaos Cloth | `cloth_flag.gd` — outposts get a subdivided pole-pinned plane with a vertex-shader ripple, droop and wind lift from `aa_vegetation_wind` (segments 0/6/12/20; Low keeps the rigid flag) |
| Swinging lanterns on chains | HingeJoint chain | Physics Constraint chain | `hanging_lantern.gd` — verlet chain pinned at the top, wind-driven, 0/3/5/8 links; one on every outpost pole |
| Rope/cable sag | Obi/Rope packages | Cable Component | `hanging_lantern.rope_points` / `build_rope_mesh` — parabolic sag tube; guy rope on outpost poles |

Not covered: skinned cloth on characters, soft bodies, fluid simulation.
